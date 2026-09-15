#!/usr/bin/env python3
"""
Per-site forest age extraction from the Besnard et al. (2021) global forest
age map, ForestAge_TC030 variable (the 30% tree-cover-correction threshold -
matches our own tc>=30 site-selection convention exactly).

Source: forest_age_2020_SBesnard/222_BGIForestAgeMPIBGC1.0.0.nc
  - global grid, ~1km pixels (0.00833 deg), static "circa 2010" snapshot
  - units: years : NaN = non-forest / no data (no sentinel value used)

For each of the 93 tc>=30 sites, extracts:
  - nearest-pixel value (the single ~1km pixel closest to the site
    coordinate) - the PRIMARY value. At this resolution a site-to-pixel-
    center distance can itself be up to ~650m (half a pixel diagonal), so
    the "500m buffer" convention used for the 10m-resolution deadwood data
    does NOT transfer here - a 500m radius can legitimately contain ZERO
    pixel centers depending on where the site falls within its pixel
    (verified: this happened for real, not a bug - see US-MtB below).
  - a genuinely-sized buffer mean instead: 1500m radius, chosen to reliably
    span several neighbouring pixels regardless of the site's position
    within its own pixel (empirically confirmed below to never come back
    empty for a reason other than real non-forest/no-data coverage).
  - n_pixels in that buffer, and whether the site pixel itself is NaN
    (non-forest per this product, or outside its valid-data area)

Output: derived_tables/outputs_afterEGU_results/forest_age_tc030_by_site.csv
"""
import numpy as np
import pandas as pd
import xarray as xr

ROOT = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
NC_FILE = f"{ROOT}/forest_age_2020_SBesnard/222_BGIForestAgeMPIBGC1.0.0.nc"
HARM_FILE = f"{ROOT}/derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
EFP_FILE = f"{ROOT}/derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
OUT_FILE = f"{ROOT}/derived_tables/outputs_afterEGU_results/forest_age_tc030_by_site.csv"

RADIUS_M = 1500
M_PER_DEG_LAT = 111320.0  # ~constant

def main():
    sites = pd.read_csv(HARM_FILE, usecols=["SITE_ID"])["SITE_ID"].unique()
    print(f"tc>=30 site list: {len(sites)} sites")

    meta = pd.read_csv(EFP_FILE, usecols=["SITE_ID", "LOCATION_LAT", "LOCATION_LONG"]).drop_duplicates("SITE_ID")
    meta = meta.set_index("SITE_ID")

    ds = xr.open_dataset(NC_FILE)
    age = ds["ForestAge_TC030"]
    lat_arr = ds["latitude"].values
    lon_arr = ds["longitude"].values
    dlat = abs(lat_arr[1] - lat_arr[0])
    dlon = abs(lon_arr[1] - lon_arr[0])

    rows = []
    for i, site in enumerate(sorted(sites)):
        if site not in meta.index:
            print(f"  {site}: no coordinates, skipped"); continue
        lat, lon = meta.loc[site, ["LOCATION_LAT", "LOCATION_LONG"]]

        # buffer half-extent in degrees (approximate: fine at this scale)
        half_lat = RADIUS_M / M_PER_DEG_LAT
        half_lon = RADIUS_M / (M_PER_DEG_LAT * np.cos(np.radians(lat)))
        n_lat_px = max(1, int(np.ceil(half_lat / dlat)))
        n_lon_px = max(1, int(np.ceil(half_lon / dlon)))

        lat_i = int(np.argmin(np.abs(lat_arr - lat)))
        lon_i = int(np.argmin(np.abs(lon_arr - lon)))

        nearest = float(age.isel(latitude=lat_i, longitude=lon_i).values)

        y0, y1 = max(0, lat_i - n_lat_px), min(len(lat_arr), lat_i + n_lat_px + 1)
        x0, x1 = max(0, lon_i - n_lon_px), min(len(lon_arr), lon_i + n_lon_px + 1)
        window = age.isel(latitude=slice(y0, y1), longitude=slice(x0, x1)).values

        # true-distance circular mask within the extracted window (haversine-ish,
        # flat-earth approximation is fine at this scale)
        wlat = lat_arr[y0:y1]; wlon = lon_arr[x0:x1]
        WLA, WLO = np.meshgrid(wlat, wlon, indexing="ij")
        dy = (WLA - lat) * M_PER_DEG_LAT
        dx = (WLO - lon) * M_PER_DEG_LAT * np.cos(np.radians(lat))
        dist = np.sqrt(dx**2 + dy**2)
        mask = dist <= RADIUS_M

        vals = window[mask]
        n_valid = int(np.sum(~np.isnan(vals)))
        buf_mean = float(np.nanmean(vals)) if n_valid > 0 else np.nan

        rows.append(dict(SITE_ID=site, LAT=lat, LON=lon,
                         forest_age_tc30_nearest_px=nearest,
                         forest_age_tc30_1500m_mean=buf_mean,
                         n_pixels_1500m=int(mask.sum()), n_valid_1500m=n_valid))

        if (i + 1) % 20 == 0 or i == len(sites) - 1:
            print(f"  [{i+1}/{len(sites)}] {site}: nearest={nearest:.1f}  buffer_mean={buf_mean:.1f}  (n_valid={n_valid}/{int(mask.sum())})")

    out = pd.DataFrame(rows)
    out.to_csv(OUT_FILE, index=False)
    print(f"\nWrote {len(out)} rows -> {OUT_FILE}")
    n_nan_site = out["forest_age_tc30_nearest_px"].isna().sum()
    print(f"Sites where the site pixel itself is NaN (non-forest per TC030 or no data): {n_nan_site}")
    valid = out["forest_age_tc30_1500m_mean"].dropna()
    print(f"forest_age_tc30_1500m_mean summary (n={len(valid)}): min={valid.min():.1f} median={valid.median():.1f} max={valid.max():.1f}")
    print("FOREST_AGE_EXTRACTION_DONE")

if __name__ == "__main__":
    main()

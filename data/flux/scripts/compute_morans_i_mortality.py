#!/usr/bin/env python3
"""
Moran's I (spatial autocorrelation) of the deadwood/mortality raster layer,
per site-year, for the tc>=30 dataset (93 sites / 395 site-years).

Buffer geometry is EMPIRICALLY reverse-engineered to match the canonical
final_disturbance_v2-2_multibuffer.csv exactly (verified against AT-Zoe/2020:
100m buffer diff=0.0000, 500m buffer diff=0.002, i.e. rounding noise):
  - circular buffer (distance <= radius_m from the site's exact UTM
    coordinate), NOT a square pixel window
  - 10 m pixels (the zarr's true resolution - NOT the 100m PIXEL_SIZE assumed
    by the stale scripts/extract_mortality_from_zarr.py, which appears to be
    an abandoned exploratory script unrelated to the canonical table)
  - raw uint8 values scaled by /2.55 (255 -> 100%)

Moran's I uses ROOK contiguity (4-neighbour: up/down/left/right) restricted
to pixels inside the circular buffer, computed in pure numpy (no scipy/pysal
dependency) via array shifting - efficient on a regular grid.

Metric = Moran's I of the raw `deadwood` layer (0-100%, continuous), the
same underlying layer that `absolute_mortality_500m` already averages - so
this is a direct spatial-pattern companion to that existing variable, not a
new concept.

Output: derived_tables/outputs_afterEGU_results/morans_i_mortality_tc30.csv
  SITE_ID, YEAR, morans_i_500m, deadwood_mean_500m_check, n_pixels_500m
"""
import sys, time
import numpy as np
import pandas as pd
import zarr
from pyproj import Transformer, CRS

ROOT = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
ZARR_DIR = f"{ROOT}/deadtree/deadtrees_maps_v2-2"
HARM_FILE = f"{ROOT}/derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
EFP_FILE = f"{ROOT}/derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
OUT_FILE = f"{ROOT}/derived_tables/outputs_afterEGU_results/morans_i_mortality_tc30.csv"

RADIUS_M = 500
SCALE = 255.0 / 100.0

def utm_transform(lat, lon):
    zone = int((lon + 180) / 6) + 1
    epsg = 32600 + zone if lat >= 0 else 32700 + zone
    tr = Transformer.from_crs(CRS.from_epsg(4326), CRS.from_epsg(epsg), always_xy=True)
    return tr.transform(lon, lat)

def buffer_mask(x, y, ux, uy, radius_m):
    XX, YY = np.meshgrid(x, y)
    return np.sqrt((XX - ux) ** 2 + (YY - uy) ** 2) <= radius_m

def morans_i_rook(vals2d, mask2d):
    v = vals2d.astype(float).copy()
    m = mask2d
    v[~m] = np.nan
    xbar = np.nanmean(v)
    d = v - xbar
    mh = m[:, :-1] & m[:, 1:]
    mv = m[:-1, :] & m[1:, :]
    ph = (d[:, :-1] * d[:, 1:])[mh]
    pv = (d[:-1, :] * d[1:, :])[mv]
    num = 2 * (ph.sum() + pv.sum())
    W = 2 * (mh.sum() + mv.sum())
    n = int(m.sum())
    den = np.nansum(d[m] ** 2)
    if W == 0 or den == 0:
        return np.nan, n, W
    return float((n / W) * (num / den)), n, int(W)

def main():
    harm = pd.read_csv(HARM_FILE, usecols=["SITE_ID", "YEAR"]).drop_duplicates()
    site_years = harm.groupby("SITE_ID")["YEAR"].apply(list).to_dict()
    sites = sorted(site_years.keys())
    print(f"tc>=30 dataset: {len(sites)} sites, {sum(len(v) for v in site_years.values())} site-years")

    meta = pd.read_csv(EFP_FILE, usecols=["SITE_ID", "LOCATION_LAT", "LOCATION_LONG"]).drop_duplicates("SITE_ID")
    meta = meta.set_index("SITE_ID")

    rows = []
    missing_zarr, missing_year, t0 = [], [], time.time()

    for i, site in enumerate(sites):
        zpath = f"{ZARR_DIR}/{site}_inference.zarr"
        try:
            z = zarr.open(zpath, mode="r")
        except Exception:
            missing_zarr.append(site)
            continue
        if site not in meta.index:
            missing_zarr.append(site + " (no coords)")
            continue
        lat, lon = meta.loc[site, ["LOCATION_LAT", "LOCATION_LONG"]]
        ux, uy = utm_transform(lat, lon)
        x = np.array(z["x"][:]); y = np.array(z["y"][:])
        times = list(z["time"][:])
        mask = buffer_mask(x, y, ux, uy, RADIUS_M)

        for yr in site_years[site]:
            ys = str(int(yr))
            if ys not in times:
                missing_year.append(f"{site}/{ys}")
                continue
            ti = times.index(ys)
            dw = np.array(z["deadwood"][ti]).astype(float) / SCALE
            I, n, W = morans_i_rook(dw, mask)
            dmean = float(np.nanmean(dw[mask]))
            rows.append(dict(SITE_ID=site, YEAR=int(yr), morans_i_500m=I,
                             deadwood_mean_500m_check=dmean, n_pixels_500m=n))

        if (i + 1) % 10 == 0 or i == len(sites) - 1:
            print(f"  [{i+1}/{len(sites)}] {site} done ({time.time()-t0:.1f}s elapsed)")

    out = pd.DataFrame(rows)
    out.to_csv(OUT_FILE, index=False)
    print(f"\nWrote {len(out)} rows -> {OUT_FILE}")
    if missing_zarr:
        print(f"MISSING zarr/coords ({len(missing_zarr)}): {missing_zarr}")
    if missing_year:
        print(f"MISSING year in zarr time dim ({len(missing_year)}): {missing_year[:10]}{'...' if len(missing_year)>10 else ''}")
    print(f"\nMoran's I summary: min={out.morans_i_500m.min():.3f} median={out.morans_i_500m.median():.3f} max={out.morans_i_500m.max():.3f}")
    print("MORANS_I_EXTRACTION_DONE")

if __name__ == "__main__":
    main()

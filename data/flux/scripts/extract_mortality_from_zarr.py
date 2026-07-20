#!/usr/bin/env python3
"""
Extract mortality metrics from deadtree zarr files.
Uses xarray to read zarr and calculates mortality metrics per site-year at 100-500m buffers.
"""

import pandas as pd
import numpy as np
import xarray as xr
from pathlib import Path
from pyproj import Transformer, CRS
import warnings

warnings.filterwarnings('ignore')

# Configuration
BASE_DIR = Path('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')
ZARR_DIR = BASE_DIR / 'deadtree' / 'deadtrees_maps_v2-2'
METADATA_FILE = BASE_DIR / 'Flux4Daniel' / 'fluxnet_site_metadata_clean_with_elevation.csv'
OUTPUT_FILE = BASE_DIR / 'derived_tables' / 'outputs_afterEGU_results' / 'mortality_from_zarr.csv'

BUFFERS_M = [100, 200, 300, 400, 500]  # Buffer sizes in meters
PIXEL_SIZE = 100  # 100m pixels

print('\n' + '='*70)
print('EXTRACTING MORTALITY FROM DEADTREE ZARR FILES')
print('='*70 + '\n')

# Step 1: Load site metadata
print('STEP 1: Loading site metadata...')
metadata = pd.read_csv(METADATA_FILE)
print(f'  Loaded {len(metadata)} sites')
print(f'  Columns: {list(metadata.columns[:5])}...\n')

# Step 2: Find available zarr files
print('STEP 2: Finding available zarr files...')
zarr_files = sorted(list(ZARR_DIR.glob('*_inference.zarr')))
zarr_sites = {f.stem.replace('_inference', ''): f for f in zarr_files}
print(f'  Found {len(zarr_sites)} zarr files\n')

# Step 3: Extract mortality metrics
print('STEP 3: Extracting mortality metrics...\n')

results = []
failed_sites = []

for site_id in sorted(zarr_sites.keys()):
    # Get coordinates
    site_meta = metadata[metadata['SITE_ID'] == site_id]
    if site_meta.empty:
        failed_sites.append((site_id, 'Not in metadata'))
        continue

    lat = site_meta['LOCATION_LAT'].values[0]
    lon = site_meta['LOCATION_LONG'].values[0]

    try:
        # Load zarr file
        zarr_path = zarr_sites[site_id]
        ds = xr.open_zarr(str(zarr_path))

        # Get CRS from zarr file
        crs_str = ds.attrs.get('crs_wkt', '')
        if 'WGS 84 / UTM zone' in crs_str:
            zone_match = crs_str.split('UTM zone ')[1].split('"')[0]
            utm_zone = int(zone_match[:-1])  # Remove N/S suffix
            is_north = 'N' in zone_match
            utm_crs = CRS.from_epsg(32600 + utm_zone if is_north else 32700 + utm_zone)
        else:
            # Try to infer from coordinates
            utm_zone = int((lon + 180) / 6) + 1
            is_north = lat >= 0
            utm_crs = CRS.from_epsg(32600 + utm_zone if is_north else 32700 + utm_zone)

        # Transform coordinates
        transformer = Transformer.from_crs(CRS.from_epsg(4326), utm_crs, always_xy=True)
        utm_x, utm_y = transformer.transform(lon, lat)

        # Extract forest and deadwood for each buffer and year
        for year_str in ds['time'].values:
            year = int(year_str)

            forest_data = ds['forest'].sel(time=year_str).values
            deadwood_data = ds['deadwood'].sel(time=year_str).values

            x_coords = ds['x'].values
            y_coords = ds['y'].values

            # Find nearest pixel
            x_idx = np.argmin(np.abs(x_coords - utm_x))
            y_idx = np.argmin(np.abs(y_coords - utm_y))

            # Extract within buffers
            for buffer_m in BUFFERS_M:
                buffer_px = int(np.ceil(buffer_m / PIXEL_SIZE))

                x_start = max(0, x_idx - buffer_px)
                x_end = min(len(x_coords), x_idx + buffer_px + 1)
                y_start = max(0, y_idx - buffer_px)
                y_end = min(len(y_coords), y_idx + buffer_px + 1)

                forest_subset = forest_data[y_start:y_end, x_start:x_end].astype(float)
                deadwood_subset = deadwood_data[y_start:y_end, x_start:x_end].astype(float)

                # Calculate metrics (values are 0-100 percentages)
                forest_mean = np.nanmean(forest_subset)
                deadwood_mean = np.nanmean(deadwood_subset)

                # Mortality intensity = deadwood / forest (if forest > 0)
                if forest_mean > 0:
                    mortality_intensity = (deadwood_mean / forest_mean) * 100
                else:
                    mortality_intensity = np.nan

                results.append({
                    'SITE_ID': site_id,
                    'YEAR': year,
                    f'forest_mean_pct_{buffer_m}m': forest_mean,
                    f'deadwood_mean_pct_{buffer_m}m': deadwood_mean,
                    f'mortality_intensity_pct_{buffer_m}m': mortality_intensity,
                })

        print(f'  ✓ {site_id}: extracted {len(ds["time"].values)} years')

    except Exception as e:
        failed_sites.append((site_id, str(e)))
        print(f'  ✗ {site_id}: {str(e)[:50]}')

print(f'\nSuccessfully extracted: {len([r for r in results if r["SITE_ID"] not in [f[0] for f in failed_sites]])} rows')
print(f'Failed sites: {len(failed_sites)}\n')

# Step 4: Save results
if results:
    df_results = pd.DataFrame(results)

    # Pivot to wide format (one row per site-year)
    df_wide = df_results.groupby(['SITE_ID', 'YEAR']).first().reset_index()

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    df_wide.to_csv(OUTPUT_FILE, index=False)

    print(f'Saved {len(df_wide)} site-years to: {OUTPUT_FILE}')
    print(f'  Size: {OUTPUT_FILE.stat().st_size / 1024 / 1024:.1f} MB\n')

    print('='*70)
    print('SUMMARY')
    print('='*70)
    print(f'Total site-years: {len(df_wide)}')
    print(f'Unique sites: {df_wide["SITE_ID"].nunique()}')
    print(f'Year range: {df_wide["YEAR"].min()}-{df_wide["YEAR"].max()}')
    print(f'Columns: {list(df_wide.columns)}')
    print()


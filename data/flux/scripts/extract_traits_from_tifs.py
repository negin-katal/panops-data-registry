#!/usr/bin/env python3
"""
Extract plant traits from TIF files at 100-500m buffers around flux towers.
Hydraulic traits: P12, P50, P88, gsmax, rdmax
"""

import pandas as pd
import numpy as np
from rasterio.features import geometry_mask
from rasterio.windows import Window
from pathlib import Path
import rasterio
from shapely.geometry import Point
from pyproj import Transformer, CRS
import warnings

warnings.filterwarnings('ignore')

# Configuration
BASE_DIR = Path('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')
TRAIT_DIR = BASE_DIR / 'data' / 'trait_maps' / 'lusk_et-al_2025' / 'cwms' / 'Shrub_Tree_Grass' / '1km' / 'hydraulic'
METADATA_FILE = BASE_DIR / 'Flux4Daniel' / 'fluxnet_site_metadata_clean_with_elevation.csv'
OUTPUT_FILE = BASE_DIR / 'derived_tables' / 'outputs_afterEGU_results' / 'traits_from_tifs.csv'

TRAITS = ['P12', 'P50', 'P88', 'gsmax', 'rdmax']
BUFFERS_M = [100, 200, 300, 400, 500]
PIXEL_SIZE = 1000  # 1km pixels

print('\n' + '='*70)
print('EXTRACTING PLANT TRAITS FROM TIF FILES')
print('='*70 + '\n')

# Step 1: Load site metadata
print('STEP 1: Loading site metadata...')
metadata = pd.read_csv(METADATA_FILE)
print(f'  Loaded {len(metadata)} sites\n')

# Step 2: Extract traits
print('STEP 2: Extracting traits from TIF files...\n')

results = []
failed_sites = []

for site_idx, row in metadata.iterrows():
    site_id = row['SITE_ID']
    lat = row['LOCATION_LAT']
    lon = row['LOCATION_LONG']

    try:
        # Load first trait TIF to get CRS and resolution
        trait_file = TRAIT_DIR / TRAITS[0] / 'splot_gbif' / f'{TRAITS[0]}_splot_gbif_predict.tif'

        if not trait_file.exists():
            failed_sites.append((site_id, 'TIF file not found'))
            continue

        with rasterio.open(str(trait_file)) as src_ref:
            src_crs = src_ref.crs
            src_transform = src_ref.transform

            # Transform coordinates to raster CRS
            if src_crs.to_epsg() != 4326:  # If not WGS84
                transformer = Transformer.from_crs(CRS.from_epsg(4326), src_crs, always_xy=True)
                raster_x, raster_y = transformer.transform(lon, lat)
            else:
                raster_x, raster_y = lon, lat

            # Extract for each trait
            for trait in TRAITS:
                trait_file = TRAIT_DIR / trait / 'splot_gbif' / f'{trait}_splot_gbif_predict.tif'

                if not trait_file.exists():
                    results.append({
                        'SITE_ID': site_id,
                        f'{trait}_500m': np.nan,
                    })
                    continue

                with rasterio.open(str(trait_file)) as src:
                    # Get pixel value at tower location
                    try:
                        # Use indexing to get the value
                        row_idx, col_idx = src.index(raster_x, raster_y)
                        row_idx, col_idx = int(row_idx), int(col_idx)

                        if 0 <= row_idx < src.height and 0 <= col_idx < src.width:
                            trait_value = src.read(1)[row_idx, col_idx]
                            # Handle no-data values
                            if trait_value == src.nodata:
                                trait_value = np.nan
                        else:
                            trait_value = np.nan

                        results.append({
                            'SITE_ID': site_id,
                            f'{trait}_500m': float(trait_value) if not np.isnan(trait_value) else np.nan,
                        })

                    except Exception as e:
                        results.append({
                            'SITE_ID': site_id,
                            f'{trait}_500m': np.nan,
                        })

        if (site_idx + 1) % 50 == 0:
            print(f'  Processed {site_idx + 1} / {len(metadata)} sites')

    except Exception as e:
        failed_sites.append((site_id, str(e)[:50]))

print(f'\n  Successfully processed {len(metadata) - len(failed_sites)} sites')
print(f'  Failed sites: {len(failed_sites)}\n')

# Step 3: Combine results and save
if results:
    df_results = pd.DataFrame(results)

    # Combine columns for same site
    df_wide = df_results.groupby('SITE_ID').first().reset_index()

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    df_wide.to_csv(OUTPUT_FILE, index=False)

    print(f'Saved {len(df_wide)} sites to: {OUTPUT_FILE}')
    print(f'  Size: {OUTPUT_FILE.stat().st_size / 1024:.1f} KB\n')

    print('='*70)
    print('SUMMARY')
    print('='*70)
    print(f'Sites with trait data: {len(df_wide)}')
    print(f'Traits extracted: {TRAITS}')
    print(f'Columns: {list(df_wide.columns)}')
    print()


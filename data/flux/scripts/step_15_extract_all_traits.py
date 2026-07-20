#!/usr/bin/env python3
"""
Extract ALL plant traits from TIF files using GDAL
- Hydraulic: P12, P50, P88, gsmax, rdmax (from hydraulic/ folder)
- Analysis-ready: 18 coded traits (from analysis-ready/ folder)
"""

import os
import sys
import subprocess
import pandas as pd
import numpy as np
from pathlib import Path

# Setup paths
TRAIT_BASE = "/mnt/gsdata/projects/panops/panops-data-registry/data/trait_maps/lusk_et-al_2025/cwms/Shrub_Tree_Grass/1km"
FLUX_DIR = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
OUTPUT_DIR = f"{FLUX_DIR}/derived_tables/outputs_afterEGU_results/v10"

os.chdir(FLUX_DIR)

# Trait codec for analysis-ready folder
ANALYSIS_CODEC = {
    '4': 'SSD',
    '6': 'rooting_depth',
    '11': 'SLA',
    '13': 'Leaf_C',
    '14': 'Leaf_N_mass',
    '15': 'Leaf_P',
    '46': 'Leaf_thickness',
    '50': 'Leaf_N_area',
    '55': 'Leaf_dry_mass',
    '78': 'Leaf_delta15N',
    '145': 'Leaf_width',
    '146': 'Leaf_CN_ratio',
    '169': 'Stem_conduit_density',
    '281': 'Stem_conduit_diameter',
    '3112': 'Leaf_area_v1',
    '3113': 'Leaf_area_v2',
    '3114': 'Leaf_area_v3',
    '3117': 'Leaf_area_v4',
}

print("\n" + "="*80)
print("EXTRACT ALL PLANT TRAITS FROM TIF FILES")
print("="*80 + "\n")

# Step 1: Load flux tower coordinates
print("Step 1: Loading flux tower coordinates...")
try:
    df_rf = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready.csv', usecols=['SITE_ID'])
    sites_unique = df_rf.drop_duplicates('SITE_ID').reset_index(drop=True)

    # Load metadata
    meta_file = 'fluxnet_2017_2025_V02/EFP_outputs_corrected/EFP_metadata_monthlyMeteo_WIDE.csv'
    df_meta = pd.read_csv(meta_file, usecols=['SITE_ID', 'LOCATION_LAT', 'LOCATION_LONG'])
    df_meta = df_meta.drop_duplicates('SITE_ID')

    sites_unique = sites_unique.merge(df_meta, on='SITE_ID', how='left')

    print(f"  Loaded {len(sites_unique)} unique sites")
    print(f"  Lat range: [{sites_unique['LOCATION_LAT'].min():.2f}, {sites_unique['LOCATION_LAT'].max():.2f}]")
    print(f"  Lon range: [{sites_unique['LOCATION_LONG'].min():.2f}, {sites_unique['LOCATION_LONG'].max():.2f}]\n")

except Exception as e:
    print(f"  ERROR: {e}\n")
    sys.exit(1)

# Function to extract value using gdalinfo
def extract_tif_value(tif_file, lon, lat):
    """Extract raster value at point using gdal_translate"""
    try:
        # Use gdal_translate to sample a 1x1 pixel at the location
        # Create a VRT that defines the point location
        cmd = f"gdallocationinfo -valonly '{tif_file}' {lon} {lat}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)

        if result.returncode == 0 and result.stdout.strip():
            try:
                val = float(result.stdout.strip())
                return val if val > 0 else np.nan
            except:
                return np.nan
        return np.nan
    except:
        return np.nan

# Step 2: Extract hydraulic traits
print("Step 2: Extracting hydraulic traits...")
hydraulic_traits = ['P12', 'P50', 'P88', 'gsmax', 'rdmax']
trait_data = {'SITE_ID': sites_unique['SITE_ID'].values}

for trait in hydraulic_traits:
    trait_dir = os.path.join(TRAIT_BASE, 'hydraulic', trait)
    tif_files = list(Path(trait_dir).glob('*.tif'))

    if not tif_files:
        print(f"  {trait}: WARNING - no TIF found")
        trait_data[f'{trait}_mean'] = [np.nan] * len(sites_unique)
        continue

    tif_file = str(tif_files[0])
    print(f"  {trait}: extracting...", end='', flush=True)

    trait_values = []
    for idx, row in sites_unique.iterrows():
        lat = row['LOCATION_LAT']
        lon = row['LOCATION_LONG']

        if pd.isna(lat) or pd.isna(lon):
            trait_values.append(np.nan)
        else:
            val = extract_tif_value(tif_file, lon, lat)
            trait_values.append(val)

    n_extracted = sum(1 for v in trait_values if not np.isnan(v))
    print(f" ✓ {n_extracted}/{len(trait_values)} sites")
    trait_data[f'{trait}_mean'] = trait_values

print()

# Step 3: Extract analysis-ready traits
print("Step 3: Extracting analysis-ready traits...")
analysis_path = os.path.join(TRAIT_BASE, 'analysis-ready')

for tif_file in sorted(Path(analysis_path).glob('X*.tif')):
    basename = tif_file.name

    # Extract code (e.g., "X13_mean..." -> "13")
    code = basename.split('_')[0].replace('X', '')
    trait_name = ANALYSIS_CODEC.get(code)

    if not trait_name:
        continue

    print(f"  X{code} ({trait_name}): extracting...", end='', flush=True)

    trait_values = []
    for idx, row in sites_unique.iterrows():
        lat = row['LOCATION_LAT']
        lon = row['LOCATION_LONG']

        if pd.isna(lat) or pd.isna(lon):
            trait_values.append(np.nan)
        else:
            val = extract_tif_value(str(tif_file), lon, lat)
            trait_values.append(val)

    n_extracted = sum(1 for v in trait_values if not np.isnan(v))
    print(f" ✓ {n_extracted}/{len(trait_values)} sites")
    trait_data[f'{trait_name}_mean'] = trait_values

print()

# Step 4: Save all traits
print("Step 4: Saving all traits...")
df_traits = pd.DataFrame(trait_data)

out_file = os.path.join(OUTPUT_DIR, 'plant_traits_all_extracted.csv')
df_traits.to_csv(out_file, index=False)

print(f"  Saved: {out_file}")
print(f"  Rows: {len(df_traits)}")
print(f"  Columns: {len(df_traits.columns)}")
print(f"    - Hydraulic: {len(hydraulic_traits)}")
print(f"    - Analysis-ready: {len([c for c in df_traits.columns if '_mean' in c and c not in [f'{t}_mean' for t in hydraulic_traits]])}\n")

# Summary stats
print("Trait availability summary:")
trait_cols = [c for c in df_traits.columns if c != 'SITE_ID']
for col in sorted(trait_cols):
    n_avail = df_traits[col].notna().sum()
    pct = 100 * n_avail / len(df_traits)
    print(f"  {col}: {n_avail}/{len(df_traits)} ({pct:.1f}%)")

print("\n" + "="*80)
print("✅ EXTRACTION COMPLETE")
print("="*80 + "\n")

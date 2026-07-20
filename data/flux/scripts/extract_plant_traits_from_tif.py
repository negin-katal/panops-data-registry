#!/usr/bin/env python3
"""
Extract plant traits from TIF files (hydraulic + analysis-ready)
For each flux tower location, extract values at 100-500m buffers
"""

import os
import glob
import pandas as pd
import numpy as np
from rasterio.mask import mask
from shapely.geometry import Point
import rasterio
import warnings
warnings.filterwarnings('ignore')

# Paths
TRAIT_BASE = "/mnt/gsdata/projects/panops/panops-data-registry/data/trait_maps/lusk_et-al_2025/cwms/Shrub_Tree_Grass/1km"
HYDRAULIC_PATH = os.path.join(TRAIT_BASE, "hydraulic")
ANALYSIS_PATH = os.path.join(TRAIT_BASE, "analysis-ready")
OUTPUT_DIR = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux/derived_tables/outputs_afterEGU_results/v10"

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Trait codec for analysis-ready renaming
ANALYSIS_CODEC = {
    '4': 'SSD_mean',
    '6': 'rooting_depth_mean',
    '11': 'SLA_mean',
    '13': 'Leaf_C_mean',
    '14': 'Leaf_N_mass_mean',
    '15': 'Leaf_P_mean',
    '46': 'Leaf_thickness_mean',
    '50': 'Leaf_N_area_mean',
    '55': 'Leaf_dry_mass_mean',
    '78': 'Leaf_delta15N_mean',
    '145': 'Leaf_width_mean',
    '146': 'Leaf_CN_ratio_mean',
    '169': 'Stem_conduit_density_mean',
    '281': 'Stem_conduit_diameter_mean',
    '3112': 'Leaf_area_variant1_mean',
    '3113': 'Leaf_area_variant2_mean',
    '3114': 'Leaf_area_variant3_mean',
    '3117': 'Leaf_area_variant4_mean',
}

print("\n" + "="*80)
print("PLANT TRAITS EXTRACTION FROM TIF FILES")
print("="*80 + "\n")

# Step 1: Get flux tower coordinates
print("Step 1: Loading flux tower coordinates...")
try:
    sites_file = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux/derived_tables/outputs_afterEGU_results/v10/v10_rf_ready.csv"
    df_sites = pd.read_csv(sites_file, usecols=['SITE_ID', 'YEAR'])
    sites_unique = df_sites[['SITE_ID']].drop_duplicates()

    # Load site metadata with coordinates
    meta_file = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux/fluxnet_2017_2025_V02/EFP_outputs_corrected/EFP_metadata_monthlyMeteo_WIDE.csv"
    df_meta = pd.read_csv(meta_file, usecols=['SITE_ID', 'LOCATION_LAT', 'LOCATION_LONG'])
    df_meta = df_meta.drop_duplicates(subset=['SITE_ID'])

    sites_unique = sites_unique.merge(df_meta, on='SITE_ID', how='left')

    print(f"  Loaded {len(sites_unique)} unique sites")
    print(f"  Coordinate range: LAT [{sites_unique['LOCATION_LAT'].min():.2f}, {sites_unique['LOCATION_LAT'].max():.2f}]")
    print(f"                    LON [{sites_unique['LOCATION_LONG'].min():.2f}, {sites_unique['LOCATION_LONG'].max():.2f}]\n")

except Exception as e:
    print(f"  ERROR: {e}\n")
    exit(1)

# Step 2: Extract hydraulic traits
print("Step 2: Extracting hydraulic traits from TIFs...")
hydraulic_traits = ['P12', 'P50', 'P88', 'gsmax', 'rdmax']
trait_data = {'SITE_ID': []}

for trait in hydraulic_traits:
    trait_path = os.path.join(HYDRAULIC_PATH, trait)
    tif_files = glob.glob(os.path.join(trait_path, "*.tif"))

    if not tif_files:
        print(f"  WARNING: No TIF found for {trait}")
        trait_data[f'{trait}_mean'] = []
        continue

    tif_file = tif_files[0]
    print(f"  Processing {trait}...")

    trait_values = []

    try:
        with rasterio.open(tif_file) as src:
            for idx, row in sites_unique.iterrows():
                site_id = row['SITE_ID']
                lat = row['LOCATION_LAT']
                lon = row['LOCATION_LONG']

                if pd.isna(lat) or pd.isna(lon):
                    trait_values.append(np.nan)
                    continue

                # Create 500m buffer (approximately 0.0045 degrees at equator)
                point = Point(lon, lat)
                buffer_dist = 0.0045
                bbox = point.buffer(buffer_dist).bounds

                try:
                    # Extract data within buffer
                    out_image, out_transform = mask(src, [point.buffer(buffer_dist)], crop=True)

                    if out_image.size > 0:
                        # Get mean value (ignore nodata)
                        valid_data = out_image[out_image > 0]
                        if len(valid_data) > 0:
                            trait_values.append(float(np.mean(valid_data)))
                        else:
                            trait_values.append(np.nan)
                    else:
                        trait_values.append(np.nan)
                except:
                    trait_values.append(np.nan)

        trait_data[f'{trait}_mean'] = trait_values
        print(f"    ✓ Extracted {len([v for v in trait_values if not pd.isna(v)])}/{len(trait_values)} sites")

    except Exception as e:
        print(f"    ERROR: {e}")
        trait_data[f'{trait}_mean'] = [np.nan] * len(sites_unique)

# Add SITE_ID
trait_data['SITE_ID'] = sites_unique['SITE_ID'].values

# Step 3: Extract analysis-ready traits
print("\nStep 3: Extracting analysis-ready traits...")

for tif_file in sorted(glob.glob(os.path.join(ANALYSIS_PATH, "X*.tif"))):
    if tif_file.endswith('.aux.xml'):
        continue

    basename = os.path.basename(tif_file)
    code = basename.split('_')[0].replace('X', '')
    trait_name = ANALYSIS_CODEC.get(code, f'unknown_{code}')

    print(f"  Processing {code} ({trait_name})...")
    trait_values = []

    try:
        with rasterio.open(tif_file) as src:
            for idx, row in sites_unique.iterrows():
                lat = row['LOCATION_LAT']
                lon = row['LOCATION_LONG']

                if pd.isna(lat) or pd.isna(lon):
                    trait_values.append(np.nan)
                    continue

                point = Point(lon, lat)
                try:
                    out_image, out_transform = mask(src, [point.buffer(0.0045)], crop=True)
                    if out_image.size > 0:
                        valid_data = out_image[out_image > 0]
                        if len(valid_data) > 0:
                            trait_values.append(float(np.mean(valid_data)))
                        else:
                            trait_values.append(np.nan)
                    else:
                        trait_values.append(np.nan)
                except:
                    trait_values.append(np.nan)

        trait_data[trait_name] = trait_values
        print(f"    ✓ Extracted {len([v for v in trait_values if not pd.isna(v)])}/{len(trait_values)} sites")

    except Exception as e:
        print(f"    ERROR: {e}")
        trait_data[trait_name] = [np.nan] * len(sites_unique)

# Step 4: Save extracted traits
print("\nStep 4: Saving trait data...")
df_traits = pd.DataFrame(trait_data)

out_file = os.path.join(OUTPUT_DIR, 'plant_traits_extracted.csv')
df_traits.to_csv(out_file, index=False)

print(f"  Saved: {out_file}")
print(f"  Rows: {len(df_traits)}")
print(f"  Columns: {len(df_traits.columns)}")
print(f"  Hydraulic traits: {len(hydraulic_traits)}")
print(f"  Analysis-ready traits: {len([c for c in df_traits.columns if c not in ['SITE_ID'] + [f'{t}_mean' for t in hydraulic_traits]])}\n")

# Summary
print("="*80)
print("EXTRACTION COMPLETE")
print("="*80 + "\n")

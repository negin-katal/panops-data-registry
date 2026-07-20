#!/usr/bin/env python3
"""
Step 19: Create B1/B2 benchmarks WITHOUT tree cover filtering (all 184 sites)
"""

import pandas as pd
import numpy as np
import os

print("\n" + "="*80)
print("STEP 19: CREATE V10_ALL_SITES - B1/B2 BENCHMARKS (NO TREE COVER FILTER)")
print("="*80 + "\n")

# Create output directory
output_dir = 'derived_tables/outputs_afterEGU_results/v10_all_sites'
os.makedirs(output_dir, exist_ok=True)
print(f"Output directory: {output_dir}\n")

# Load unfiltered dataset with traits
print("Loading unfiltered RF-ready dataset with traits...")
df_unfiltered = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready_with_traits.csv')

print(f"  Total rows: {len(df_unfiltered)}")
print(f"  Total sites: {df_unfiltered['SITE_ID'].nunique()}")
print(f"  Columns: {len(df_unfiltered.columns)}\n")

# Get tree cover distribution for reference
tree_cover_col = 'tree_cover_mean_pct_500m'
tree_cover_per_site = df_unfiltered.groupby('SITE_ID')[tree_cover_col].mean()

print("Tree cover distribution (all sites):")
print(f"  Min: {tree_cover_per_site.min():.1f}%")
print(f"  Max: {tree_cover_per_site.max():.1f}%")
print(f"  Mean: {tree_cover_per_site.mean():.1f}%")
print(f"  Median: {tree_cover_per_site.median():.1f}%")
print(f"  Sites <30%: {(tree_cover_per_site < 30).sum()}")
print(f"  Sites >=30%: {(tree_cover_per_site >= 30).sum()}\n")

# ============================================================================
# CREATE B1 (LAG1 ONLY)
# ============================================================================
print("Creating B1 benchmark (lag1 only)...")

# Base columns
base_cols = ['SITE_ID', 'YEAR']

# Response variables
response_vars = ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']
for var in response_vars:
    base_cols.append(var)
    base_cols.append(f'{var}_anomaly')

# Meteorological lags (lag1 only)
meteo_cols_b1 = [c for c in df_unfiltered.columns if c.startswith('lag1_') and any(x in c for x in ['TA_', 'VPD_', 'P_', 'SW_IN_'])]

# Disturbance and mortality
dist_cols = [c for c in df_unfiltered.columns if any(x in c for x in
    ['mortality', 'relative_disturbance', 'new_'])]

# Traits (static)
trait_cols = [c for c in df_unfiltered.columns if any(x in c for x in
    ['P12_', 'P50_', 'P88_', 'gsmax_', 'rdmax_', 'SSD', 'SLA', 'Leaf', 'Stem'])]

# Combine all for B1
b1_cols = base_cols + meteo_cols_b1 + dist_cols + trait_cols
b1_cols = [c for c in b1_cols if c in df_unfiltered.columns]

df_b1 = df_unfiltered[b1_cols].copy()

print(f"  Rows: {len(df_b1)}")
print(f"  Columns: {len(df_b1)} (base: {len(base_cols)}, meteo: {len(meteo_cols_b1)}, dist: {len(dist_cols)}, traits: {len(trait_cols)})")

b1_file = f'{output_dir}/v10_all_B1_lag1only.csv'
df_b1.to_csv(b1_file, index=False)
print(f"  Saved: {b1_file}\n")

# ============================================================================
# CREATE B2 (LAG1 + LAG2)
# ============================================================================
print("Creating B2 benchmark (lag1+lag2)...")

# Meteorological lags (lag1 + lag2)
meteo_cols_b2 = [c for c in df_unfiltered.columns if c.startswith('lag') and any(x in c for x in ['TA_', 'VPD_', 'P_', 'SW_IN_'])]

# Disturbance and mortality (now includes lag1+lag2)
# Same as B1 since disturbance also has lag1+lag2 variants

# Combine all for B2
b2_cols = base_cols + meteo_cols_b2 + dist_cols + trait_cols
b2_cols = [c for c in b2_cols if c in df_unfiltered.columns]

df_b2 = df_unfiltered[b2_cols].copy()

print(f"  Rows: {len(df_b2)}")
print(f"  Columns: {len(df_b2)} (base: {len(base_cols)}, meteo: {len(meteo_cols_b2)}, dist: {len(dist_cols)}, traits: {len(trait_cols)})")

b2_file = f'{output_dir}/v10_all_B2_lag1lag2.csv'
df_b2.to_csv(b2_file, index=False)
print(f"  Saved: {b2_file}\n")

# ============================================================================
# CREATE RESPONSE-SPECIFIC DATASETS
# ============================================================================
print("Creating response-variable-specific datasets...\n")

for response_var in response_vars:
    print(f"  {response_var}:")

    # Response-specific memory columns
    response_cols = [
        f'{response_var}_lag1',
        f'{response_var}_anom_lag1',
        f'{response_var}_lag2',
        f'{response_var}_anom_lag2',
    ]
    response_cols = [c for c in response_cols if c in df_unfiltered.columns]

    # B1
    b1_resp_cols = base_cols + meteo_cols_b1 + dist_cols + trait_cols
    b1_resp_cols += [c for c in response_cols if '_lag2' not in c]
    b1_resp_cols = [c for c in b1_resp_cols if c in df_unfiltered.columns]

    df_b1_resp = df_unfiltered[b1_resp_cols].copy()
    b1_resp_file = f'{output_dir}/v10_all_B1_{response_var}.csv'
    df_b1_resp.to_csv(b1_resp_file, index=False)
    print(f"    B1_{response_var}: {len(df_b1_resp)} rows × {len(df_b1_resp.columns)} cols")

    # B2
    b2_resp_cols = base_cols + meteo_cols_b2 + dist_cols + trait_cols
    b2_resp_cols += response_cols
    b2_resp_cols = [c for c in b2_resp_cols if c in df_unfiltered.columns]

    df_b2_resp = df_unfiltered[b2_resp_cols].copy()
    b2_resp_file = f'{output_dir}/v10_all_B2_{response_var}.csv'
    df_b2_resp.to_csv(b2_resp_file, index=False)
    print(f"    B2_{response_var}: {len(df_b2_resp)} rows × {len(df_b2_resp.columns)} cols")

print("\n" + "="*80)
print("✅ STEP 19 COMPLETE - V10_ALL_SITES DATASETS CREATED")
print("="*80)
print(f"\nSummary:")
print(f"  Sites (all, no filtering): 184")
print(f"  Site-years: 1006")
print(f"  B1 benchmark: {len(df_b1)} rows × {len(df_b1.columns)} cols")
print(f"  B2 benchmark: {len(df_b2)} rows × {len(df_b2.columns)} cols")
print(f"  5 response-specific datasets per benchmark")
print(f"  Output directory: {output_dir}\n")

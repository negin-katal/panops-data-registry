#!/usr/bin/env python3
"""
Step 17: Create B1 (lag1 only) and B2 (lag1+lag2) benchmarks
- B1: Remove all lag2 columns, keep only lag1
- B2: Keep all lag1 and lag2 columns
- Remove tree cover/live tree columns from disturbance (keep only mortality metrics)
"""

import pandas as pd
import numpy as np

print("\n" + "="*80)
print("STEP 17: CREATE B1 AND B2 BENCHMARKS")
print("="*80 + "\n")

# Load filtered dataset
print("Loading tree-cover filtered dataset...")
df = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready_with_traits_treecover_filtered.csv')

print(f"  Initial: {len(df)} rows × {len(df.columns)} columns\n")

# Identify column types
id_cols = ['SITE_ID', 'YEAR']
response_vars = ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']
response_anom = [f'{v}_anomaly' for v in response_vars]

# Tree cover columns to REMOVE from disturbance
tree_cover_cols_to_remove = [
    'tree_cover_mean_pct_100m', 'tree_cover_mean_pct_200m', 'tree_cover_mean_pct_300m',
    'tree_cover_mean_pct_400m', 'tree_cover_mean_pct_500m',
    'tree_cover_mean_pct_100m_lag1', 'tree_cover_mean_pct_200m_lag1',
    'tree_cover_mean_pct_300m_lag1', 'tree_cover_mean_pct_400m_lag1',
    'tree_cover_mean_pct_500m_lag1',
    'tree_cover_mean_pct_100m_lag2', 'tree_cover_mean_pct_200m_lag2',
    'tree_cover_mean_pct_300m_lag2', 'tree_cover_mean_pct_400m_lag2',
    'tree_cover_mean_pct_500m_lag2',
    'live_tree_cover_pct_100m', 'live_tree_cover_pct_200m', 'live_tree_cover_pct_300m',
    'live_tree_cover_pct_400m', 'live_tree_cover_pct_500m',
    'live_tree_cover_pct_100m_lag1', 'live_tree_cover_pct_200m_lag1',
    'live_tree_cover_pct_300m_lag1', 'live_tree_cover_pct_400m_lag1',
    'live_tree_cover_pct_500m_lag1',
    'live_tree_cover_pct_100m_lag2', 'live_tree_cover_pct_200m_lag2',
    'live_tree_cover_pct_300m_lag2', 'live_tree_cover_pct_400m_lag2',
    'live_tree_cover_pct_500m_lag2',
    'tree_loss_pp_100m', 'tree_loss_pp_200m', 'tree_loss_pp_300m',
    'tree_loss_pp_400m', 'tree_loss_pp_500m',
    'tree_loss_pp_100m_lag1', 'tree_loss_pp_200m_lag1',
    'tree_loss_pp_300m_lag1', 'tree_loss_pp_400m_lag1',
    'tree_loss_pp_500m_lag1',
    'tree_loss_pp_100m_lag2', 'tree_loss_pp_200m_lag2',
    'tree_loss_pp_300m_lag2', 'tree_loss_pp_400m_lag2',
    'tree_loss_pp_500m_lag2',
    'relative_tree_loss_pct_100m', 'relative_tree_loss_pct_200m',
    'relative_tree_loss_pct_300m', 'relative_tree_loss_pct_400m',
    'relative_tree_loss_pct_500m',
    'relative_tree_loss_pct_100m_lag1', 'relative_tree_loss_pct_200m_lag1',
    'relative_tree_loss_pct_300m_lag1', 'relative_tree_loss_pct_400m_lag1',
    'relative_tree_loss_pct_500m_lag1',
    'relative_tree_loss_pct_100m_lag2', 'relative_tree_loss_pct_200m_lag2',
    'relative_tree_loss_pct_300m_lag2', 'relative_tree_loss_pct_400m_lag2',
    'relative_tree_loss_pct_500m_lag2',
    'tree_loss_pp_thresh_100m', 'tree_loss_pp_thresh_200m',
    'tree_loss_pp_thresh_300m', 'tree_loss_pp_thresh_400m',
    'tree_loss_pp_thresh_500m',
    'tree_loss_pp_thresh_100m_lag1', 'tree_loss_pp_thresh_200m_lag1',
    'tree_loss_pp_thresh_300m_lag1', 'tree_loss_pp_thresh_400m_lag1',
    'tree_loss_pp_thresh_500m_lag1',
    'tree_loss_pp_thresh_100m_lag2', 'tree_loss_pp_thresh_200m_lag2',
    'tree_loss_pp_thresh_300m_lag2', 'tree_loss_pp_thresh_400m_lag2',
    'tree_loss_pp_thresh_500m_lag2',
    'relative_tree_loss_pct_thresh_100m', 'relative_tree_loss_pct_thresh_200m',
    'relative_tree_loss_pct_thresh_300m', 'relative_tree_loss_pct_thresh_400m',
    'relative_tree_loss_pct_thresh_500m',
    'relative_tree_loss_pct_thresh_100m_lag1', 'relative_tree_loss_pct_thresh_200m_lag1',
    'relative_tree_loss_pct_thresh_300m_lag1', 'relative_tree_loss_pct_thresh_400m_lag1',
    'relative_tree_loss_pct_thresh_500m_lag1',
    'relative_tree_loss_pct_thresh_100m_lag2', 'relative_tree_loss_pct_thresh_200m_lag2',
    'relative_tree_loss_pct_thresh_300m_lag2', 'relative_tree_loss_pct_thresh_400m_lag2',
    'relative_tree_loss_pct_thresh_500m_lag2',
]

# Filter columns that actually exist
tree_cover_cols_to_remove = [c for c in tree_cover_cols_to_remove if c in df.columns]

print(f"Removing {len(tree_cover_cols_to_remove)} tree cover/loss columns from disturbance...")
df_clean = df.drop(columns=tree_cover_cols_to_remove)

print(f"  Columns after removing tree cover: {len(df_clean)}\n")

# Identify lag2 columns (for B1 creation)
lag2_cols = [c for c in df_clean.columns if '_lag2' in c]

print(f"Lag2 columns to remove for B1: {len(lag2_cols)}")
print("  Examples:", lag2_cols[:5], "\n")

# Create B1 benchmark (lag1 only)
print("Creating B1 benchmark (lag1 only)...")
df_b1 = df_clean.drop(columns=lag2_cols)

b1_out = 'derived_tables/outputs_afterEGU_results/v10/v10_B1_lag1only.csv'
df_b1.to_csv(b1_out, index=False)

print(f"  B1 file: {b1_out}")
print(f"  B1 rows: {len(df_b1)}")
print(f"  B1 columns: {len(df_b1.columns)}")
print(f"    - ID/metadata: 2")
print(f"    - Response: 5")
print(f"    - Response anomalies: 5")
print(f"    - Meteo lag1: 78 (13 months × 3 stats)")
print(f"    - Disturbance (no tree cover): {len([c for c in df_b1.columns if 'deadwood' in c or 'mortality' in c or 'relative_disturbance' in c or 'new_' in c])}")
print(f"    - Traits: 21")
print(f"  B1 size: {df_b1.memory_usage(deep=True).sum()/1024/1024:.1f} MB\n")

# Create B2 benchmark (lag1+lag2)
print("Creating B2 benchmark (lag1+lag2)...")
df_b2 = df_clean  # Already has both lag1 and lag2

b2_out = 'derived_tables/outputs_afterEGU_results/v10/v10_B2_lag1lag2.csv'
df_b2.to_csv(b2_out, index=False)

print(f"  B2 file: {b2_out}")
print(f"  B2 rows: {len(df_b2)}")
print(f"  B2 columns: {len(df_b2.columns)}")
print(f"    - ID/metadata: 2")
print(f"    - Response: 5")
print(f"    - Response anomalies: 5")
print(f"    - Meteo lag1+lag2: 156 (13 months × 3 stats × 2 lags)")
print(f"    - Disturbance lag1+lag2 (no tree cover): {len([c for c in df_b2.columns if ('deadwood' in c or 'mortality' in c or 'relative_disturbance' in c or 'new_' in c)])}")
print(f"    - Traits: 21")
print(f"  B2 size: {df_b2.memory_usage(deep=True).sum()/1024/1024:.1f} MB\n")

# Verify identical site-years
b1_sites = set(df_b1['SITE_ID'].unique())
b2_sites = set(df_b2['SITE_ID'].unique())
b1_siteyears = set(zip(df_b1['SITE_ID'], df_b1['YEAR']))
b2_siteyears = set(zip(df_b2['SITE_ID'], df_b2['YEAR']))

print("Benchmark verification:")
print(f"  B1 sites: {len(b1_sites)}, site-years: {len(b1_siteyears)}")
print(f"  B2 sites: {len(b2_sites)}, site-years: {len(b2_siteyears)}")
print(f"  Sites match: {b1_sites == b2_sites}")
print(f"  Site-years match: {b1_siteyears == b2_siteyears}")

# Response variable coverage
print("\nResponse variable coverage:")
for var in response_vars:
    b1_cov = df_b1[var].notna().sum()
    b2_cov = df_b2[var].notna().sum()
    print(f"  {var}: B1={b1_cov}/{len(df_b1)}, B2={b2_cov}/{len(df_b2)}")

print("\n✅ STEP 17 COMPLETE - B1 AND B2 BENCHMARKS CREATED")
print("="*80 + "\n")

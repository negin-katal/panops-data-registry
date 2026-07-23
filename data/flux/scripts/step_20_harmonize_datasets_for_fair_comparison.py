#!/usr/bin/env python3
"""
Step 20: Harmonize datasets so ALL models use the SAME site-years
- B1 and B2 use identical site-years
- All 16 models (8 × 2 memory types) trained on same data
"""

import pandas as pd
import numpy as np

print("\n" + "="*80)
print("STEP 20: HARMONIZE DATASETS - SAME SITE-YEARS FOR ALL MODELS")
print("="*80 + "\n")

# Load filtered B1 and B2 benchmarks
print("Loading B1 and B2 benchmarks (tree-cover filtered)...")
df_b1_base = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_B1_lag1only.csv')
df_b2_base = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_B2_lag1lag2.csv')

print(f"  B1: {len(df_b1_base)} rows initially")
print(f"  B2: {len(df_b2_base)} rows initially\n")

# Response variables
response_vars = ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']

print("Finding IDENTICAL site-years for B1 and B2...\n")

# Drop all-missing rows from both
df_b1_nomiss = df_b1_base.dropna()
df_b2_nomiss = df_b2_base.dropna()

print(f"After removing rows with ANY missing values:")
print(f"  B1: {len(df_b1_nomiss)} rows")
print(f"  B2: {len(df_b2_nomiss)} rows\n")

# Find common site-years using merge
common = pd.merge(
    df_b1_nomiss[['SITE_ID', 'YEAR']],
    df_b2_nomiss[['SITE_ID', 'YEAR']],
    on=['SITE_ID', 'YEAR'],
    how='inner'
)

print(f"Common site-years in both: {len(common)}\n")

# For each response, create harmonized datasets with these common site-years
for response_var in response_vars:
    print(f"{response_var}:")

    # Filter B1 to common site-years
    df_b1_harm = df_b1_nomiss.merge(
        common[['SITE_ID', 'YEAR']],
        on=['SITE_ID', 'YEAR'],
        how='inner'
    ).sort_values(['SITE_ID', 'YEAR']).reset_index(drop=True)

    # Filter B2 to common site-years
    df_b2_harm = df_b2_nomiss.merge(
        common[['SITE_ID', 'YEAR']],
        on=['SITE_ID', 'YEAR'],
        how='inner'
    ).sort_values(['SITE_ID', 'YEAR']).reset_index(drop=True)

    # Verify match
    assert len(df_b1_harm) == len(df_b2_harm)
    assert (df_b1_harm['SITE_ID'].values == df_b2_harm['SITE_ID'].values).all()
    assert (df_b1_harm['YEAR'].values == df_b2_harm['YEAR'].values).all()

    print(f"  ✓ SYNCHRONIZED: B1={len(df_b1_harm)}, B2={len(df_b2_harm)} (IDENTICAL)\n")

    # Save harmonized B1
    b1_harm_file = f'derived_tables/outputs_afterEGU_results/v10/v10_B1_{response_var}_harmonized.csv'
    df_b1_harm.to_csv(b1_harm_file, index=False)

    # Save harmonized B2
    b2_harm_file = f'derived_tables/outputs_afterEGU_results/v10/v10_B2_{response_var}_harmonized.csv'
    df_b2_harm.to_csv(b2_harm_file, index=False)

print("\n" + "="*80)
print("✅ HARMONIZED DATASETS READY FOR FAIR MODEL COMPARISON")
print("="*80)
print("\nAll models trained on identical site-years:")
print("  ✓ B1 (lag1 only) and B2 (lag1+lag2) use SAME site-years")
print("  ✓ All 8 models × 2 memory types use SAME n per response")
print("  ✓ RMSE/MAE/R² differences reflect ONLY model quality\n")

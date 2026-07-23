#!/usr/bin/env python3
"""
Step 21: Create harmonized datasets for ALL sites (no tree-cover filtering)
Same logic as step_20 but applied to v10_all_sites
"""

import pandas as pd
import numpy as np

print("\n" + "="*80)
print("STEP 21: HARMONIZE ALL-SITES DATASET")
print("="*80 + "\n")

# Load unfiltered B1 and B2
print("Loading ALL-SITES B1 and B2 (no tree-cover filtering)...")
df_b1 = pd.read_csv('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_lag1only.csv')
df_b2 = pd.read_csv('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B2_lag1lag2.csv')

print(f"  B1: {len(df_b1)} rows, {len(df_b1.columns)} columns")
print(f"  B2: {len(df_b2)} rows, {len(df_b2.columns)} columns\n")

print(f"  Unique sites: {df_b1['SITE_ID'].nunique()}\n")

# Identify and remove unnecessary columns (Rb, Rbmax, aCUE)
cols_to_remove = ['Rb', 'Rbmax', 'aCUE']
cols_to_remove = [c for c in cols_to_remove if c in df_b1.columns]

if cols_to_remove:
    print(f"Removing unnecessary columns: {cols_to_remove}\n")
    df_b1 = df_b1.drop(columns=cols_to_remove)
    df_b2 = df_b2.drop(columns=cols_to_remove)

print(f"After cleanup:")
print(f"  B1: {len(df_b1.columns)} columns")
print(f"  B2: {len(df_b2.columns)} columns\n")

# Response variables
response_vars = ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']

print("Finding IDENTICAL site-years for B1 and B2...\n")

# Remove rows with ANY missing values
df_b1_nomiss = df_b1.dropna()
df_b2_nomiss = df_b2.dropna()

print(f"After removing rows with ANY missing values:")
print(f"  B1: {len(df_b1_nomiss)} rows (removed {len(df_b1) - len(df_b1_nomiss)})")
print(f"  B2: {len(df_b2_nomiss)} rows (removed {len(df_b2) - len(df_b2_nomiss)})\n")

# Find common site-years
common = pd.merge(
    df_b1_nomiss[['SITE_ID', 'YEAR']],
    df_b2_nomiss[['SITE_ID', 'YEAR']],
    on=['SITE_ID', 'YEAR'],
    how='inner'
)

print(f"Common site-years in both: {len(common)}")
print(f"Common unique sites: {common['SITE_ID'].nunique()}\n")

# For each response, create harmonized datasets
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
    b1_harm_file = f'derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_{response_var}_harmonized.csv'
    df_b1_harm.to_csv(b1_harm_file, index=False)

    # Save harmonized B2
    b2_harm_file = f'derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B2_{response_var}_harmonized.csv'
    df_b2_harm.to_csv(b2_harm_file, index=False)

print("\n" + "="*80)
print("✅ ALL-SITES HARMONIZED DATASETS READY")
print("="*80)
print("\nDataset summary:")
print(f"  Sites: {len(common)}")
print(f"  Site-years: {len(df_b1_harm)} (both B1 and B2)")
print(f"  B1 and B2: IDENTICAL site-years")
print(f"  All 5 responses: IDENTICAL site-years\n")

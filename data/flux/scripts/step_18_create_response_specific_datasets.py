#!/usr/bin/env python3
"""
Step 18: Create response-variable-specific datasets
For memory models (M05-M08), each response variable gets only its own EFP lags/anomalies
E.g., for predicting GPPsat, only include GPPsat_lag1/lag2 and GPPsat_anom_lag1/lag2
"""

import pandas as pd
import numpy as np

print("\n" + "="*80)
print("STEP 18: CREATE RESPONSE-VARIABLE-SPECIFIC DATASETS")
print("="*80 + "\n")

# Load both benchmarks
print("Loading B1 and B2 benchmarks...")
df_b1 = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_B1_lag1only.csv')
df_b2 = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_B2_lag1lag2.csv')

print(f"  B1: {len(df_b1)} rows × {len(df_b1.columns)} columns")
print(f"  B2: {len(df_b2)} rows × {len(df_b2.columns)} columns\n")

# Response variables
response_vars = ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']

# Columns that should be in ALL datasets
common_cols = ['SITE_ID', 'YEAR']

# Add response variables
for var in response_vars:
    common_cols.append(var)
    common_cols.append(f'{var}_anomaly')

# Add meteo lags - B1 and B2 have different numbers!
meteo_cols_b1 = [c for c in df_b1.columns if c.startswith('lag1_') and any(x in c for x in ['TA_', 'VPD_', 'P_', 'SW_IN_'])]
meteo_cols_b2 = [c for c in df_b2.columns if c.startswith('lag') and any(x in c for x in ['TA_', 'VPD_', 'P_', 'SW_IN_'])]

# Add disturbance and traits (get from each benchmark separately)
dist_cols_b1 = [c for c in df_b1.columns if any(x in c for x in
    ['mortality', 'relative_disturbance', 'new_'])]
dist_cols_b2 = [c for c in df_b2.columns if any(x in c for x in
    ['mortality', 'relative_disturbance', 'new_'])]

trait_cols = [c for c in df_b1.columns if any(x in c for x in
    ['P12_', 'P50_', 'P88_', 'gsmax_', 'rdmax_', 'SSD', 'SLA', 'Leaf', 'Stem'])]

print(f"B1 columns:")
print(f"  ID/metadata: {len(common_cols)}")
print(f"  Meteo lags (lag1 only): {len(meteo_cols_b1)}")
print(f"  Disturbance: {len(dist_cols_b1)}")
print(f"  Traits: {len(trait_cols)}\n")

print(f"B2 columns:")
print(f"  ID/metadata: {len(common_cols)}")
print(f"  Meteo lags (lag1+lag2): {len(meteo_cols_b2)}")
print(f"  Disturbance: {len(dist_cols_b2)}")
print(f"  Traits: {len(trait_cols)}\n")

# Create response-specific datasets
for response_var in response_vars:
    print(f"Creating datasets for {response_var}...")

    # Columns specific to this response (only its own EFP memory)
    response_specific_cols = [
        f'{response_var}_lag1',
        f'{response_var}_anom_lag1',
        f'{response_var}_lag2',
        f'{response_var}_anom_lag2',
    ]
    # Keep only columns that exist
    response_specific_cols = [c for c in response_specific_cols if c in df_b1.columns or c in df_b2.columns]

    # B1: lag1 only
    b1_cols = common_cols + meteo_cols_b1 + dist_cols_b1 + trait_cols
    # Add only lag1 memory columns
    b1_cols += [c for c in response_specific_cols if '_lag2' not in c]
    b1_cols = [c for c in b1_cols if c in df_b1.columns]

    df_b1_resp = df_b1[b1_cols].copy()

    b1_file = f'derived_tables/outputs_afterEGU_results/v10/v10_B1_{response_var}.csv'
    df_b1_resp.to_csv(b1_file, index=False)

    print(f"  B1_{response_var}: {len(df_b1_resp)} rows × {len(df_b1_resp.columns)} columns")
    print(f"    File: {b1_file}")

    # B2: lag1 + lag2
    b2_cols = common_cols + meteo_cols_b2 + dist_cols_b2 + trait_cols
    # Add both lag1 and lag2 memory columns
    b2_cols += response_specific_cols
    b2_cols = [c for c in b2_cols if c in df_b2.columns]

    df_b2_resp = df_b2[b2_cols].copy()

    b2_file = f'derived_tables/outputs_afterEGU_results/v10/v10_B2_{response_var}.csv'
    df_b2_resp.to_csv(b2_file, index=False)

    print(f"  B2_{response_var}: {len(df_b2_resp)} rows × {len(df_b2_resp.columns)} columns")
    print(f"    File: {b2_file}")

    # Verify matching EFP memory
    efp_lags_b1 = [c for c in df_b1_resp.columns if '_lag' in c and response_var in c]
    efp_lags_b2 = [c for c in df_b2_resp.columns if '_lag' in c and response_var in c]

    print(f"  EFP memory columns:")
    print(f"    B1: {efp_lags_b1}")
    print(f"    B2: {efp_lags_b2}")
    print()

print("="*80)
print("SUMMARY - DATASET STRUCTURE FOR EACH RESPONSE VARIABLE")
print("="*80 + "\n")

# Create summary table
summary_data = []
for response_var in response_vars:
    b1_file = f'derived_tables/outputs_afterEGU_results/v10/v10_B1_{response_var}.csv'
    b2_file = f'derived_tables/outputs_afterEGU_results/v10/v10_B2_{response_var}.csv'

    df_b1_resp = pd.read_csv(b1_file)
    df_b2_resp = pd.read_csv(b2_file)

    summary_data.append({
        'Response': response_var,
        'B1_rows': len(df_b1_resp),
        'B1_cols': len(df_b1_resp.columns),
        'B2_rows': len(df_b2_resp),
        'B2_cols': len(df_b2_resp.columns),
    })

df_summary = pd.DataFrame(summary_data)
print(df_summary.to_string(index=False))

print("\n✅ STEP 18 COMPLETE - RESPONSE-SPECIFIC DATASETS CREATED")
print("="*80 + "\n")

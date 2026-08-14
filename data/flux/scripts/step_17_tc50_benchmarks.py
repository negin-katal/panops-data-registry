#!/usr/bin/env python3
"""
Step 17 FIXED: Create B1 (lag1 only) and B2 (lag1+lag2) benchmarks
- B1: Remove ALL lag2 columns (meteo, mortality, disturbance, memory)
- B2: Keep ALL lag1 and lag2 columns
"""

import pandas as pd
import numpy as np

print("\n" + "="*80)
print("STEP 17 FIXED: CREATE B1 AND B2 BENCHMARKS")
print("="*80 + "\n")

# Load tree-cover filtered dataset
print("Loading tree-cover filtered dataset...")
df = pd.read_csv('derived_tables/outputs_afterEGU_results/v10_tc50/v10_tc50_rf_ready_with_traits.csv')

print(f"  Initial: {len(df)} rows × {len(df.columns)} columns\n")

# Identify all lag2 columns (to remove for B1)
lag2_cols = [c for c in df.columns if '_lag2' in c]

print(f"Lag2 columns to remove for B1: {len(lag2_cols)}")
print(f"  Meteo lag2: {len([c for c in lag2_cols if c.startswith('lag2_')])}")
print(f"  Mortality lag2: {len([c for c in lag2_cols if 'mortality' in c])}")
print(f"  Disturbance lag2: {len([c for c in lag2_cols if 'relative_disturbance' in c])}")
print(f"  Memory lag2: {len([c for c in lag2_cols if any(resp in c for resp in ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE'])])}\n")

# Create B1 benchmark (remove all lag2)
print("Creating B1 benchmark (lag1 only)...")
df_b1 = df.drop(columns=lag2_cols)

b1_out = 'derived_tables/outputs_afterEGU_results/v10_tc50/v10_tc50_B1_lag1only.csv'
df_b1.to_csv(b1_out, index=False)

print(f"  B1 file: {b1_out}")
print(f"  B1 rows: {len(df_b1)}")
print(f"  B1 columns: {len(df_b1.columns)}")
print(f"    - Meteo lag1: 143")
print(f"    - Mortality (current + lag1): 40 + 40 = 80")
print(f"    - Disturbance (current + lag1): 5 + 5 = 10")
print(f"    - Traits: 21")
print(f"    - Memory: varies by response")
print(f"  B1 size: {df_b1.memory_usage(deep=True).sum()/1024/1024:.1f} MB\n")

# Create B2 benchmark (keep all lags)
print("Creating B2 benchmark (lag1+lag2)...")
df_b2 = df.copy()  # Keep all columns

b2_out = 'derived_tables/outputs_afterEGU_results/v10_tc50/v10_tc50_B2_lag1lag2.csv'
df_b2.to_csv(b2_out, index=False)

print(f"  B2 file: {b2_out}")
print(f"  B2 rows: {len(df_b2)}")
print(f"  B2 columns: {len(df_b2.columns)}")
print(f"    - Meteo lag1+lag2: 143 + 143 = 286")
print(f"    - Mortality (current + lag1 + lag2): 40 + 40 + 30 = 110")
print(f"    - Disturbance (current + lag1 + lag2): 5 + 5 + 5 = 15")
print(f"    - Traits: 21")
print(f"    - Memory: varies by response")
print(f"  B2 size: {df_b2.memory_usage(deep=True).sum()/1024/1024:.1f} MB\n")

# Verify identical site-years
b1_siteyears = set(zip(df_b1['SITE_ID'], df_b1['YEAR']))
b2_siteyears = set(zip(df_b2['SITE_ID'], df_b2['YEAR']))

print("Benchmark verification:")
print(f"  B1 rows: {len(df_b1)}, sites: {df_b1['SITE_ID'].nunique()}, site-years: {len(b1_siteyears)}")
print(f"  B2 rows: {len(df_b2)}, sites: {df_b2['SITE_ID'].nunique()}, site-years: {len(b2_siteyears)}")
print(f"  ✓ Identical site-years: {b1_siteyears == b2_siteyears}\n")

# Response variable coverage
print("Response variable coverage:")
for var in ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']:
    b1_cov = df_b1[var].notna().sum()
    b2_cov = df_b2[var].notna().sum()
    print(f"  {var}: B1={b1_cov}/{len(df_b1)}, B2={b2_cov}/{len(df_b2)}")

print("\n✅ STEP 17 FIXED COMPLETE\n")
print("="*80)
print("SUMMARY - PREDICTORS BY BENCHMARK")
print("="*80 + "\n")

print("B1 (Lag1 only):")
print("  Meteo: 143 (13 months × 11 stats)")
print("  Mortality: 80 (5 buffers × 8 metrics × 2 time steps)")
print("  Disturbance: 10 (5 buffers × 2 time steps)")
print("  Traits: 21 (static)")
print("  Memory: varies by response (2 columns each)\n")

print("B2 (Lag1 + Lag2):")
print("  Meteo: 286 (143 lag1 + 143 lag2)")
print("  Mortality: 110 (40 current + 40 lag1 + 30 lag2)")
print("  Disturbance: 15 (5 current + 5 lag1 + 5 lag2)")
print("  Traits: 21 (static)")
print("  Memory: varies by response (4 columns each)\n")

print("="*80 + "\n")


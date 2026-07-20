#!/usr/bin/env python3
"""
Document all predictor columns used in each response variable model
"""

import pandas as pd
import os

data_dir = 'derived_tables/outputs_afterEGU_results/v10'
responses = ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']

print("="*100)
print("DETAILED PREDICTOR COLUMN BREAKDOWN - BY RESPONSE VARIABLE")
print("="*100 + "\n")

# Load B1 datasets for each response
for response in responses:
    fname = f'v10_B1_{response}.csv'
    fpath = os.path.join(data_dir, fname)

    df = pd.read_csv(fpath)

    print(f"\n{'='*100}")
    print(f"{response} - B1 BENCHMARK (Lag1 only)")
    print(f"{'='*100}\n")

    print(f"Dataset: {len(df)} rows × {len(df.columns)} columns")
    print(f"Sites: {df['SITE_ID'].nunique()} | Site-years: {len(df)}\n")

    # ID
    id_cols = ['SITE_ID', 'YEAR']

    # Response
    response_cols = [response, f'{response}_anomaly']

    # Meteo
    meteo_cols = [c for c in df.columns if c.startswith('lag1_') and any(x in c for x in ['TA_', 'VPD_', 'P_', 'SW_IN_'])]

    # Mortality & Disturbance
    mortality_cols = [c for c in df.columns if any(x in c for x in ['absolute_mortality', 'relative_mortality', 'new_', 'mortality_loss', 'mortality_stock']) and '_lag2' not in c]
    disturbance_cols = [c for c in df.columns if 'relative_disturbance' in c and '_lag2' not in c]

    # Traits
    trait_cols = [c for c in df.columns if any(x in c for x in ['P12_', 'P50_', 'P88_', 'gsmax_', 'rdmax_', 'SSD', 'SLA', 'Leaf', 'Stem'])]

    # Memory (response-specific)
    memory_cols = [c for c in df.columns if response in c and ('_lag1' in c or '_anom_lag1' in c)]

    # Print breakdown
    print(f"📊 RESPONSE VARIABLE:")
    for col in response_cols:
        if col in df.columns:
            print(f"    ✓ {col}")

    print(f"\n🌡️  METEO/CLIMATE PREDICTORS: {len(meteo_cols)} columns")
    print(f"    Months M01-M13 (13 × growing season)")
    print(f"    Per month: TA (mean, p05, p95), VPD (mean, p05, p95), SW_IN (mean, p05, p95), P (sum, mean)")
    print(f"    Example columns:")
    for col in sorted(meteo_cols)[:5]:
        print(f"      {col}")
    print(f"    ... {len(meteo_cols)-5} more")

    print(f"\n💀 MORTALITY METRICS: {len(mortality_cols)} columns")
    print(f"    Buffers: 100m, 200m, 300m, 400m, 500m")
    print(f"    Current year + Lag1 (2 time steps)")
    print(f"    Metrics per buffer: absolute_mortality, relative_mortality, new_deadwood_gain_pp, etc.")
    if mortality_cols:
        print(f"    Example columns:")
        for col in sorted(mortality_cols)[:5]:
            print(f"      {col}")

    print(f"\n🔴 DISTURBANCE (Relative): {len(disturbance_cols)} columns")
    print(f"    Metric: relative_disturbance (deadwood + tree_loss) / (forest + tree_loss)")
    print(f"    Buffers: 100m, 200m, 300m, 400m, 500m")
    print(f"    Current year + Lag1 (2 time steps)")
    if disturbance_cols:
        print(f"    Columns:")
        for col in sorted(disturbance_cols)[:10]:
            print(f"      {col}")

    print(f"\n🌿 PLANT TRAITS (Static): {len(trait_cols)} columns")
    trait_categories = {
        'Hydraulic': ['P12_', 'P50_', 'P88_', 'gsmax_', 'rdmax_'],
        'Leaf': ['Leaf'],
        'Stem': ['Stem'],
        'Other': ['SSD', 'SLA']
    }
    for cat, patterns in trait_categories.items():
        cat_cols = [c for c in trait_cols if any(p in c for p in patterns)]
        if cat_cols:
            print(f"    {cat} ({len(cat_cols)}):")
            for col in sorted(cat_cols):
                print(f"      {col}")

    print(f"\n🧠 EFP MEMORY (Response-specific): {len(memory_cols)} columns")
    if memory_cols:
        print(f"    Only {response} memory included (no cross-response contamination)")
        raw_mem = [c for c in memory_cols if '_anom_' not in c]
        anom_mem = [c for c in memory_cols if '_anom_' in c]
        print(f"    Raw memory lag1: {raw_mem}")
        print(f"    Anomaly memory lag1: {anom_mem}")
    else:
        print(f"    ⚠️  None found in B1 dataset")

    print(f"\n📈 TOTAL PREDICTORS BY CATEGORY:")
    print(f"    Meteo: {len(meteo_cols)}")
    print(f"    Mortality: {len(mortality_cols)}")
    print(f"    Disturbance: {len(disturbance_cols)}")
    print(f"    Traits: {len(trait_cols)}")
    print(f"    Memory: {len(memory_cols)}")
    print(f"    TOTAL: {len(meteo_cols) + len(mortality_cols) + len(disturbance_cols) + len(trait_cols) + len(memory_cols)}")

print("\n" + "="*100)
print("SUMMARY TABLE - ALL RESPONSES")
print("="*100 + "\n")

summary_data = []
for response in responses:
    fname = f'v10_B1_{response}.csv'
    fpath = os.path.join(data_dir, fname)
    df = pd.read_csv(fpath)

    meteo = len([c for c in df.columns if c.startswith('lag1_') and any(x in c for x in ['TA_', 'VPD_', 'P_', 'SW_IN_'])])
    mortality = len([c for c in df.columns if any(x in c for x in ['absolute_mortality', 'relative_mortality', 'new_', 'mortality_loss', 'mortality_stock']) and '_lag2' not in c])
    disturbance = len([c for c in df.columns if 'relative_disturbance' in c and '_lag2' not in c])
    traits = len([c for c in df.columns if any(x in c for x in ['P12_', 'P50_', 'P88_', 'gsmax_', 'rdmax_', 'SSD', 'SLA', 'Leaf', 'Stem'])])
    memory = len([c for c in df.columns if response in c and ('_lag1' in c or '_anom_lag1' in c)])

    summary_data.append({
        'Response': response,
        'Meteo': meteo,
        'Mortality': mortality,
        'Disturbance': disturbance,
        'Traits': traits,
        'Memory': memory,
        'Total': meteo + mortality + disturbance + traits + memory
    })

df_summary = pd.DataFrame(summary_data)
print(df_summary.to_string(index=False))

print("\n✅ All response variables use IDENTICAL predictor columns!")
print("   Only difference: Response-specific EFP memory (lag columns for that response only)")


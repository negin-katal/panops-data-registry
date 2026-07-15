#!/usr/bin/env python3
"""
Merge SHAP files across all 5 EFPs for v3 (anomaly + rawmem)
"""
import pandas as pd
import os
from pathlib import Path

BASE = "derived_tables/outputs_afterEGU_results"
EFPS = ["GPPsat", "NEPmax", "ETmax", "uWUE", "WUE"]

print("=" * 70)
print("MERGE SHAP v3 — All 5 EFPs")
print("=" * 70)
print()

for memory_type in ["anomaly", "rawmem"]:
    print(f"Processing {memory_type.upper()}...")
    print("-" * 70)

    out_dir = f"{BASE}/RF_outputs_{memory_type}_24mbench_v3"
    out_file = f"{out_dir}/RF_site_shap_M04_M08.csv"

    all_dfs = []

    for efp in EFPS:
        # Each EFP was run separately, creating individual SHAP files
        # Find the SHAP file (might be named with EFP or just M04_M08)
        efp_dir = f"{BASE}/RF_outputs_{memory_type}_24mbench_v3"
        efp_shap = f"{efp_dir}/RF_site_shap_M04_M08.csv"

        # Check if file exists and has data for this EFP
        if os.path.exists(efp_shap):
            df = pd.read_csv(efp_shap)
            if len(df) > 0 and 'response' in df.columns:
                n_rows = len(df)
                print(f"  {efp:10s}: {n_rows:7d} rows")
                all_dfs.append(df)
            else:
                print(f"  {efp:10s}: empty or no response column")
        else:
            print(f"  {efp:10s}: file not found")

    if all_dfs:
        print()
        print(f"  Merging {len(all_dfs)} EFP files...")
        merged = pd.concat(all_dfs, ignore_index=True)
        print(f"  Total merged rows: {len(merged)}")
        print(f"  EFPs in merged: {sorted(merged['response'].unique())}")

        # Save merged file
        merged.to_csv(out_file, index=False)
        print(f"  ✓ Saved: {out_file}")
        print()
    else:
        print(f"  ✗ No valid SHAP files found for {memory_type}")
        print()

print("=" * 70)
print("MERGE COMPLETE")
print("=" * 70)

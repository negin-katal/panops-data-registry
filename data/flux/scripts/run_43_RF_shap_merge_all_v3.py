#!/usr/bin/env python3
"""
Merge all v3 SHAP outputs from individual EFP runs into unified files.
Rerun SHAP computation for anomaly and rawmem, merging all 5 EFPs.
"""
import subprocess
import pandas as pd
import os
import sys

BASE = "derived_tables/outputs_afterEGU_results"
RSCRIPT = "/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript"
EFPS = ["GPPsat", "NEPmax", "ETmax", "uWUE", "WUE"]

print("=" * 70)
print("RE-RUN SHAP v3 WITH PROPER MERGING")
print("=" * 70)
print()

for memory_type in ["anomaly", "rawmem"]:
    print(f"Processing {memory_type.upper()}...")
    print("-" * 70)

    out_dir = f"{BASE}/RF_outputs_{memory_type}_24mbench_v3"
    out_file = f"{out_dir}/RF_site_shap_M04_M08.csv"
    temp_file = f"{out_dir}/RF_site_shap_M04_M08_temp.csv"

    # Remove old file
    if os.path.exists(out_file):
        os.remove(out_file)
        print(f"  Removed old {out_file}")

    all_dfs = []

    for efp in EFPS:
        script = f"run_4{'1' if memory_type == 'anomaly' else '2'}_RF_shap_{memory_type}_v3_{efp}.R"

        print(f"  Running SHAP for {efp}...")
        result = subprocess.run(
            [RSCRIPT, script],
            cwd="/mnt/gsdata/projects/panops/panops-data-registry/data/flux",
            capture_output=True,
            text=True,
            timeout=3600
        )

        if result.returncode == 0:
            print(f"    ✓ {efp} SHAP computed")
            # Read the file
            if os.path.exists(out_file):
                df = pd.read_csv(out_file)
                print(f"    Rows: {len(df)}")
                all_dfs.append(df)
        else:
            print(f"    ✗ {efp} SHAP failed")
            print(result.stderr[:200])

    if all_dfs:
        print()
        print(f"  Merging {len(all_dfs)} EFPs...")
        merged = pd.concat(all_dfs, ignore_index=True)
        merged.to_csv(out_file, index=False)
        print(f"  ✓ Merged file: {len(merged)} rows")
        print(f"  ✓ EFPs: {sorted(merged['response'].unique())}")

    print()

print("=" * 70)
print("DONE")
print("=" * 70)

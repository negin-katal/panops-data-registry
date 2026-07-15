#!/usr/bin/env python3
"""
Prepare harmonized RF dataset (v3):
- Remove CN-Sb1, CN-Sb2 so all EFPs have identical sites/years
- Add relative_disturbance metric = (deadwood + loss×100) / (forest + loss×100) × 100
  at 500m buffer for all lags
- Report what was removed
"""
import pandas as pd
import numpy as np
import os

BASE = "derived_tables/outputs_afterEGU_results"
MODEL_CSV = f"{BASE}/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
OUT_FILE = f"{BASE}/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv"

# ── Load ───────────────────────────────────────────────────────────────
df = pd.read_csv(MODEL_CSV)

print("=" * 70)
print("PREPARE RF v3 HARMONIZED DATASET")
print("=" * 70)
print()
print(f"Input file: {MODEL_CSV}")
print(f"Initial dataset: {len(df)} rows, {df['SITE_ID'].nunique()} sites")
print()

# ── Remove CN-Sb1 and CN-Sb2 ───────────────────────────────────────────
print("STEP 1: Remove flagged sites (CN-Sb1, CN-Sb2)")
print("-" * 70)

remove_sites = {"CN-Sb1", "CN-Sb2"}
remove_rows = df[df["SITE_ID"].isin(remove_sites)]
print(f"Rows to remove: {len(remove_rows)}")
for site in remove_sites:
    site_rows = len(df[df["SITE_ID"] == site])
    print(f"  {site}: {site_rows} rows")

df = df[~df["SITE_ID"].isin(remove_sites)].copy()
print(f"After removal: {len(df)} rows, {df['SITE_ID'].nunique()} sites")
print()

# ── Add relative disturbance metrics ────────────────────────────────────
print("STEP 2: Add relative_disturbance metric")
print("-" * 70)

# Note: forest_mean_pct only exists at current year (no lags)
# but deadwood and loss have lags, so we calculate for all available combinations
buffers = [100, 200, 300, 400, 500]
lags = ["", "_lag1", "_lag2"]  # "" = current year, _lag1, _lag2

new_cols = []
for buf in buffers:
    for lag_suffix in lags:
        deadwood_col = f"deadwood_mean_pct_{buf}m{lag_suffix}"
        forest_col = f"forest_mean_pct_{buf}m"  # Note: forest has no lag column
        loss_col = f"loss_area_frac_{buf}m{lag_suffix}"
        rel_dist_col = f"relative_disturbance_pct_{buf}m{lag_suffix}"

        # Skip if required columns don't exist
        if deadwood_col not in df.columns or forest_col not in df.columns or loss_col not in df.columns:
            continue

        # Calculate: (deadwood + loss*100) / (forest + loss*100) * 100
        deadwood = df[deadwood_col]
        forest = df[forest_col]
        loss = df[loss_col]

        numerator = deadwood + loss * 100
        denominator = forest + loss * 100

        # Only calculate where denominator > 0
        df[rel_dist_col] = np.where(
            denominator > 0,
            (numerator / denominator) * 100,
            np.nan
        )
        new_cols.append(rel_dist_col)

print(f"Added {len(new_cols)} relative_disturbance columns:")
for col in sorted(new_cols):
    non_na = df[col].notna().sum()
    print(f"  {col}: {non_na} non-NA values")

print()

# ── Verify harmonization ───────────────────────────────────────────────
print("STEP 3: Verify harmonization across EFPs")
print("-" * 70)

efps = ["GPPsat", "NEPmax", "ETmax", "uWUE", "WUE"]
for efp in efps:
    non_na = df[efp].notna().sum()
    sites = df[df[efp].notna()]["SITE_ID"].nunique()
    print(f"{efp:8s}: {non_na:5d} site-years | {sites:3d} sites")

# Check if all identical
coverage_by_efp = {}
for efp in efps:
    coverage_by_efp[efp] = set(df[df[efp].notna()][["SITE_ID","YEAR"]].apply(tuple, axis=1))

all_coverage = set.intersection(*coverage_by_efp.values()) if coverage_by_efp else set()
print()
if len(all_coverage) > 0:
    all_sites = set(s[0] for s in all_coverage)
    print(f"✓ Harmonized: {len(all_coverage)} site-years, {len(all_sites)} sites (all EFPs identical)")
else:
    print(f"✗ NOT harmonized: EFPs have different coverage")

print()

# ── Summary ────────────────────────────────────────────────────────────
print("=" * 70)
print("SUMMARY")
print("=" * 70)
print(f"Removed sites: {', '.join(sorted(remove_sites))}")
print(f"  Reason: no usable uWUE/WUE values (quality control outliers)")
print()
print(f"Output dataset: {len(df)} rows, {df['SITE_ID'].nunique()} sites")
print(f"  All EFPs: 24 site-years × 166 sites (after removing CN-Sb1/2)")

# Verify final counts
final_coverage = set(df[df["GPPsat"].notna()][["SITE_ID","YEAR"]].apply(tuple, axis=1))
final_sites = df[df["GPPsat"].notna()]["SITE_ID"].nunique()
final_years = df[df["GPPsat"].notna()]["YEAR"].nunique()
print(f"  Benchmark: {len(final_coverage)} site-years, {final_sites} sites, {final_years} years")

print()

# ── Save ───────────────────────────────────────────────────────────────
df.to_csv(OUT_FILE, index=False)
print(f"✓ Saved: {OUT_FILE}")
print(f"  Columns: {len(df.columns)}")
print(f"  New disturbance columns: {len(new_cols)}")

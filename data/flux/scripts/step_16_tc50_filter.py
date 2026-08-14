#!/usr/bin/env python3
"""
Step 16: Filter RF-ready dataset to keep only sites with >=50% tree cover
"""

import pandas as pd
import numpy as np

print("\n" + "="*80)
print("STEP 16: FILTER SITES BY TREE COVER (>=50%)")
print("="*80 + "\n")

# Load RF-ready dataset with traits
print("Loading RF-ready dataset with traits...")
df_rf = pd.read_csv('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready_with_traits.csv')

print(f"  Initial rows: {len(df_rf)}")
print(f"  Initial sites: {df_rf['SITE_ID'].nunique()}")
print(f"  Initial columns: {len(df_rf.columns)}\n")

# Get per-site tree cover (average across years)
tree_cover_col = 'tree_cover_mean_pct_500m'
tree_cover_per_site = df_rf.groupby('SITE_ID')[tree_cover_col].mean()

print("Tree cover distribution (500m buffer, per site):")
print(f"  Min: {tree_cover_per_site.min():.1f}%")
print(f"  Max: {tree_cover_per_site.max():.1f}%")
print(f"  Mean: {tree_cover_per_site.mean():.1f}%")
print(f"  Median: {tree_cover_per_site.median():.1f}%\n")

# Identify sites to keep (>=50% tree cover)
sites_keep = tree_cover_per_site[tree_cover_per_site >= 50].index.tolist()
sites_remove = tree_cover_per_site[tree_cover_per_site < 50].index.tolist()

print(f"Sites with <50% tree cover (REMOVE): {len(sites_remove)}")
print("  Examples (lowest 10):")
for site in sorted(sites_remove, key=lambda s: tree_cover_per_site[s])[:10]:
    print(f"    {site}: {tree_cover_per_site[site]:.1f}%")

print(f"\nSites with >=50% tree cover (KEEP): {len(sites_keep)}\n")

# Filter dataset
df_filtered = df_rf[df_rf['SITE_ID'].isin(sites_keep)].reset_index(drop=True)

print("After filtering to >=50% tree cover:")
print(f"  Rows: {len(df_filtered)}")
print(f"  Sites: {df_filtered['SITE_ID'].nunique()}")
print(f"  Rows removed: {len(df_rf) - len(df_filtered)}")
print(f"  Sites removed: {len(sites_remove)}\n")

# Site-year statistics
sites_before_stats = df_rf.groupby('SITE_ID').size()
sites_after_stats = df_filtered.groupby('SITE_ID').size()

print("Site-year distribution:")
print(f"  Before: {len(sites_before_stats)} sites, {sites_before_stats.sum()} site-years")
print(f"  After:  {len(sites_after_stats)} sites, {sites_after_stats.sum()} site-years")
print(f"  Reduction: {len(sites_before_stats) - len(sites_after_stats)} sites " +
      f"({100*(len(sites_before_stats) - len(sites_after_stats))/len(sites_before_stats):.1f}%), " +
      f"{sites_before_stats.sum() - sites_after_stats.sum()} site-years " +
      f"({100*(sites_before_stats.sum() - sites_after_stats.sum())/sites_before_stats.sum():.1f}%)\n")

# Response variable coverage
response_vars = ['GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE']
print("Response variable coverage (after filtering):")
for var in response_vars:
    n_avail = df_filtered[var].notna().sum()
    print(f"  {var}: {n_avail}/{len(df_filtered)} ({100*n_avail/len(df_filtered):.1f}%)")

print()

# Save filtered dataset
out_file = 'derived_tables/outputs_afterEGU_results/v10_tc50/v10_tc50_rf_ready_with_traits.csv'
df_filtered.to_csv(out_file, index=False)

print(f"Saving filtered RF-ready dataset...")
print(f"  File: {out_file}")
print(f"  Size: {df_filtered.memory_usage(deep=True).sum()/1024/1024:.1f} MB")
print(f"  Rows: {len(df_filtered)}")
print(f"  Columns: {len(df_filtered.columns)}\n")

print("✅ STEP 16 COMPLETE - TREE COVER FILTERED DATASET READY")
print("="*80 + "\n")

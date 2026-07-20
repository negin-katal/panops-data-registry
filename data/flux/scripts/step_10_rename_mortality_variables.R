#!/usr/bin/env Rscript
# Step 10: Rename mortality variables

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 10: RENAME MORTALITY VARIABLES\n')
cat('====================================================================\n\n')

# Load combined dataset
cat('Loading combined EFP + disturbance data...\n')
dt <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_combined.csv')

cat('  Rows:', nrow(dt), '\n')
cat('  Columns:', ncol(dt), '\n\n')

# Get all column names
all_cols <- names(dt)

cat('Renaming variables:\n')

# Rename mortality_stock_pct to relative_mortality
# Rename deadwood_mean_pct to absolute_mortality

for (buf in c('100m', '200m', '300m', '400m', '500m')) {
  old_stock <- paste0('mortality_stock_pct_', buf)
  new_stock <- paste0('relative_mortality_', buf)

  old_deadwood <- paste0('deadwood_mean_pct_', buf)
  new_deadwood <- paste0('absolute_mortality_', buf)

  if (old_stock %in% all_cols) {
    setnames(dt, old_stock, new_stock)
    cat(sprintf('  ✓ %s → %s\n', old_stock, new_stock))
  }

  if (old_deadwood %in% all_cols) {
    setnames(dt, old_deadwood, new_deadwood)
    cat(sprintf('  ✓ %s → %s\n', old_deadwood, new_deadwood))
  }
}

cat('\n')

# Save updated dataset
cat('Saving updated dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_combined.csv'
fwrite(dt, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(dt), '\n')
cat('  Columns:', ncol(dt), '\n\n')

cat('✅ STEP 10 COMPLETE\n')
cat('====================================================================\n\n')

#!/usr/bin/env Rscript
# Step 9: Add disturbance/mortality data from v2-2 multibuffer

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 9: ADD DISTURBANCE/MORTALITY DATA (100-500M BUFFERS)\n')
cat('====================================================================\n\n')

# Load EFP yearly with anomalies
cat('Loading EFP data with anomalies...\n')
efp <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_yearly_with_anomalies.csv')

cat('  Rows:', nrow(efp), '\n')
cat('  Sites:', uniqueN(efp$SITE_ID), '\n\n')

# Load disturbance v2-2 multibuffer
cat('Loading disturbance v2-2 data (100-500m buffers)...\n')
dist <- fread('derived_tables/final_disturbance_v2-2_multibuffer.csv')

# Rename columns to match
setnames(dist, c('site_id', 'year'), c('SITE_ID', 'YEAR'))

cat('  Rows:', nrow(dist), '\n')
cat('  Sites:', uniqueN(dist$SITE_ID), '\n')
cat('  Years:', min(dist$YEAR, na.rm=TRUE), '-', max(dist$YEAR, na.rm=TRUE), '\n\n')

# Get column names to show what's available
all_cols <- names(dist)
buffers <- c('100m', '200m', '300m', '400m', '500m')

cat('Available disturbance variables by buffer:\n')
for (buf in buffers) {
  cols_in_buf <- grep(paste0('_', buf, '$'), all_cols, value=TRUE)
  cat(sprintf('  %s: %d variables\n', buf, length(cols_in_buf)))
}

cat('\n')

# Keep only 100-500m buffers (exclude other columns if any)
keep_cols <- c('SITE_ID', 'YEAR')
for (buf in buffers) {
  cols_in_buf <- grep(paste0('_', buf, '$'), all_cols, value=TRUE)
  keep_cols <- c(keep_cols, cols_in_buf)
}

dist_filtered <- dist[, keep_cols, with=FALSE]

cat('Filtered disturbance data:\n')
cat('  Total columns (ID + disturbance):', ncol(dist_filtered), '\n')
cat('  Disturbance-specific columns:', ncol(dist_filtered) - 2, '\n\n')

# Merge EFP with disturbance by SITE_ID and YEAR
cat('Merging EFP with disturbance...\n')

combined <- merge(efp, dist_filtered, by=c('SITE_ID', 'YEAR'), all=TRUE)

cat('  Combined rows:', nrow(combined), '\n')
cat('  Combined sites:', uniqueN(combined$SITE_ID), '\n')
cat('  Combined columns:', ncol(combined), '\n\n')

# Check for missing values
cat('Data availability:\n')
n_complete <- sum(complete.cases(combined))
cat(sprintf('  Complete cases (no NAs): %d (%.1f%%)\n', n_complete, 100*n_complete/nrow(combined)))

n_with_efp <- sum(!is.na(combined$GPPsat) | !is.na(combined$NEPmax) | !is.na(combined$ETmax))
cat(sprintf('  Rows with EFP data: %d (%.1f%%)\n', n_with_efp, 100*n_with_efp/nrow(combined)))

n_with_dist <- sum(!is.na(combined$tree_cover_mean_pct_100m) | !is.na(combined$deadwood_mean_pct_100m))
cat(sprintf('  Rows with disturbance data: %d (%.1f%%)\n', n_with_dist, 100*n_with_dist/nrow(combined)))

n_both <- sum((!is.na(combined$GPPsat) | !is.na(combined$NEPmax) | !is.na(combined$ETmax)) &
              (!is.na(combined$tree_cover_mean_pct_100m) | !is.na(combined$deadwood_mean_pct_100m)))
cat(sprintf('  Rows with both EFP and disturbance: %d (%.1f%%)\n\n', n_both, 100*n_both/nrow(combined)))

# Save combined dataset
cat('Saving combined EFP + disturbance dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_combined.csv'
fwrite(combined, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(combined), '\n')
cat('  Columns:', ncol(combined), '\n\n')

# Summary
cat('Dataset summary:\n')
cat('  EFP variables: 20 (includes anomalies)\n')
cat('  Disturbance variables: 80 (16 metrics × 5 buffers: 100m-500m)\n')
cat('  Total columns: ', ncol(combined), '\n\n')

cat('Disturbance metric groups:\n')
cat('  Group 1 — Tree cover state: tree_cover_mean_pct, deadwood_mean_pct, live_tree_cover_pct\n')
cat('  Group 2 — Mortality stock: mortality_stock_pct\n')
cat('  Group 3 — New mortality: new_deadwood_gain_pp, new_mortality_rate_pct (raw + threshold)\n')
cat('  Group 4 — Tree loss: tree_loss_pp, relative_tree_loss_pct (raw + threshold)\n')
cat('  Group 5 — Combined severity: mortality_loss_severity_pct (raw + threshold)\n\n')

cat('✅ STEP 9 COMPLETE\n')
cat('====================================================================\n\n')

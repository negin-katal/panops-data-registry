#!/usr/bin/env Rscript
# Step 12: Create lag1 and lag2 for EFPs, EFP anomalies, and all disturbances

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 12: CREATE LAG1 & LAG2 FOR EFPs, ANOMALIES, AND DISTURBANCES\n')
cat('====================================================================\n\n')

# Load EFP + disturbance combined
cat('Loading EFP + disturbance combined...\n')
dt <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_combined.csv')

cat('  Rows:', nrow(dt), '\n')
cat('  Sites:', uniqueN(dt$SITE_ID), '\n')
cat('  Years:', min(dt$YEAR, na.rm=TRUE), '-', max(dt$YEAR, na.rm=TRUE), '\n\n')

# Sort by site and year
setorder(dt, SITE_ID, YEAR)

# Identify columns to lag
efp_cols <- grep('^(GPPsat|NEPmax|ETmax|uWUE|WUE)$', names(dt), value=TRUE)
efp_anom_cols <- grep('^(GPPsat|NEPmax|ETmax|uWUE|WUE)_anom$', names(dt), value=TRUE)

# All disturbance columns (anything ending with _100m through _500m)
dist_cols <- grep('_([1-5]00m)$', names(dt), value=TRUE)

cat('Variables to create lags for:\n')
cat('  EFP variables:', length(efp_cols), '\n')
cat('    ', paste(efp_cols, collapse=', '), '\n')
cat('  EFP anomalies:', length(efp_anom_cols), '\n')
cat('    ', paste(efp_anom_cols, collapse=', '), '\n')
cat('  Disturbance metrics:', length(dist_cols), '\n')
cat('    (', length(unique(gsub('_[1-5]00m$', '', dist_cols))), 'unique metrics × 5 buffers )\n\n')

# Create lag1 and lag2 ONLY for rows with continuous years
all_cols_to_lag <- c(efp_cols, efp_anom_cols, dist_cols)

cat('Creating lag1 and lag2 (only for continuous years)...\n')

# First, identify which rows have continuous data
dt[, has_lag1 := shift(YEAR, 1) == (YEAR - 1), by=SITE_ID]
dt[, has_lag2 := shift(YEAR, 2) == (YEAR - 2), by=SITE_ID]

for (col in all_cols_to_lag) {
  lag1_name <- paste0(col, '_lag1')
  lag2_name <- paste0(col, '_lag2')

  # Shift values by site
  lag1_vals <- shift(dt[[col]], 1, NA, 'lag')
  lag2_vals <- shift(dt[[col]], 2, NA, 'lag')

  # Create lag columns, set to NA where continuous years missing
  dt[, (lag1_name) := ifelse(has_lag1 == TRUE, lag1_vals, NA_real_)]
  dt[, (lag2_name) := ifelse(has_lag2 == TRUE, lag2_vals, NA_real_)]
}

cat(sprintf('  Created lags for %d variables\n', length(all_cols_to_lag)))
cat(sprintf('  Added %d lag columns (lag1 + lag2)\n', length(all_cols_to_lag) * 2))
cat('  Total columns now:', ncol(dt), '\n')
cat('  NOTE: Lags set to NA where continuous years missing\n\n')

n_with_lag1 <- sum(dt$has_lag1 == TRUE, na.rm=TRUE)
n_with_lag2 <- sum(dt$has_lag2 == TRUE, na.rm=TRUE)

cat('Lag availability:\n')
cat(sprintf('  Rows with lag1 data: %d (%.1f%%)\n', n_with_lag1, 100*n_with_lag1/nrow(dt)))
cat(sprintf('  Rows with lag2 data: %d (%.1f%%)\n', n_with_lag2, 100*n_with_lag2/nrow(dt)))
cat(sprintf('  Rows with continuous years (has_lag1): %d\n', n_with_lag1))
cat(sprintf('  Rows with continuous 2-year span (has_lag2): %d\n\n', n_with_lag2))

# Remove helper columns
dt[, c('has_lag1', 'has_lag2') := NULL]

# Save with lags
cat('Saving dataset with lags...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_with_lags.csv'
fwrite(dt, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(dt), '\n')
cat('  Columns:', ncol(dt), '\n\n')

# Summary
cat('FINAL DATASET WITH LAGS:\n')
cat(sprintf('  EFP: %d variables + lag1 + lag2 = %d columns\n',
            length(efp_cols), length(efp_cols) * 3))
cat(sprintf('  EFP anomalies: %d variables + lag1 + lag2 = %d columns\n',
            length(efp_anom_cols), length(efp_anom_cols) * 3))
cat(sprintf('  Disturbance: %d variables + lag1 + lag2 = %d columns\n',
            length(dist_cols), length(dist_cols) * 3))
cat(sprintf('  Metadata: 2 (SITE_ID, YEAR)\n'))
cat(sprintf('  TOTAL COLUMNS: %d\n\n', ncol(dt)))

cat('✅ STEP 12 COMPLETE - READY FOR METEO LAG MERGE\n')
cat('====================================================================\n\n')

#!/usr/bin/env Rscript
# Step 8: Calculate EFP anomalies from EFP_yearly_combined.csv

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 8: CALCULATE EFP ANOMALIES FROM YEARLY COMBINED DATA\n')
cat('====================================================================\n\n')

# Load EFP yearly combined data
cat('Loading EFP yearly combined data...\n')
dt <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_yearly_combined.csv')

cat('  Rows:', nrow(dt), '\n')
cat('  Sites:', uniqueN(dt$SITE_ID), '\n')
cat('  Years:', min(dt$YEAR, na.rm=TRUE), '-', max(dt$YEAR, na.rm=TRUE), '\n\n')

# EFP variables to calculate anomalies for
efp_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'WUE', 'uWUE')

cat('Calculating anomalies for:', paste(efp_vars, collapse=', '), '\n\n')

# Sort by site and year for clarity
setorder(dt, SITE_ID, YEAR)

# Calculate anomalies per site (z-score: (value - mean) / sd)
for (var in efp_vars) {
  anom_name <- paste0(var, '_anom')

  dt[, (anom_name) := {
    vals <- get(var)
    mean_val <- mean(vals, na.rm=TRUE)
    sd_val <- sd(vals, na.rm=TRUE)

    if (is.na(sd_val) || sd_val == 0) {
      rep(NA_real_, length(vals))
    } else {
      (vals - mean_val) / sd_val
    }
  }, by=SITE_ID]
}

cat('✅ Anomalies calculated\n')
cat('  New columns:', paste(paste0(efp_vars, '_anom'), collapse=', '), '\n')
cat('  Total columns now:', ncol(dt), '\n\n')

# Show summary statistics
cat('Anomaly statistics:\n\n')

for (var in efp_vars) {
  anom_name <- paste0(var, '_anom')
  anom_vals <- dt[[anom_name]]
  non_na <- anom_vals[!is.na(anom_vals)]

  if (length(non_na) > 0) {
    cat(sprintf('%s:\n', anom_name))
    cat(sprintf('  Mean: %.2f (should be ~0)\n', mean(non_na)))
    cat(sprintf('  SD: %.2f (should be ~1)\n', sd(non_na)))
    cat(sprintf('  Range: [%.2f, %.2f]\n', min(non_na), max(non_na)))
    cat(sprintf('  Missing: %d\n\n', sum(is.na(anom_vals))))
  }
}

# Save updated dataset
cat('Saving dataset with anomalies...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/EFP_yearly_with_anomalies.csv'
fwrite(dt, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(dt), '\n')
cat('  Columns:', ncol(dt), '\n\n')

cat('✅ STEP 8 COMPLETE\n')
cat('====================================================================\n\n')

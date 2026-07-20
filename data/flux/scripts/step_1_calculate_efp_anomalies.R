#!/usr/bin/env Rscript
# Step 1: Calculate EFP anomalies from the wide metadata file

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 1: CALCULATE EFP ANOMALIES\n')
cat('====================================================================\n\n')

# Load data
cat('Loading data...\n')
dt <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/EFP_metadata_monthlyMeteo_WIDE.csv')

cat('  Rows:', nrow(dt), '\n')
cat('  Sites:', uniqueN(dt$SITE_ID), '\n')
cat('  Years:', min(dt$YEAR, na.rm=TRUE), '-', max(dt$YEAR, na.rm=TRUE), '\n\n')

# Calculate anomalies for 5 EFP variables
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
cat('  New columns:', paste(paste0(efp_vars, '_anom'), collapse=', '), '\n\n')

# Save output
cat('Saving to temporary output...\n')
temp_output <- 'derived_tables/temp_step1_with_anomalies.csv'
dir.create('derived_tables', showWarnings=FALSE)
fwrite(dt, temp_output)

cat('  Saved:', temp_output, '\n')
cat('  Size:', round(file.size(temp_output)/1024/1024, 1), 'MB\n\n')

cat('✅ STEP 1 COMPLETE\n')
cat('====================================================================\n\n')

#!/usr/bin/env Rscript
# Step 14: Clean dataset to keep only usable rows for RF modeling

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 14: CLEAN DATASET FOR RF MODELING\n')
cat('====================================================================\n\n')

# Load final dataset
cat('Loading v10_final_complete...\n')
dt <- fread('derived_tables/outputs_afterEGU_results/v10/v10_final_complete.csv')

cat('  Initial rows:', nrow(dt), '\n')
cat('  Initial sites:', uniqueN(dt$SITE_ID), '\n')
cat('  Initial columns:', ncol(dt), '\n\n')

# Filter to keep only rows with BOTH EFP and meteo lags
cat('Filtering to rows with BOTH EFP/disturbance AND meteo lags...\n')

has_efp <- !is.na(dt$GPPsat) | !is.na(dt$NEPmax) | !is.na(dt$ETmax) | !is.na(dt$uWUE) | !is.na(dt$WUE)
has_meteo <- !is.na(dt$lag1_M01_TA_mean) | !is.na(dt$lag2_M01_TA_mean)

usable_rows <- has_efp & has_meteo

dt_clean <- dt[usable_rows]

cat('  After filtering:\n')
cat('  Rows:', nrow(dt_clean), '\n')
cat('  Sites:', uniqueN(dt_clean$SITE_ID), '\n')
cat('  Columns:', ncol(dt_clean), '\n\n')

# Check response variable coverage
cat('Response variable coverage:\n')
response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')
for (var in response_vars) {
  n_avail <- sum(!is.na(dt_clean[[var]]))
  cat(sprintf('  %s: %d rows (%.1f%%)\n', var, n_avail, 100*n_avail/nrow(dt_clean)))
}

cat('\n')

# Check key predictor availability
cat('Key predictor availability:\n')

# Check meteo (should all be there)
meteo_check <- sum(!is.na(dt_clean$lag1_M01_TA_mean))
cat(sprintf('  Lag1 meteo: %d rows (%.1f%%)\n', meteo_check, 100*meteo_check/nrow(dt_clean)))

# Check disturbance
dist_check <- sum(!is.na(dt_clean$absolute_mortality_500m))
cat(sprintf('  Disturbance: %d rows (%.1f%%)\n', dist_check, 100*dist_check/nrow(dt_clean)))

# Check relative disturbance
rel_dist_check <- sum(!is.na(dt_clean$relative_disturbance_500m))
cat(sprintf('  Relative disturbance: %d rows (%.1f%%)\n\n', rel_dist_check, 100*rel_dist_check/nrow(dt_clean)))

# Year range
cat('Year coverage:\n')
cat('  Range:', min(dt_clean$YEAR, na.rm=TRUE), '-', max(dt_clean$YEAR, na.rm=TRUE), '\n')
cat('  Unique years:', uniqueN(dt_clean$YEAR), '\n\n')

# Site distribution
cat('Site-year distribution:\n')
site_years <- dt_clean[, .N, by=SITE_ID][order(-N)]
cat('  Mean years per site:', round(mean(site_years$N), 1), '\n')
cat('  Median years per site:', median(site_years$N), '\n')
cat('  Range:', min(site_years$N), '-', max(site_years$N), '\n')
cat('  Sites with >= 5 years:', nrow(site_years[N >= 5]), '\n')
cat('  Sites with >= 10 years:', nrow(site_years[N >= 10]), '\n\n')

# Save clean dataset
cat('Saving cleaned dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_rf_ready.csv'
fwrite(dt_clean, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(dt_clean), '\n')
cat('  Columns:', ncol(dt_clean), '\n\n')

cat('✅ STEP 14 COMPLETE - RF-READY DATASET\n')
cat('====================================================================\n\n')

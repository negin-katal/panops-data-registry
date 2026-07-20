#!/usr/bin/env Rscript
# Step 15: Extract and merge plant traits to RF-ready dataset

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 15: MERGE PLANT TRAITS TO RF-READY DATASET\n')
cat('====================================================================\n\n')

# Load RF-ready dataset
cat('Loading RF-ready dataset...\n')
dt_rf <- fread('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready.csv')

cat('  Rows:', nrow(dt_rf), '\n')
cat('  Sites:', uniqueN(dt_rf$SITE_ID), '\n')
cat('  Columns:', ncol(dt_rf), '\n\n')

# Load V3 traits
cat('Loading V3 plant traits...\n')
v3_file <- 'derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv'
dt_v3 <- fread(v3_file, select=c('SITE_ID', 'P12_mean', 'P50_mean', 'P88_mean', 'gsmax_mean', 'rdmax_mean'))

# Keep only unique sites (traits are static per site)
dt_v3_static <- dt_v3[!duplicated(SITE_ID)]

cat('  Trait columns found: P12_mean, P50_mean, P88_mean, gsmax_mean, rdmax_mean\n')
cat('  Sites with traits:', nrow(dt_v3_static), '\n\n')

# Merge traits to RF dataset
cat('Merging traits by SITE_ID...\n')

dt_final <- merge(dt_rf, dt_v3_static, by='SITE_ID', all.x=TRUE)

cat('  Final rows:', nrow(dt_final), '\n')
cat('  Final columns:', ncol(dt_final), '\n')
cat('  Columns added: 5 trait variables\n\n')

# Check trait availability
trait_cols <- c('P12_mean', 'P50_mean', 'P88_mean', 'gsmax_mean', 'rdmax_mean')

cat('Trait availability:\n')
for (col in trait_cols) {
  n_avail <- sum(!is.na(dt_final[[col]]))
  cat(sprintf('  %s: %d rows (%.1f%%)\n', col, n_avail, 100*n_avail/nrow(dt_final)))
}

cat('\n')

# Save final dataset with traits
cat('Saving final RF-ready dataset with traits...\n')

out_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_rf_ready_with_traits.csv'
fwrite(dt_final, out_file)

cat(sprintf('  Saved: %s\n', out_file))
cat(sprintf('  Size: %.1f MB\n', file.size(out_file)/1024/1024))
cat(sprintf('  Rows: %d site-years\n', nrow(dt_final)))
cat(sprintf('  Columns: %d\n', ncol(dt_final)))
cat(sprintf('    - Original: 556\n')
cat(sprintf('    - Traits added: 5\n')
cat(sprintf('    - Total: %d\n\n', ncol(dt_final)))

# Summary
cat('DATASET SUMMARY:\n')
cat('  Response variables: 5 (GPPsat, NEPmax, ETmax, uWUE, WUE)\n')
cat('  Response anomalies: 5\n')
cat('  Disturbance metrics (current + lag1 + lag2): 225\n')
cat('  Meteo lags (CGS monthly): 286\n')
cat('  Plant traits (static): 5\n')
cat('  Metadata: 2\n')
cat(sprintf('  TOTAL: %d columns\n\n', ncol(dt_final)))

cat('✅ STEP 15 COMPLETE - READY FOR RF MODELING WITH TRAITS\n')
cat('====================================================================\n\n')

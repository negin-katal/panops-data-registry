#!/usr/bin/env Rscript
# Step 13: Combine EFP+disturbance with lags with meteo lags by SITE_ID and YEAR

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 13: COMBINE EFP+DISTURBANCE LAGS WITH METEO LAGS\n')
cat('====================================================================\n\n')

# Load EFP + disturbance with lags
cat('Loading EFP + disturbance with lags...\n')
efp_dist_lags <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_with_lags.csv')

cat('  Rows:', nrow(efp_dist_lags), '\n')
cat('  Columns:', ncol(efp_dist_lags), '\n')
cat('  Sites:', uniqueN(efp_dist_lags$SITE_ID), '\n\n')

# Load meteo lags by CGS month
cat('Loading meteo lags by CGS month...\n')
meteo_lags <- fread('derived_tables/outputs_afterEGU_results/v10/meteo_lags_by_cgs_month.csv')

cat('  Rows:', nrow(meteo_lags), '\n')
cat('  Columns:', ncol(meteo_lags), '\n')
cat('  Sites:', uniqueN(meteo_lags$SITE_ID), '\n\n')

# Merge by SITE_ID and YEAR
cat('Merging by SITE_ID and YEAR...\n')

combined_final <- merge(efp_dist_lags, meteo_lags, by=c('SITE_ID', 'YEAR'), all=TRUE)

cat('  Combined rows:', nrow(combined_final), '\n')
cat('  Combined sites:', uniqueN(combined_final$SITE_ID), '\n')
cat('  Combined columns:', ncol(combined_final), '\n\n')

# Check data availability
cat('Data availability:\n')

n_with_efp_dist <- sum(!is.na(combined_final$GPPsat) | !is.na(combined_final$NEPmax))
cat(sprintf('  Rows with EFP/disturbance: %d (%.1f%%)\n',
            n_with_efp_dist, 100*n_with_efp_dist/nrow(combined_final)))

n_with_meteo_lag <- sum(!is.na(combined_final$lag1_M01_TA_mean) | !is.na(combined_final$lag2_M01_TA_mean))
cat(sprintf('  Rows with meteo lags: %d (%.1f%%)\n',
            n_with_meteo_lag, 100*n_with_meteo_lag/nrow(combined_final)))

n_both <- sum((!is.na(combined_final$GPPsat) | !is.na(combined_final$NEPmax)) &
              (!is.na(combined_final$lag1_M01_TA_mean) | !is.na(combined_final$lag2_M01_TA_mean)))
cat(sprintf('  Rows with BOTH EFP/disturbance AND meteo lags: %d (%.1f%%)\n\n',
            n_both, 100*n_both/nrow(combined_final)))

# Save final combined dataset
cat('Saving final combined dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_final_complete.csv'
fwrite(combined_final, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(combined_final), '\n')
cat('  Columns:', ncol(combined_final), '\n\n')

# Summary
cat('FINAL COMPREHENSIVE DATASET:\n')
cat('  EFP variables (current + lag1 + lag2): 15 columns\n')
cat('  EFP anomalies (current + lag1 + lag2): 15 columns\n')
cat('  Disturbance metrics (current + lag1 + lag2): 225 columns\n')
cat('  Meteo lags (CGS-based, monthly individual): 286 columns\n')
cat('  Metadata (SITE_ID, YEAR): 2 columns\n')
cat(sprintf('  TOTAL COLUMNS: %d\n\n', ncol(combined_final)))

cat('✅ STEP 13 COMPLETE - FINAL DATASET READY FOR MODELING\n')
cat('====================================================================\n\n')

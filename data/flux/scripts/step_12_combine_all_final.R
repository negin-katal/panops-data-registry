#!/usr/bin/env Rscript
# Step 12: Combine EFP + disturbance with meteo lags by SITE_ID and YEAR

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 12: COMBINE EFP+DISTURBANCE WITH METEO LAGS\n')
cat('====================================================================\n\n')

# Load EFP + disturbance combined
cat('Loading EFP + disturbance combined...\n')
efp_dist <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_combined.csv')

cat('  Rows:', nrow(efp_dist), '\n')
cat('  Columns:', ncol(efp_dist), '\n')
cat('  Sites:', uniqueN(efp_dist$SITE_ID), '\n\n')

# Load meteo lags by CGS month
cat('Loading meteo lags by CGS month...\n')
meteo_lags <- fread('derived_tables/outputs_afterEGU_results/v10/meteo_lags_by_cgs_month.csv')

cat('  Rows:', nrow(meteo_lags), '\n')
cat('  Columns:', ncol(meteo_lags), '\n')
cat('  Sites:', uniqueN(meteo_lags$SITE_ID), '\n\n')

# Merge by SITE_ID and YEAR (inner join to keep matching rows)
cat('Merging by SITE_ID and YEAR...\n')

combined_final <- merge(efp_dist, meteo_lags, by=c('SITE_ID', 'YEAR'), all=TRUE)

cat('  Combined rows:', nrow(combined_final), '\n')
cat('  Combined sites:', uniqueN(combined_final$SITE_ID), '\n')
cat('  Combined columns:', ncol(combined_final), '\n\n')

# Check data availability
cat('Data availability:\n')
n_with_efp_dist <- sum(!is.na(combined_final$GPPsat) | !is.na(combined_final$NEPmax))
cat(sprintf('  Rows with EFP/disturbance: %d (%.1f%%)\n', n_with_efp_dist, 100*n_with_efp_dist/nrow(combined_final)))

n_with_meteo_lag <- sum(!is.na(combined_final$lag1_M01_TA_mean) | !is.na(combined_final$lag2_M01_TA_mean))
cat(sprintf('  Rows with meteo lags: %d (%.1f%%)\n', n_with_meteo_lag, 100*n_with_meteo_lag/nrow(combined_final)))

n_both <- sum((!is.na(combined_final$GPPsat) | !is.na(combined_final$NEPmax)) &
              (!is.na(combined_final$lag1_M01_TA_mean) | !is.na(combined_final$lag2_M01_TA_mean)))
cat(sprintf('  Rows with both EFP/disturbance AND meteo lags: %d (%.1f%%)\n\n', n_both, 100*n_both/nrow(combined_final)))

# Save combined dataset
cat('Saving final combined dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_final_complete.csv'
fwrite(combined_final, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(combined_final), '\n')
cat('  Columns:', ncol(combined_final), '\n\n')

# Summary
cat('FINAL DATASET COMPOSITION:\n')
cat('  EFP variables: 20 (includes 5 anomalies)\n')
cat('  Disturbance metrics: 70 (14 metrics × 5 buffers)\n')
cat('  Relative disturbance: 5 (one per buffer)\n')
cat('  Meteo lags (individual monthly): 286 (11 variables × 13 months × 2 lags)\n')
cat('  Metadata: 3 (SITE_ID, YEAR, and any other)\n')
cat('  TOTAL COLUMNS:', ncol(combined_final), '\n\n')

# Show sample of columns
cat('Column categories:\n')
cat('  EFP/anomalies: ', length(grep('^(GPPsat|NEPmax|ETmax|uWUE|WUE)', names(combined_final), value=TRUE)), '\n')
cat('  Disturbance: ', length(grep('_[0-9]{3}m$', names(combined_final), value=TRUE)), '\n')
cat('  Relative disturbance: ', length(grep('^relative_disturbance_', names(combined_final), value=TRUE)), '\n')
cat('  Meteo lags: ', length(grep('^lag[12]_', names(combined_final), value=TRUE)), '\n\n')

cat('✅ STEP 12 COMPLETE - FINAL DATASET READY\n')
cat('====================================================================\n\n')

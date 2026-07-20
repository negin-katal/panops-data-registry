#!/usr/bin/env Rscript
# Step 7: Combine EFP data with meteo lags by SITE_ID and YEAR

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 7: COMBINE EFP WITH METEO LAGS BY CGS MONTH\n')
cat('====================================================================\n\n')

# Load EFP yearly combined data
cat('Loading EFP yearly combined data...\n')
efp <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_yearly_combined.csv')

cat('  Rows:', nrow(efp), '\n')
cat('  Sites:', uniqueN(efp$SITE_ID), '\n')
cat('  Columns:', ncol(efp), '\n\n')

# Load meteo lags
cat('Loading meteo lags by CGS month...\n')
meteo_lags <- fread('derived_tables/outputs_afterEGU_results/v10/meteo_lags_by_cgs_month.csv')

cat('  Rows:', nrow(meteo_lags), '\n')
cat('  Sites:', uniqueN(meteo_lags$SITE_ID), '\n')
cat('  Columns:', ncol(meteo_lags), '\n\n')

# Merge by SITE_ID and YEAR
cat('Merging by SITE_ID and YEAR...\n')

combined <- merge(efp, meteo_lags, by=c('SITE_ID', 'YEAR'), all=TRUE)

cat('  Combined rows:', nrow(combined), '\n')
cat('  Combined sites:', uniqueN(combined$SITE_ID), '\n')
cat('  Combined columns:', ncol(combined), '\n\n')

# Check for missing values
cat('Data availability:\n')
n_complete <- sum(complete.cases(combined))
cat(sprintf('  Complete cases (no NAs): %d (%.1f%%)\n', n_complete, 100*n_complete/nrow(combined)))

# Count rows with EFP data
n_with_efp <- sum(!is.na(combined$GPPsat) | !is.na(combined$NEPmax) | !is.na(combined$ETmax) | !is.na(combined$uWUE))
cat(sprintf('  Rows with EFP data: %d (%.1f%%)\n', n_with_efp, 100*n_with_efp/nrow(combined)))

# Count rows with meteo lags
n_with_meteo <- sum(!is.na(combined$lag1_M01_TA_mean) | !is.na(combined$lag2_M01_TA_mean))
cat(sprintf('  Rows with meteo lags: %d (%.1f%%)\n', n_with_meteo, 100*n_with_meteo/nrow(combined)))

# Count rows with both
n_both <- sum((!is.na(combined$GPPsat) | !is.na(combined$NEPmax) | !is.na(combined$ETmax) | !is.na(combined$uWUE)) &
              (!is.na(combined$lag1_M01_TA_mean) | !is.na(combined$lag2_M01_TA_mean)))
cat(sprintf('  Rows with both EFP and meteo lags: %d (%.1f%%)\n\n', n_both, 100*n_both/nrow(combined)))

# Save combined dataset
cat('Saving combined EFP + meteo lags dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/EFP_meteo_lags_combined.csv'
fwrite(combined, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(combined), '\n')
cat('  Columns:', ncol(combined), '\n\n')

cat('✅ STEP 7 COMPLETE\n')
cat('====================================================================\n\n')

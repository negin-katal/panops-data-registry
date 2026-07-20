#!/usr/bin/env Rscript
# Step 5: Aggregate monthly meteo to yearly and combine with yearly EFP

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 5: COMBINE MONTHLY METEO & YEARLY EFP BY SITE-YEAR\n')
cat('====================================================================\n\n')

# Load cleaned monthly meteo
cat('Loading cleaned monthly meteo data...\n')
meteo_monthly <- fread('derived_tables/outputs_afterEGU_results/v10/meteo_monthly_cleaned.csv')

cat('  Rows:', nrow(meteo_monthly), '\n')
cat('  Sites:', uniqueN(meteo_monthly$SITE_ID), '\n')
cat('  Years:', min(meteo_monthly$YEAR, na.rm=TRUE), '-', max(meteo_monthly$YEAR, na.rm=TRUE), '\n\n')

# Aggregate monthly meteo to yearly
# Temperature (TA) and radiation (SW_IN): average across months
# Precipitation (P): sum across months
# VPD: average across months

cat('Aggregating monthly meteo to yearly...\n')

meteo_yearly <- meteo_monthly[, .(
  # Temperature: average
  TA_mean = mean(TA_mean, na.rm=TRUE),
  TA_p05 = mean(TA_p05, na.rm=TRUE),
  TA_p95 = mean(TA_p95, na.rm=TRUE),

  # VPD: average
  VPD_mean = mean(VPD_mean, na.rm=TRUE),
  VPD_p05 = mean(VPD_p05, na.rm=TRUE),
  VPD_p95 = mean(VPD_p95, na.rm=TRUE),

  # Radiation: average
  SW_IN_mean = mean(SW_IN_mean, na.rm=TRUE),
  SW_IN_p05 = mean(SW_IN_p05, na.rm=TRUE),
  SW_IN_p95 = mean(SW_IN_p95, na.rm=TRUE),

  # Precipitation: sum
  P_sum = sum(P_sum, na.rm=TRUE),
  P_mean = mean(P_mean, na.rm=TRUE),

  # Metadata
  n_months_available = sum(!is.na(TA_mean))
), by=.(SITE_ID, YEAR)]

cat('  Aggregated to:', nrow(meteo_yearly), 'site-years\n')
cat('  Sites:', uniqueN(meteo_yearly$SITE_ID), '\n\n')

# Load yearly EFP data
cat('Loading yearly EFP data...\n')
efp_yearly <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_yearly_combined.csv')

cat('  Rows:', nrow(efp_yearly), '\n')
cat('  Sites:', uniqueN(efp_yearly$SITE_ID), '\n\n')

# Merge by SITE_ID and YEAR (inner join to keep only matching rows)
cat('Merging meteo and EFP by SITE_ID, YEAR...\n')

combined <- merge(efp_yearly, meteo_yearly, by=c('SITE_ID', 'YEAR'), all=TRUE)

cat('  Combined rows:', nrow(combined), '\n')
cat('  Combined sites:', uniqueN(combined$SITE_ID), '\n')
cat('  Combined columns:', ncol(combined), '\n\n')

# Check for missing values
cat('Missing values by variable:\n')
missing_cols <- names(combined)[sapply(combined, function(x) any(is.na(x)))]

for (col in missing_cols) {
  n_missing <- sum(is.na(combined[[col]]))
  pct_missing <- 100 * n_missing / nrow(combined)
  if (pct_missing > 0.1) {  # Only show if > 0.1% missing
    cat(sprintf('  %s: %d (%.1f%%)\n', col, n_missing, pct_missing))
  }
}

cat('\n')

# Save combined dataset
cat('Saving combined EFP + meteo dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/EFP_meteo_yearly_combined.csv'
fwrite(combined, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(combined), '\n')
cat('  Columns:', ncol(combined), '\n\n')

# Summary
cat('Dataset summary:\n')
cat('  SITE_ID: unique sites =', uniqueN(combined$SITE_ID), '\n')
cat('  YEAR: range =', min(combined$YEAR, na.rm=TRUE), '-', max(combined$YEAR, na.rm=TRUE), '\n')
cat('  EFP variables: 13 (uWUE, WUE, ETmax, GSmax, G1, EF, EFampl, GPPsat, NEPmax, Rb, Rbmax, aCUE, nyears)\n')
cat('  Meteo variables: 11 (TA_mean, TA_p05, TA_p95, VPD_mean, VPD_p05, VPD_p95, SW_IN_mean, SW_IN_p05, SW_IN_p95, P_sum, P_mean)\n')
cat('  Anomaly columns: 5 (GPPsat_anom, NEPmax_anom, ETmax_anom, WUE_anom, uWUE_anom)\n\n')

cat('✅ STEP 5 COMPLETE\n')
cat('====================================================================\n\n')

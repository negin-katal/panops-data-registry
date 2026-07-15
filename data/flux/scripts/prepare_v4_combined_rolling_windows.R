#!/usr/bin/env Rscript
# Combine corrected monthly meteo + yearly EFP
# Apply rolling 2-year and 3-year windows
# Save as v4 datasets

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('📊 Creating v4 Combined Dataset with Rolling Windows\n')
cat('===================================================\n\n')

# =========================================================
# 1) Load data
# =========================================================

cat('Loading data...\n')
meteo_monthly <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_MONTHLY_METEO_corrected.csv')
efp_yearly <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_YEARLY_EFP_min4continuousYears.csv')
cont_years <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/SITE_VALID_CONTINUOUS_YEARS.csv')

cat('Meteo: ', nrow(meteo_monthly), 'rows\n')
cat('EFP: ', nrow(efp_yearly), 'rows\n')
cat('Continuity info: ', nrow(cont_years), 'sites\n\n')

# =========================================================
# 2) Aggregate monthly meteo to yearly
# =========================================================

cat('Aggregating monthly meteorology to yearly...\n')

meteo_yearly <- meteo_monthly[, .(
  TA_mean = mean(TA_mean, na.rm = TRUE),
  TA_p05 = mean(TA_p05, na.rm = TRUE),
  TA_p95 = mean(TA_p95, na.rm = TRUE),
  VPD_mean = mean(VPD_mean, na.rm = TRUE),
  VPD_p05 = mean(VPD_p05, na.rm = TRUE),
  VPD_p95 = mean(VPD_p95, na.rm = TRUE),
  SW_IN_mean = mean(SW_IN_mean, na.rm = TRUE),
  SW_IN_p05 = mean(SW_IN_p05, na.rm = TRUE),
  SW_IN_p95 = mean(SW_IN_p95, na.rm = TRUE),
  P_sum = sum(P_sum, na.rm = TRUE),
  P_mean = mean(P_mean, na.rm = TRUE),
  n_months = .N
), by = .(SITE_ID, YEAR)]

cat('Aggregated to ', nrow(meteo_yearly), ' site-year combinations\n\n')

# =========================================================
# 3) Merge meteo + EFP
# =========================================================

cat('Merging meteorology + EFP...\n')

v4_base <- merge(
  efp_yearly,
  meteo_yearly,
  by = c('SITE_ID', 'YEAR'),
  all.x = TRUE
)

cat('Combined dataset: ', nrow(v4_base), 'rows\n')
cat('Columns: ', ncol(v4_base), '\n\n')

# Save base combined dataset
out_dir <- 'derived_tables/outputs_afterEGU_results/V4_combined'
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

base_file <- file.path(out_dir, 'EFP_meteo_combined_v4_base.csv')
fwrite(v4_base, base_file)
cat('✅ Base combined dataset saved to:', base_file, '\n\n')

# =========================================================
# 4) Apply rolling 2-year window
# =========================================================

cat('Creating rolling 2-year window dataset...\n')

v4_2year <- v4_base[order(SITE_ID, YEAR)]

# Add lags for EFP and meteo
meteo_cols <- c('TA_mean', 'TA_p05', 'TA_p95', 'VPD_mean', 'VPD_p05', 'VPD_p95',
                'SW_IN_mean', 'SW_IN_p05', 'SW_IN_p95', 'P_sum', 'P_mean')
efp_cols <- c('uWUE', 'WUE', 'ETmax', 'GPPsat', 'NEPmax', 'GSmax', 'G1')

# Add lagged EFP (lag 1 year = previous year's EFP)
for (col in efp_cols) {
  new_col <- paste0(col, '_lag1')
  v4_2year[, (new_col) := shift(get(col), 1, NA, 'lag'), by = SITE_ID]
}

# Add lagged meteo
for (col in meteo_cols) {
  new_col <- paste0(col, '_lag1')
  v4_2year[, (new_col) := shift(get(col), 1, NA, 'lag'), by = SITE_ID]
}

# Filter to complete 2-year rolling windows (current + lag1)
check_cols_2y <- c(efp_cols, paste0(efp_cols, '_lag1'))
v4_2year_complete <- v4_2year[, is_complete := apply(.SD, 1, function(x) all(!is.na(x))), .SDcols = check_cols_2y
                              ][is_complete == TRUE, ]
v4_2year_complete[, is_complete := NULL]

cat('2-year rolling window: ', nrow(v4_2year_complete), 'complete rows\n')
cat('Sites: ', uniqueN(v4_2year_complete$SITE_ID), '\n')

file_2y <- file.path(out_dir, 'EFP_meteo_combined_v4_rolling2year.csv')
fwrite(v4_2year_complete, file_2y)
cat('✅ 2-year rolling dataset saved to:', file_2y, '\n\n')

# =========================================================
# 5) Apply rolling 3-year window
# =========================================================

cat('Creating rolling 3-year window dataset...\n')

v4_3year <- v4_base[order(SITE_ID, YEAR)]

# Add lags for lag1 and lag2 (previous 2 years)
for (col in efp_cols) {
  new_col_1 <- paste0(col, '_lag1')
  new_col_2 <- paste0(col, '_lag2')
  v4_3year[, (new_col_1) := shift(get(col), 1, NA, 'lag'), by = SITE_ID]
  v4_3year[, (new_col_2) := shift(get(col), 2, NA, 'lag'), by = SITE_ID]
}

# Add lagged meteo
for (col in meteo_cols) {
  new_col_1 <- paste0(col, '_lag1')
  new_col_2 <- paste0(col, '_lag2')
  v4_3year[, (new_col_1) := shift(get(col), 1, NA, 'lag'), by = SITE_ID]
  v4_3year[, (new_col_2) := shift(get(col), 2, NA, 'lag'), by = SITE_ID]
}

# Filter to complete 3-year rolling windows (current + lag1 + lag2)
check_cols_3y <- c(efp_cols, paste0(efp_cols, '_lag1'), paste0(efp_cols, '_lag2'))
v4_3year_complete <- v4_3year[, is_complete := apply(.SD, 1, function(x) all(!is.na(x))), .SDcols = check_cols_3y
                              ][is_complete == TRUE, ]
v4_3year_complete[, is_complete := NULL]

cat('3-year rolling window: ', nrow(v4_3year_complete), 'complete rows\n')
cat('Sites: ', uniqueN(v4_3year_complete$SITE_ID), '\n')

file_3y <- file.path(out_dir, 'EFP_meteo_combined_v4_rolling3year.csv')
fwrite(v4_3year_complete, file_3y)
cat('✅ 3-year rolling dataset saved to:', file_3y, '\n\n')

# =========================================================
# 6) Summary statistics
# =========================================================

cat('\n📊 SUMMARY STATISTICS:\n')
cat('======================\n\n')

cat('Base combined dataset (all available data):\n')
cat('  Rows: ', nrow(v4_base), '\n')
cat('  Sites: ', uniqueN(v4_base$SITE_ID), '\n')
cat('  Year range: ', min(v4_base$YEAR, na.rm=TRUE), '-', max(v4_base$YEAR, na.rm=TRUE), '\n')
cat('  Columns: ', ncol(v4_base), '\n\n')

cat('Rolling 2-year window (current + lag1):\n')
cat('  Rows: ', nrow(v4_2year_complete), '\n')
cat('  Sites: ', uniqueN(v4_2year_complete$SITE_ID), '\n')
cat('  Year range: ', min(v4_2year_complete$YEAR, na.rm=TRUE), '-', max(v4_2year_complete$YEAR, na.rm=TRUE), '\n\n')

cat('Rolling 3-year window (current + lag1 + lag2):\n')
cat('  Rows: ', nrow(v4_3year_complete), '\n')
cat('  Sites: ', uniqueN(v4_3year_complete$SITE_ID), '\n')
cat('  Year range: ', min(v4_3year_complete$YEAR, na.rm=TRUE), '-', max(v4_3year_complete$YEAR, na.rm=TRUE), '\n\n')

# Sites by rolling window type
cat('Sites retained by window type:\n')
sites_base <- sort(unique(v4_base$SITE_ID))
sites_2y <- sort(unique(v4_2year_complete$SITE_ID))
sites_3y <- sort(unique(v4_3year_complete$SITE_ID))

cat('  In base only: ', length(setdiff(sites_base, sites_2y)), '\n')
cat('  In 2-year only: ', length(setdiff(sites_2y, sites_3y)), '\n')
cat('  In all (2-year + 3-year): ', length(intersect(sites_2y, sites_3y)), '\n\n')

cat('✅ v4 DATASETS COMPLETE!\n')
cat('Output directory: ', out_dir, '\n')

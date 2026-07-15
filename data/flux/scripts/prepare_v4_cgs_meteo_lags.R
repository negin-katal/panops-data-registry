#!/usr/bin/env Rscript
# Create meteorological lags based on CENTER OF GROWING SEASON
# Instead of calendar year, use growing season window

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('🌱 Creating Meteorological Lags Based on Growing Season\n')
cat('=======================================================\n\n')

# =========================================================
# 1) Load data
# =========================================================

cat('Loading data...\n')
v4_complete <- fread('derived_tables/outputs_afterEGU_results/V4_combined/EFP_meteo_traits_mortality_v4_rolling3year_complete.csv')
meteo_monthly <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_MONTHLY_METEO_corrected.csv')
cgs_data <- fread('derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv')

# Fix column name: 'year' -> 'YEAR'
setnames(cgs_data, 'year', 'YEAR')

cat('  v4 complete: ', nrow(v4_complete), ' rows\n')
cat('  Monthly meteo: ', nrow(meteo_monthly), ' rows\n')
cat('  CGS data: ', nrow(cgs_data), ' rows\n\n')

# =========================================================
# 2) Aggregate meteo to yearly (by CGS month window)
# =========================================================

cat('Creating CGS-based meteorological aggregations...\n')

meteo_cols <- c('TA_mean', 'TA_p05', 'TA_p95', 'VPD_mean', 'VPD_p05', 'VPD_p95',
                'SW_IN_mean', 'SW_IN_p05', 'SW_IN_p95', 'P_sum', 'P_mean')

# For each site-year, get CGS month and aggregate around it
meteo_cgs <- merge(meteo_monthly, cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)],
                   by = c('SITE_ID', 'YEAR'), all.x = TRUE)

# Convert CGS day-of-year to month
meteo_cgs[, CGS_month := ceiling(CGS_weighted_doy / (365.25/12))]
meteo_cgs[, CGS_month := pmin(pmax(CGS_month, 1L), 12L)]  # Clamp to 1-12

# Aggregate from growing season center -6 to +6 months (12-month window)
# This captures meteorology during and around the growing season
meteo_cgs[, is_in_gs_window := {
  month_diff <- abs(MONTH - CGS_month)
  # Account for year wrap-around
  month_diff <- pmin(month_diff, 12 - month_diff)
  month_diff <= 6
}]

meteo_yearly_cgs <- meteo_cgs[is_in_gs_window == TRUE,
  lapply(.SD, function(x) {
    if (is.numeric(x)) mean(x, na.rm = TRUE) else x[1]
  }),
  .SDcols = c(meteo_cols, 'CGS_month'),
  by = .(SITE_ID, YEAR)
]

cat('  CGS-aggregated meteo: ', nrow(meteo_yearly_cgs), ' rows\n\n')

# =========================================================
# 3) Create lag1 and lag2 (previous growing seasons)
# =========================================================

cat('Creating lag1 and lag2 from previous growing seasons...\n')

# Sort and create lags
meteo_yearly_cgs <- meteo_yearly_cgs[order(SITE_ID, YEAR)]

for (col in meteo_cols) {
  new_col_1 <- paste0(col, '_lag1_cgs')
  new_col_2 <- paste0(col, '_lag2_cgs')

  meteo_yearly_cgs[, (new_col_1) := shift(get(col), 1, NA, 'lag'), by = SITE_ID]
  meteo_yearly_cgs[, (new_col_2) := shift(get(col), 2, NA, 'lag'), by = SITE_ID]
}

cat('  Added lag1_cgs (', length(meteo_cols), ' vars)\n')
cat('  Added lag2_cgs (', length(meteo_cols), ' vars)\n\n')

# =========================================================
# 4) Merge with v4 complete (replace old lags)
# =========================================================

cat('Merging CGS-based lags with v4 complete...\n')

# Remove old lagged meteo columns from v4_complete
old_lag_cols <- grep('_lag1|_lag2', names(v4_complete), value = TRUE)
old_lag_cols <- old_lag_cols[!grepl('_lag1_cgs|_lag2_cgs', old_lag_cols)]

if (length(old_lag_cols) > 0) {
  v4_complete[, (old_lag_cols) := NULL]
}

# Select only CGS-based lags to add
cgs_lag_cols <- grep('_lag1_cgs|_lag2_cgs', names(meteo_yearly_cgs), value = TRUE)
meteo_to_merge <- meteo_yearly_cgs[, c('SITE_ID', 'YEAR', cgs_lag_cols), with = FALSE]

# Merge
v4_cgs <- merge(
  v4_complete,
  meteo_to_merge,
  by = c('SITE_ID', 'YEAR'),
  all.x = TRUE
)

cat('  Final dataset: ', nrow(v4_cgs), ' rows x', ncol(v4_cgs), 'cols\n\n')

# =========================================================
# 5) Save
# =========================================================

cat('Saving v4 with CGS-based meteorological lags...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V4_combined'
out_file <- file.path(out_dir, 'EFP_meteo_traits_mortality_v4_rolling3year_CGS_lags.csv')
fwrite(v4_cgs, out_file)

cat('✅ Saved to: ', out_file, '\n\n')

# =========================================================
# 6) Summary
# =========================================================

cat('📊 V4 WITH CGS-BASED METEOROLOGICAL LAGS:\n')
cat('==========================================\n\n')

cat('Dataset size:\n')
cat('  Rows: ', nrow(v4_cgs), ' site-years\n')
cat('  Sites: ', uniqueN(v4_cgs$SITE_ID), '\n')
cat('  Years: ', min(v4_cgs$YEAR, na.rm=TRUE), '-', max(v4_cgs$YEAR, na.rm=TRUE), '\n')
cat('  Columns: ', ncol(v4_cgs), '\n\n')

cat('Meteorology variables:\n')
cat('  Current year (CGS-centered): ', length(meteo_cols), '\n')
cat('  Lag1 (previous season, CGS-centered): ', length(meteo_cols), '\n')
cat('  Lag2 (2 seasons ago, CGS-centered): ', length(meteo_cols), '\n')
cat('  Total: ', length(meteo_cols)*3, ' meteorology variables\n\n')

cat('Complete cases: ', nrow(v4_cgs[complete.cases(v4_cgs)]), ' / ', nrow(v4_cgs),
    ' (', round(100*nrow(v4_cgs[complete.cases(v4_cgs)])/nrow(v4_cgs), 1), '%)\n\n')

cat('✅ READY FOR RF MODELING WITH CGS-BASED METEOROLOGY!\n')

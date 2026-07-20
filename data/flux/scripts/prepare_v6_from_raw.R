#!/usr/bin/env Rscript
# Comprehensive data preparation from raw sources:
# 1. Yearly EFPs (calculate anomalies)
# 2. Monthly meteo (aggregate by CGS, create lags)
# 3. Mortality data (from v3)
# 4. Create rolling windows with continuous years
# 5. Lag1 and Lag2

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('V6 DATASET PREPARATION - FROM RAW DATA\n')
cat('====================================================================\n\n')

# =========================================================
# PHASE 1: Load and combine yearly EFPs
# =========================================================

cat('PHASE 1: Loading yearly EFPs from all sites...\n')

efp_dir <- 'fluxnet_2017_2025_V02/EFP_outputs_corrected/yearly_EFP_per_site'
efp_files <- list.files(efp_dir, pattern='_yearly_EFP.csv$', full.names=TRUE)

cat('  Found', length(efp_files), 'EFP files\n')

# Load and combine all EFP files
efp_list <- lapply(efp_files, fread)
efp_combined <- rbindlist(efp_list, fill=TRUE)

cat('  Combined EFP data:', nrow(efp_combined), 'rows x', ncol(efp_combined), 'cols\n')
cat('  Sites:', uniqueN(efp_combined$SITE_ID), '\n')
cat('  Years:', min(efp_combined$YEAR, na.rm=TRUE), '-', max(efp_combined$YEAR, na.rm=TRUE), '\n\n')

# =========================================================
# PHASE 2: Calculate EFP anomalies (z-scores per site)
# =========================================================

cat('PHASE 2: Calculating EFP anomalies...\n')

# EFP variables
efp_vars <- c('uWUE', 'WUE', 'ETmax', 'GPPsat', 'NEPmax')

# Calculate z-scores per site
efp_combined <- efp_combined[order(SITE_ID, YEAR)]

for (var in efp_vars) {
  anom_name <- paste0(var, '_anom')
  efp_combined[, (anom_name) := {
    vals <- get(var)
    mean_val <- mean(vals, na.rm=TRUE)
    sd_val <- sd(vals, na.rm=TRUE)
    if (sd_val == 0 || is.na(sd_val)) {
      rep(NA, length(vals))
    } else {
      (vals - mean_val) / sd_val
    }
  }, by=SITE_ID]
}

cat('  Added anomalies for', length(efp_vars), 'EFPs\n')
cat('  Dataset now:', ncol(efp_combined), 'columns\n\n')

# =========================================================
# PHASE 3: Load and aggregate monthly meteo (CGS-based)
# =========================================================

cat('PHASE 3: Processing meteorology with CGS aggregation...\n')

meteo_wide <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/MONTHLY_METEO_WIDE.csv')
cgs_data <- fread('derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv')

# Fix column name
setnames(cgs_data, 'year', 'YEAR')

cat('  Monthly meteo:', nrow(meteo_wide), 'rows\n')
cat('  CGS data:', nrow(cgs_data), 'rows\n')

# Convert wide to long
meteo_long <- melt(meteo_wide, id.vars=c('SITE_ID', 'YEAR'),
                   variable.name='var_month', value.name='value')

# Extract variable type and month
meteo_long[, c('var_type', 'month_str') := tstrsplit(var_month, '_M', fixed=TRUE)]
meteo_long[, month := as.integer(month_str)]
meteo_long[, c('var_month', 'month_str') := NULL]

# Merge with CGS
meteo_cgs <- merge(meteo_long, cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)],
                   by=c('SITE_ID', 'YEAR'), all.x=TRUE)

# Calculate CGS month
meteo_cgs[, cgs_month := ceiling(CGS_weighted_doy / (365.25/12))]
meteo_cgs[, cgs_month := pmin(pmax(cgs_month, 1L), 12L)]

# Aggregate within ±6 months of CGS (12-month window)
meteo_cgs[, month_diff := abs(month - cgs_month)]
meteo_cgs[, month_diff := pmin(month_diff, 12 - month_diff)]
meteo_cgs[, in_gs_window := month_diff <= 6]

meteo_yearly <- meteo_cgs[in_gs_window == TRUE,
  .(value_agg = mean(value, na.rm=TRUE)),
  by=.(SITE_ID, YEAR, var_type)
]

# Pivot to wide
meteo_wide_final <- dcast(meteo_yearly, SITE_ID + YEAR ~ var_type,
                          value.var='value_agg')

cat('  CGS-aggregated meteo:', nrow(meteo_wide_final), 'rows\n')
cat('  Meteo variables:', ncol(meteo_wide_final) - 2, '\n\n')

# =========================================================
# PHASE 4: Merge EFP + Meteo
# =========================================================

cat('PHASE 4: Merging EFPs with meteorology...\n')

data_combined <- merge(efp_combined, meteo_wide_final,
                       by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  Combined dataset:', nrow(data_combined), 'rows x', ncol(data_combined), 'cols\n\n')

# =========================================================
# PHASE 5: Add mortality data (from v3)
# =========================================================

cat('PHASE 5: Adding mortality data...\n')

v3 <- fread('derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv')

# Extract mortality and tree cover columns
mort_cols <- grep('^(mortality|deadwood|forest_loss|new_mortality)', names(v3), value=TRUE)
mort_cols <- setdiff(mort_cols, grep('_lag', mort_cols, value=TRUE))

tree_cover_cols <- grep('forest_mean_pct', names(v3), value=TRUE)

v3_dist <- v3[, c('SITE_ID', 'YEAR', mort_cols, tree_cover_cols), with=FALSE]

data_with_dist <- merge(data_combined, v3_dist, by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  Mortality variables:', length(mort_cols), '\n')
cat('  Tree cover variables:', length(tree_cover_cols), '\n')
cat('  Combined dataset:', nrow(data_with_dist), 'rows x', ncol(data_with_dist), 'cols\n\n')

# =========================================================
# PHASE 6: Create rolling windows (continuous years only)
# =========================================================

cat('PHASE 6: Creating rolling windows with continuous years...\n')

# Sort by site and year
data_with_dist <- data_with_dist[order(SITE_ID, YEAR)]

# Create rolling window flags
data_with_dist[, has_lag1 := shift(YEAR, 1) == (YEAR - 1), by=SITE_ID]
data_with_dist[, has_lag2 := shift(YEAR, 2) == (YEAR - 2), by=SITE_ID]

# Mark rows that can have lags
data_with_dist[, can_use_lag1 := !is.na(has_lag1) & has_lag1 == TRUE]
data_with_dist[, can_use_lag2 := !is.na(has_lag2) & has_lag2 == TRUE]

cat('  Rows with lag1 data:', sum(data_with_dist$can_use_lag1, na.rm=TRUE), '\n')
cat('  Rows with lag2 data:', sum(data_with_dist$can_use_lag2, na.rm=TRUE), '\n\n')

# =========================================================
# PHASE 7: Create lagged variables
# =========================================================

cat('PHASE 7: Creating lagged variables...\n')

# Lag1 for EFPs (raw and anomaly)
for (var in efp_vars) {
  lag1_name <- paste0(var, '_lag1')
  lag1_anom_name <- paste0(var, '_anom_lag1')

  data_with_dist[, (lag1_name) := shift(get(var), 1, NA, 'lag'), by=SITE_ID]
  data_with_dist[, (lag1_anom_name) := shift(get(paste0(var, '_anom')), 1, NA, 'lag'), by=SITE_ID]
}

# Lag2 for EFPs
for (var in efp_vars) {
  lag2_name <- paste0(var, '_lag2')
  lag2_anom_name <- paste0(var, '_anom_lag2')

  data_with_dist[, (lag2_name) := shift(get(var), 2, NA, 'lag'), by=SITE_ID]
  data_with_dist[, (lag2_anom_name) := shift(get(paste0(var, '_anom')), 2, NA, 'lag'), by=SITE_ID]
}

# Lag1 and Lag2 for mortality
for (col in mort_cols) {
  lag1_name <- paste0(col, '_lag1')
  lag2_name <- paste0(col, '_lag2')

  data_with_dist[, (lag1_name) := shift(get(col), 1, NA, 'lag'), by=SITE_ID]
  data_with_dist[, (lag2_name) := shift(get(col), 2, NA, 'lag'), by=SITE_ID]
}

# Lag1 and Lag2 for meteo (if needed for separate models)
meteo_vars <- setdiff(names(meteo_wide_final), c('SITE_ID', 'YEAR'))
for (col in meteo_vars) {
  lag1_name <- paste0(col, '_lag1')
  lag2_name <- paste0(col, '_lag2')

  data_with_dist[, (lag1_name) := shift(get(col), 1, NA, 'lag'), by=SITE_ID]
  data_with_dist[, (lag2_name) := shift(get(col), 2, NA, 'lag'), by=SITE_ID]
}

cat('  Added lag1 and lag2 for all EFPs, mortality, and meteorology\n')
cat('  Final dataset:', nrow(data_with_dist), 'rows x', ncol(data_with_dist), 'cols\n\n')

# =========================================================
# PHASE 8: Save output
# =========================================================

cat('PHASE 8: Saving v6 dataset...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V6_rolling_lags'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

out_file <- file.path(out_dir, 'EFP_meteo_mortality_v6_rolling_lags.csv')
fwrite(data_with_dist, out_file)

cat('  Saved to:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n\n')

# =========================================================
# SUMMARY
# =========================================================

cat('====================================================================\n')
cat('V6 ROLLING LAGS DATASET SUMMARY\n')
cat('====================================================================\n\n')

cat('Dataset dimensions:\n')
cat('  Total rows:', nrow(data_with_dist), '\n')
cat('  Columns:', ncol(data_with_dist), '\n')
cat('  Sites:', uniqueN(data_with_dist$SITE_ID), '\n')
cat('  Years:', min(data_with_dist$YEAR), '-', max(data_with_dist$YEAR), '\n\n')

cat('Continuous year data:\n')
cat('  Rows with lag1:', sum(data_with_dist$can_use_lag1, na.rm=TRUE), '\n')
cat('  Rows with lag2:', sum(data_with_dist$can_use_lag2, na.rm=TRUE), '\n\n')

cat('Variable groups:\n')
efp_count <- length(efp_vars)
cat('  EFPs (current):', efp_count, '\n')
cat('  EFP anomalies (current):', efp_count, '\n')
cat('  EFP lag1 (raw):', efp_count, '\n')
cat('  EFP lag1 (anomaly):', efp_count, '\n')
cat('  EFP lag2 (raw):', efp_count, '\n')
cat('  EFP lag2 (anomaly):', efp_count, '\n')
cat('  Meteorology (current):', length(meteo_vars), '\n')
cat('  Meteorology lag1:', length(meteo_vars), '\n')
cat('  Meteorology lag2:', length(meteo_vars), '\n')
cat('  Mortality (current):', length(mort_cols), '\n')
cat('  Mortality lag1:', length(mort_cols), '\n')
cat('  Mortality lag2:', length(mort_cols), '\n')
cat('  Tree cover:', length(tree_cover_cols), '\n')
cat('  Meta/status:', 3, ' (YEAR, status, nyears)\n\n')

cat('Data completeness:\n')
complete_rows <- sum(complete.cases(data_with_dist))
cat('  Complete rows (all vars):', complete_rows, '/', nrow(data_with_dist),
    '(', round(100*complete_rows/nrow(data_with_dist), 1), '%)\n\n')

cat('✅ V6 ROLLING LAGS DATASET READY!\n')
cat('====================================================================\n\n')


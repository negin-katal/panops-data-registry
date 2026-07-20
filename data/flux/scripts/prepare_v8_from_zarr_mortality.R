#!/usr/bin/env Rscript
# Complete pipeline using mortality extracted from zarr files
# No dependency on v3!

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('V8 PIPELINE - USING ZARR MORTALITY (NO V3 DEPENDENCY)\n')
cat('====================================================================\n\n')

# =========================================================
# PHASE 1: Load yearly EFPs
# =========================================================

cat('PHASE 1: Loading yearly EFPs...\n')

efp_dir <- 'fluxnet_2017_2025_V02/EFP_outputs_corrected/yearly_EFP_per_site'
efp_files <- list.files(efp_dir, pattern='_yearly_EFP.csv$', full.names=TRUE)

efp_list <- lapply(efp_files, fread)
efp_combined <- rbindlist(efp_list, fill=TRUE)

n_sites_step1 <- uniqueN(efp_combined$SITE_ID)
n_rows_step1 <- nrow(efp_combined)

cat('  Sites:', n_sites_step1, '\n')
cat('  Site-years:', n_rows_step1, '\n')
cat('  Year range:', min(efp_combined$YEAR), '-', max(efp_combined$YEAR), '\n\n')

# =========================================================
# PHASE 2: Calculate EFP anomalies
# =========================================================

cat('PHASE 2: Calculating EFP anomalies...\n')

efp_vars <- c('uWUE', 'WUE', 'ETmax', 'GPPsat', 'NEPmax')

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

cat('  Added anomalies for', length(efp_vars), 'EFPs\n\n')

# =========================================================
# PHASE 3: Add meteorology (CGS-based)
# =========================================================

cat('PHASE 3: Adding meteorology (CGS-centered)...\n')

meteo_wide <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/MONTHLY_METEO_WIDE.csv')
cgs_data <- fread('derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv')

setnames(cgs_data, 'year', 'YEAR')

# Convert wide to long
meteo_long <- melt(meteo_wide, id.vars=c('SITE_ID', 'YEAR'),
                   variable.name='var_month', value.name='value')

meteo_long[, c('var_type', 'month_str') := tstrsplit(var_month, '_M', fixed=TRUE)]
meteo_long[, month := as.integer(month_str)]
meteo_long[, c('var_month', 'month_str') := NULL]

# Merge with CGS and aggregate
meteo_cgs <- merge(meteo_long, cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)],
                   by=c('SITE_ID', 'YEAR'), all.x=TRUE)

meteo_cgs[, cgs_month := ceiling(CGS_weighted_doy / (365.25/12))]
meteo_cgs[, cgs_month := pmin(pmax(cgs_month, 1L), 12L)]

meteo_cgs[, month_diff := abs(month - cgs_month)]
meteo_cgs[, month_diff := pmin(month_diff, 12 - month_diff)]
meteo_cgs[, in_gs_window := month_diff <= 6]

meteo_yearly <- meteo_cgs[in_gs_window == TRUE,
  .(value_agg = mean(value, na.rm=TRUE)),
  by=.(SITE_ID, YEAR, var_type)
]

meteo_wide_final <- dcast(meteo_yearly, SITE_ID + YEAR ~ var_type,
                          value.var='value_agg')

cat('  CGS-aggregated meteo:', nrow(meteo_wide_final), 'rows\n')

# Merge with EFP
data_combined <- merge(efp_combined, meteo_wide_final,
                       by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  After adding meteo:', nrow(data_combined), 'rows\n\n')

# =========================================================
# PHASE 4: Add mortality from zarr
# =========================================================

cat('PHASE 4: Adding mortality from zarr files...\n')

mortality <- fread('derived_tables/outputs_afterEGU_results/mortality_from_zarr.csv')

cat('  Mortality data:', nrow(mortality), 'rows from', uniqueN(mortality$SITE_ID), 'sites\n')

# Keep only 500m buffer mortality for main model
mort_cols_500m <- grep('_500m$', names(mortality), value=TRUE)
mortality_500m <- mortality[, c('SITE_ID', 'YEAR', mort_cols_500m), with=FALSE]

data_with_mort <- merge(data_combined, mortality_500m,
                        by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  After adding mortality:', nrow(data_with_mort), 'rows\n')
cat('  Unique sites now:', uniqueN(data_with_mort$SITE_ID), '\n\n')

# =========================================================
# PHASE 5: Tree cover filter (>=30%)
# =========================================================

cat('PHASE 5: Applying tree cover filter (>=30%)...\n')

tree_cover_site <- data_with_mort[, .(mean_tree_cover = mean(forest_mean_pct_500m, na.rm=TRUE)),
                                   by=SITE_ID]

sites_high_cover <- tree_cover_site[mean_tree_cover >= 30, SITE_ID]
n_sites_high_cover <- length(sites_high_cover)

cat('  Sites with >=30% tree cover:', n_sites_high_cover, '\n')

data_filtered <- data_with_mort[SITE_ID %in% sites_high_cover]

cat('  After tree cover filter:', nrow(data_filtered), 'rows\n')
cat('  Unique sites:', uniqueN(data_filtered$SITE_ID), '\n\n')

# =========================================================
# PHASE 6: Create rolling windows with lags
# =========================================================

cat('PHASE 6: Creating rolling windows...\n')

data_filtered <- data_filtered[order(SITE_ID, YEAR)]

# Mark rows with lag1 and lag2 data
data_filtered[, has_lag1 := shift(YEAR, 1) == (YEAR - 1), by=SITE_ID]
data_filtered[, has_lag2 := shift(YEAR, 2) == (YEAR - 2), by=SITE_ID]

data_filtered[, can_use_lag1 := !is.na(has_lag1) & has_lag1 == TRUE]
data_filtered[, can_use_lag2 := !is.na(has_lag2) & has_lag2 == TRUE]

cat('  Rows with lag1 data:', sum(data_filtered$can_use_lag1, na.rm=TRUE), '\n')
cat('  Rows with lag2 data:', sum(data_filtered$can_use_lag2, na.rm=TRUE), '\n')

# Create lagged variables for EFPs and mortality
for (var in efp_vars) {
  lag1_name <- paste0(var, '_lag1')
  lag1_anom_name <- paste0(var, '_anom_lag1')
  lag2_name <- paste0(var, '_lag2')
  lag2_anom_name <- paste0(var, '_anom_lag2')

  data_filtered[, (lag1_name) := shift(get(var), 1, NA, 'lag'), by=SITE_ID]
  data_filtered[, (lag1_anom_name) := shift(get(paste0(var, '_anom')), 1, NA, 'lag'), by=SITE_ID]
  data_filtered[, (lag2_name) := shift(get(var), 2, NA, 'lag'), by=SITE_ID]
  data_filtered[, (lag2_anom_name) := shift(get(paste0(var, '_anom')), 2, NA, 'lag'), by=SITE_ID]
}

# Lag mortality
mort_cols <- grep('forest_mean|deadwood_mean|mortality_intensity', names(data_filtered), value=TRUE)
for (col in mort_cols) {
  lag1_name <- paste0(col, '_lag1')
  lag2_name <- paste0(col, '_lag2')
  data_filtered[, (lag1_name) := shift(get(col), 1, NA, 'lag'), by=SITE_ID]
  data_filtered[, (lag2_name) := shift(get(col), 2, NA, 'lag'), by=SITE_ID]
}

cat('  Added lag1 and lag2 for all variables\n')
cat('  Final dataset:', nrow(data_filtered), 'rows x', ncol(data_filtered), 'cols\n\n')

# =========================================================
# PHASE 7: Save
# =========================================================

cat('PHASE 7: Saving v8 dataset...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V8_zarr_mortality'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

out_file <- file.path(out_dir, 'EFP_meteo_mortality_v8_with_lags.csv')
fwrite(data_filtered, out_file)

cat('  Saved to:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n\n')

# =========================================================
# SUMMARY
# =========================================================

cat('====================================================================\n')
cat('V8 SUMMARY (ZARR MORTALITY PIPELINE)\n')
cat('====================================================================\n\n')

cat('Dataset dimensions:\n')
cat('  Total rows:', nrow(data_filtered), '\n')
cat('  Columns:', ncol(data_filtered), '\n')
cat('  Sites:', uniqueN(data_filtered$SITE_ID), '\n')
cat('  Years:', min(data_filtered$YEAR), '-', max(data_filtered$YEAR), '\n\n')

cat('Site progression:\n')
cat('  1. Initial EFPs: ', n_sites_step1, ' sites\n')
cat('  2. With zarr mortality: ', uniqueN(data_with_mort$SITE_ID), ' sites\n')
cat('  3. After tree cover >=30%: ', n_sites_high_cover, ' sites\n')
cat('  4. Final: ', uniqueN(data_filtered$SITE_ID), ' sites\n\n')

cat('Continuous year data:\n')
cat('  Rows with lag1:', sum(data_filtered$can_use_lag1, na.rm=TRUE), '\n')
cat('  Rows with lag2:', sum(data_filtered$can_use_lag2, na.rm=TRUE), '\n\n')

cat('✅ V8 READY FOR BENCHMARKING!\n')
cat('====================================================================\n\n')


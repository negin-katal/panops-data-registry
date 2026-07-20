#!/usr/bin/env Rscript
# V10: Rebuild benchmarks with GS-to-GS meteorological lags
# Same structure as V9, but with corrected meteo aggregation

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('V10 PIPELINE - REBUILT WITH GS-TO-GS METEOROLOGICAL LAGS\n')
cat('====================================================================\n\n')

# =========================================================
# PHASE 1: Load base data (EFPs + mortality) and add traits
# =========================================================

cat('PHASE 1: Loading base data...\n')

# Load v8 base (has EFPs, mortality)
v8_path <- 'derived_tables/outputs_afterEGU_results/V8_zarr_mortality/EFP_meteo_mortality_v8_with_lags.csv'
data_base <- fread(v8_path)

cat('  Loaded v8 base:', nrow(data_base), 'rows\n')

# Add plant traits from v3
cat('  Adding plant traits from v3...\n')
v3 <- fread('derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv')
trait_cols <- grep('^(P12|P50|P88|gsmax|rdmax)_mean$', names(v3), value=TRUE)

if (length(trait_cols) > 0) {
  v3_traits <- v3[, c('SITE_ID', trait_cols), with=FALSE]
  v3_traits_static <- v3_traits[!duplicated(SITE_ID)]
  data_base <- merge(data_base, v3_traits_static, by='SITE_ID', all.x=TRUE)
  cat('    Added', length(trait_cols), 'trait variables\n')
}

# Remove the old meteo columns (TA, VPD, P, SW_IN without lags, and the old lag versions)
old_meteo_cols <- grep('^(TA|VPD|P|SW_IN)_', names(data_base), value=TRUE)
data_base <- data_base[, .SD, .SDcols = !names(data_base) %in% old_meteo_cols]

cat('  Removed old meteo columns, remaining:', nrow(data_base), 'rows\n')

# =========================================================
# PHASE 2: Load corrected GS-to-GS meteo
# =========================================================

cat('PHASE 2: Loading GS-to-GS meteo lags...\n')

lag0_meteo <- fread('derived_tables/outputs_afterEGU_results/GS_to_GS_meteo_lags/meteo_lag0_gs_centered.csv')
lag1_meteo <- fread('derived_tables/outputs_afterEGU_results/GS_to_GS_meteo_lags/meteo_lag1_gs_to_gs.csv')
lag2_meteo <- fread('derived_tables/outputs_afterEGU_results/GS_to_GS_meteo_lags/meteo_lag2_gs_to_gs.csv')

cat('  Lag0 (current):', nrow(lag0_meteo), 'rows\n')
cat('  Lag1 (GS-to-GS):', nrow(lag1_meteo), 'rows\n')
cat('  Lag2 (GS-to-GS):', nrow(lag2_meteo), 'rows\n\n')

# =========================================================
# PHASE 3: Add meteo to base data
# =========================================================

cat('PHASE 3: Adding corrected meteo to base data...\n')

# Merge lag0
data_v10 <- merge(data_base, lag0_meteo,
                 by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  After lag0 meteo:', nrow(data_v10), 'rows\n')

# Merge lag1
data_v10 <- merge(data_v10, lag1_meteo,
                 by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  After lag1 meteo:', nrow(data_v10), 'rows\n')

# Merge lag2
data_v10 <- merge(data_v10, lag2_meteo,
                 by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  After lag2 meteo:', nrow(data_v10), 'rows\n')
cat('  Columns now:', ncol(data_v10), '\n\n')

# =========================================================
# PHASE 4: Create harmonized benchmarks
# =========================================================

cat('PHASE 4: Creating harmonized benchmarks...\n\n')

# Identify rows with complete data for each benchmark
# B1: need lag0 and lag1 meteo
# B2: need lag0, lag1, and lag2 meteo

# Get complete cases
data_v10[, has_lag0_meteo := !is.na(data_v10[[grep('^TA_mean$', names(data_v10), value=TRUE)[1]]])]
data_v10[, has_lag1_meteo := !is.na(data_v10[[grep('^TA_mean_lag1$', names(data_v10), value=TRUE)[1]]])]
data_v10[, has_lag2_meteo := !is.na(data_v10[[grep('^TA_mean_lag2$', names(data_v10), value=TRUE)[1]]])]

# Response variable completeness
response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE')
for (var in response_vars) {
  col_name <- paste0('has_', var)
  data_v10[, (col_name) := !is.na(get(var))]
}
data_v10[, has_response := Reduce(`&`, mget(paste0('has_', response_vars)))]

# Mortality/traits completeness
mort_cols_check <- grep('forest_mean_pct|deadwood_mean_pct|mortality_intensity', names(data_v10), value=TRUE)
mort_lag_cols_check <- grep('_lag1$|_lag2$', mort_cols_check, value=TRUE)
trait_cols_check <- grep('^(P12|P50|P88|gsmax|rdmax)_mean', names(data_v10), value=TRUE)

if (length(mort_cols_check) > 0) {
  data_v10[, has_mort := rowSums(is.na(as.matrix(data_v10[, mort_cols_check, with=FALSE]))) < length(mort_cols_check)]
} else {
  data_v10[, has_mort := TRUE]
}

if (length(trait_cols_check) > 0) {
  data_v10[, has_traits := rowSums(is.na(as.matrix(data_v10[, trait_cols_check, with=FALSE]))) == 0]
} else {
  data_v10[, has_traits := TRUE]
}

# B1 benchmark: lag1 only
b1_rows <- data_v10[has_response == TRUE &
                   has_lag0_meteo == TRUE &
                   has_lag1_meteo == TRUE &
                   has_mort == TRUE &
                   has_traits == TRUE]

cat('Benchmark 1 (Lag1 only):\n')
cat('  Candidate rows:', sum(data_v10$has_response & data_v10$has_lag0_meteo & data_v10$has_lag1_meteo), '\n')
cat('  With mortality & traits:', nrow(b1_rows), '\n')
cat('  Unique sites:', uniqueN(b1_rows$SITE_ID), '\n')
cat('  Year range:', min(b1_rows$YEAR), '-', max(b1_rows$YEAR), '\n\n')

# B2 benchmark: lag1+lag2
b2_rows <- data_v10[has_response == TRUE &
                   has_lag0_meteo == TRUE &
                   has_lag1_meteo == TRUE &
                   has_lag2_meteo == TRUE &
                   has_mort == TRUE &
                   has_traits == TRUE]

cat('Benchmark 2 (Lag1+Lag2):\n')
cat('  Candidate rows:', sum(data_v10$has_response & data_v10$has_lag0_meteo &
                            data_v10$has_lag1_meteo & data_v10$has_lag2_meteo), '\n')
cat('  With mortality & traits:', nrow(b2_rows), '\n')
cat('  Unique sites:', uniqueN(b2_rows$SITE_ID), '\n')
cat('  Year range:', min(b2_rows$YEAR), '-', max(b2_rows$YEAR), '\n\n')

# Harmonize: use same sites/years across both benchmarks
if (nrow(b1_rows) > 0 && nrow(b2_rows) > 0) {
  b1_sy <- b1_rows[, .(SITE_ID, YEAR)]
  b2_sy <- b2_rows[, .(SITE_ID, YEAR)]

  # Find common site-years using semi-join approach
  setkey(b1_sy, SITE_ID, YEAR)
  setkey(b2_sy, SITE_ID, YEAR)

  common_site_years <- b1_sy[b2_sy, nomatch=0, .SD]

  cat('Harmonizing benchmarks (using common site-years)...\n')
  cat('  Common site-years:', nrow(common_site_years), '\n')

  if (nrow(common_site_years) > 0) {
    b1_final <- merge(b1_rows, common_site_years, by=c('SITE_ID', 'YEAR'))
    b2_final <- merge(b2_rows, common_site_years, by=c('SITE_ID', 'YEAR'))

    cat('  B1 final:', nrow(b1_final), 'rows,', uniqueN(b1_final$SITE_ID), 'sites\n')
    cat('  B2 final:', nrow(b2_final), 'rows,', uniqueN(b2_final$SITE_ID), 'sites\n')
  } else {
    cat('  WARNING: No common site-years found!\n')
    b1_final <- b1_rows
    b2_final <- b2_rows
  }
} else {
  cat('  Not enough rows for both benchmarks\n')
  b1_final <- b1_rows
  b2_final <- b2_rows
}

# =========================================================
# PHASE 5: Save benchmarks
# =========================================================

cat('PHASE 5: Saving benchmarks...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V10_gs_meteo_benchmarks'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

fwrite(b1_final, file.path(out_dir, 'benchmark_B1_lag1only_gs_meteo.csv'))
fwrite(b2_final, file.path(out_dir, 'benchmark_B2_lag1and2_gs_meteo.csv'))

cat('  Saved:', file.path(out_dir, 'benchmark_B1_lag1only_gs_meteo.csv'), '\n')
cat('  Saved:', file.path(out_dir, 'benchmark_B2_lag1and2_gs_meteo.csv'), '\n\n')

# =========================================================
# SUMMARY
# =========================================================

cat('====================================================================\n')
cat('V10 SUMMARY - GS-TO-GS METEOROLOGICAL LAGS\n')
cat('====================================================================\n\n')

cat('Benchmark 1 (Lag1 only):\n')
cat('  Rows:', nrow(b1_final), '\n')
cat('  Sites:', uniqueN(b1_final$SITE_ID), '\n')
cat('  Years:', min(b1_final$YEAR), '-', max(b1_final$YEAR), '\n\n')

cat('Benchmark 2 (Lag1+Lag2):\n')
cat('  Rows:', nrow(b2_final), '\n')
cat('  Sites:', uniqueN(b2_final$SITE_ID), '\n')
cat('  Years:', min(b2_final$YEAR), '-', max(b2_final$YEAR), '\n\n')

cat('✅ V10 BENCHMARKS READY FOR RF!\n')
cat('====================================================================\n\n')

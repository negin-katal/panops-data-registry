#!/usr/bin/env Rscript
# Create two identical benchmark datasets with different lag structures
# Benchmark 1: lag1 only (meteo + mortality)
# Benchmark 2: lag1 + lag2 (meteo + mortality)
# Both use SAME sites and years for fair comparison

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('📊 Creating v4 RF Benchmarks with Lagged Mortality\n')
cat('===================================================\n\n')

# =========================================================
# 1) Load v3 for full mortality data (to create lags)
# =========================================================

cat('Loading data...\n')
v3 <- fread('derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv')
v4_cgs <- fread('derived_tables/outputs_afterEGU_results/V4_combined/EFP_meteo_traits_mortality_v4_rolling3year_CGS_lags.csv')

cat('  v4 CGS: ', nrow(v4_cgs), ' rows\n')
cat('  v3 full: ', nrow(v3), ' rows\n\n')

# =========================================================
# 2) Extract and lag mortality from v3
# =========================================================

cat('Creating lagged mortality variables...\n')

# Get mortality columns
mort_cols <- grep('^(mortality|deadwood|forest_loss|new_mortality)', names(v3), value = TRUE)
cat('  Mortality variables: ', length(mort_cols), '\n')

# Extract mortality and create lags
v3_mortality <- v3[, c('SITE_ID', 'YEAR', mort_cols), with = FALSE]
v3_mortality <- v3_mortality[order(SITE_ID, YEAR)]

# Create lag1 and lag2
for (col in mort_cols) {
  new_col_1 <- paste0(col, '_lag1')
  new_col_2 <- paste0(col, '_lag2')

  v3_mortality[, (new_col_1) := shift(get(col), 1, NA, 'lag'), by = SITE_ID]
  v3_mortality[, (new_col_2) := shift(get(col), 2, NA, 'lag'), by = SITE_ID]
}

cat('  Added lag1 (', length(mort_cols), ' vars)\n')
cat('  Added lag2 (', length(mort_cols), ' vars)\n\n')

# =========================================================
# 3) Merge with v4_cgs to add lagged mortality
# =========================================================

cat('Merging lagged mortality with v4 CGS...\n')

# Remove old mortality columns from v4_cgs (keep only current year)
old_mort_cols <- grep('^(mortality|deadwood|forest_loss|new_mortality)_lag',
                      names(v4_cgs), value = TRUE)
if (length(old_mort_cols) > 0) {
  v4_cgs[, (old_mort_cols) := NULL]
}

# Merge lag1 and lag2
mort_lags <- v3_mortality[, grep('_lag[12]$', names(v3_mortality), value = TRUE), with = FALSE]
mort_lags[, SITE_ID := v3_mortality$SITE_ID]
mort_lags[, YEAR := v3_mortality$YEAR]

v4_complete <- merge(
  v4_cgs,
  mort_lags,
  by = c('SITE_ID', 'YEAR'),
  all.x = TRUE
)

cat('  v4 complete (with mort lags): ', nrow(v4_complete), ' rows x', ncol(v4_complete), 'cols\n\n')

# =========================================================
# 4) Create Benchmark 1: lag1 only
# =========================================================

cat('Creating Benchmark 1: lag1 only (meteo + mortality)...\n')

v4_lag1 <- copy(v4_complete)

# Remove all lag2 columns
lag2_cols <- grep('_lag2', names(v4_lag1), value = TRUE)
if (length(lag2_cols) > 0) {
  v4_lag1[, (lag2_cols) := NULL]
}

# Remove rows with incomplete lag1 data
v4_lag1 <- v4_lag1[!is.na(rowSums(v4_lag1[, grep('_lag1', names(v4_lag1), value = TRUE), with = FALSE])), ]

cat('  Rows: ', nrow(v4_lag1), '\n')
cat('  Sites: ', uniqueN(v4_lag1$SITE_ID), '\n')
cat('  Years: ', min(v4_lag1$YEAR), '-', max(v4_lag1$YEAR), '\n')
cat('  Columns: ', ncol(v4_lag1), '\n\n')

# =========================================================
# 5) Create Benchmark 2: lag1 + lag2
# =========================================================

cat('Creating Benchmark 2: lag1 + lag2 (meteo + mortality)...\n')

v4_lag1and2 <- copy(v4_complete)

# Remove rows with incomplete lag1 or lag2 data
v4_lag1and2 <- v4_lag1and2[!is.na(rowSums(v4_lag1and2[, grep('_lag[12]', names(v4_lag1and2), value = TRUE), with = FALSE])), ]

cat('  Rows: ', nrow(v4_lag1and2), '\n')
cat('  Sites: ', uniqueN(v4_lag1and2$SITE_ID), '\n')
cat('  Years: ', min(v4_lag1and2$YEAR), '-', max(v4_lag1and2$YEAR), '\n')
cat('  Columns: ', ncol(v4_lag1and2), '\n\n')

# =========================================================
# 6) Harmonize: keep SAME sites and years in both
# =========================================================

cat('Harmonizing benchmarks to same sites/years...\n')

# Find common sites and years
common_sites <- intersect(unique(v4_lag1$SITE_ID), unique(v4_lag1and2$SITE_ID))
common_years <- intersect(unique(v4_lag1$YEAR), unique(v4_lag1and2$YEAR))

v4_lag1 <- v4_lag1[SITE_ID %in% common_sites & YEAR %in% common_years]
v4_lag1and2 <- v4_lag1and2[SITE_ID %in% common_sites & YEAR %in% common_years]

cat('  Common sites: ', uniqueN(v4_lag1$SITE_ID), '\n')
cat('  Common years: ', min(v4_lag1$YEAR), '-', max(v4_lag1$YEAR), '\n')
cat('  Lag1 only: ', nrow(v4_lag1), ' rows\n')
cat('  Lag1+2: ', nrow(v4_lag1and2), ' rows\n\n')

# =========================================================
# 7) Save benchmarks
# =========================================================

cat('Saving benchmark datasets...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V4_combined'
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

file_lag1 <- file.path(out_dir, 'EFP_meteo_mortality_traits_v4_RF_benchmark_lag1only.csv')
file_lag1and2 <- file.path(out_dir, 'EFP_meteo_mortality_traits_v4_RF_benchmark_lag1and2.csv')

fwrite(v4_lag1, file_lag1)
fwrite(v4_lag1and2, file_lag1and2)

cat('✅ Lag1 only: ', file_lag1, '\n')
cat('✅ Lag1+2: ', file_lag1and2, '\n\n')

# =========================================================
# 8) Summary
# =========================================================

cat('📊 V4 RF BENCHMARK DATASETS:\n')
cat('============================\n\n')

cat('BENCHMARK 1 (Lag1 only):\n')
cat('  Rows: ', nrow(v4_lag1), ' site-years\n')
cat('  Sites: ', uniqueN(v4_lag1$SITE_ID), '\n')
cat('  Years: ', min(v4_lag1$YEAR), '-', max(v4_lag1$YEAR), '\n')
cat('  Columns: ', ncol(v4_lag1), '\n')
cat('  Variables:\n')
cat('    - EFP (current + lag1): 14\n')
cat('    - Meteo CGS (current + lag1): 22\n')
cat('    - Mortality (current + lag1): ', 2 * length(mort_cols), '\n')
cat('    - Traits: 22 (static)\n')
cat('    - Meta: 2\n\n')

cat('BENCHMARK 2 (Lag1 + Lag2):\n')
cat('  Rows: ', nrow(v4_lag1and2), ' site-years\n')
cat('  Sites: ', uniqueN(v4_lag1and2$SITE_ID), '\n')
cat('  Years: ', min(v4_lag1and2$YEAR), '-', max(v4_lag1and2$YEAR), '\n')
cat('  Columns: ', ncol(v4_lag1and2), '\n')
cat('  Variables:\n')
cat('    - EFP (current + lag1 + lag2): 21\n')
cat('    - Meteo CGS (current + lag1 + lag2): 33\n')
cat('    - Mortality (current + lag1 + lag2): ', 3 * length(mort_cols), '\n')
cat('    - Traits: 22 (static)\n')
cat('    - Meta: 2\n\n')

cat('✅ IDENTICAL SITES & YEARS FOR FAIR MODEL COMPARISON!\n')

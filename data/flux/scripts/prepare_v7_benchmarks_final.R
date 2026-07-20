#!/usr/bin/env Rscript
# Create harmonized RF benchmarks:
# 1. Filter by tree cover (>=30%)
# 2. Add plant traits (static per site)
# 3. Create Benchmark 1: lag1 only (continuous 2-year data)
# 4. Create Benchmark 2: lag1+lag2 (continuous 3-year data)
# 5. Harmonize both to identical site-years for fair model comparison

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('V7 HARMONIZED RF BENCHMARKS\n')
cat('====================================================================\n\n')

# =========================================================
# PHASE 1: Load v6 rolling lags
# =========================================================

cat('PHASE 1: Loading v6 rolling lags dataset...\n')

v6 <- fread('derived_tables/outputs_afterEGU_results/V6_rolling_lags/EFP_meteo_mortality_v6_rolling_lags.csv')

cat('  v6 loaded:', nrow(v6), 'rows x', ncol(v6), 'cols\n')
cat('  Sites:', uniqueN(v6$SITE_ID), '\n')
cat('  Years:', min(v6$YEAR), '-', max(v6$YEAR), '\n\n')

# =========================================================
# PHASE 2: Add plant traits
# =========================================================

cat('PHASE 2: Adding plant traits...\n')

# Load v3 for traits (static per site)
v3 <- fread('derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv')

trait_cols <- grep('^(Leaf|SLA|SSD|Stem|Rooting|gsmax|P12|P50|P88|rdmax)', names(v3), value=TRUE)
v3_traits <- v3[, c('SITE_ID', trait_cols), with=FALSE]
v3_traits_static <- v3_traits[!duplicated(SITE_ID)]

cat('  Trait variables:', length(trait_cols), '\n')
cat('  Sites with traits:', nrow(v3_traits_static), '\n')

v6_with_traits <- merge(v6, v3_traits_static, by='SITE_ID', all.x=TRUE)

cat('  After adding traits:', nrow(v6_with_traits), 'rows x', ncol(v6_with_traits), 'cols\n\n')

# =========================================================
# PHASE 3: Apply tree cover filter (>=30%)
# =========================================================

cat('PHASE 3: Applying tree cover filter (>=30%)...\n')

tree_cover_site <- v6_with_traits[, .(mean_tree_cover = mean(forest_mean_pct_500m, na.rm=TRUE)),
                                   by=SITE_ID]

sites_low_cover <- tree_cover_site[mean_tree_cover < 30, SITE_ID]
sites_high_cover <- tree_cover_site[mean_tree_cover >= 30, SITE_ID]

cat('  Sites removed (<30% cover):', length(sites_low_cover), '\n')
cat('  Sites retained (>=30% cover):', length(sites_high_cover), '\n')

v6_filtered <- v6_with_traits[SITE_ID %in% sites_high_cover]

cat('  After tree cover filter:', nrow(v6_filtered), 'rows\n')
cat('  Sites: ', uniqueN(v6_filtered$SITE_ID), '\n\n')

# =========================================================
# PHASE 4: Create Benchmark 1 (lag1 only)
# =========================================================

cat('PHASE 4: Creating Benchmark 1 (lag1 only)...\n')

# Keep rows with complete lag1 data (continuous 2-year data)
efp_vars <- c('uWUE', 'WUE', 'ETmax', 'GPPsat', 'NEPmax')
lag1_cols <- paste0(c(efp_vars), '_lag1')

# Check that lag1 exists and is not NA
b1_candidate <- v6_filtered[can_use_lag1 == TRUE]

# Additional check: all critical lag1 variables must be non-NA
for (col in lag1_cols) {
  b1_candidate <- b1_candidate[!is.na(get(col))]
}

cat('  Rows with complete lag1 data:', nrow(b1_candidate), '\n')

# Remove lag2 columns to create lag1-only dataset
lag2_cols_to_remove <- grep('_lag2$', names(b1_candidate), value=TRUE)
b1 <- b1_candidate[, (lag2_cols_to_remove) := NULL]

cat('  Removed lag2 columns:', length(lag2_cols_to_remove), '\n')
cat('  B1 dataset:', nrow(b1), 'rows x', ncol(b1), 'cols\n')
cat('  B1 sites:', uniqueN(b1$SITE_ID), '\n')
cat('  B1 years:', min(b1$YEAR), '-', max(b1$YEAR), '\n\n')

# =========================================================
# PHASE 5: Create Benchmark 2 (lag1 + lag2)
# =========================================================

cat('PHASE 5: Creating Benchmark 2 (lag1 + lag2)...\n')

# Keep rows with complete lag1 AND lag2 data (continuous 3-year data)
lag2_cols <- paste0(c(efp_vars), '_lag2')

b2_candidate <- v6_filtered[can_use_lag2 == TRUE]

# Check that both lag1 and lag2 exist and are not NA
for (col in c(lag1_cols, lag2_cols)) {
  b2_candidate <- b2_candidate[!is.na(get(col))]
}

cat('  Rows with complete lag1+lag2 data:', nrow(b2_candidate), '\n')

b2 <- copy(b2_candidate)

cat('  B2 dataset:', nrow(b2), 'rows x', ncol(b2), 'cols\n')
cat('  B2 sites:', uniqueN(b2$SITE_ID), '\n')
cat('  B2 years:', min(b2$YEAR), '-', max(b2$YEAR), '\n\n')

# =========================================================
# PHASE 6: Harmonize B1 and B2 (same site-years)
# =========================================================

cat('PHASE 6: Harmonizing benchmarks to identical site-years...\n')

# Strategy: Keep ONLY rows from B2 (lag1+lag2, most restrictive)
# and add matching B1 rows with lag1 columns

# B2 is most restrictive (requires 3 years), so use it as the reference
# B1 should match exactly to B2's site-years (2019-2025 for those sites)

# Get B2's site-year combinations (these are the ones with lag1+lag2)
b2_pairs <- b2[, .(SITE_ID, YEAR)]

# Filter B1 to ONLY these site-years
b1_harmonized <- b1[b2_pairs, on=c('SITE_ID', 'YEAR'), nomatch=0]
b2_harmonized <- b2[b2_pairs, on=c('SITE_ID', 'YEAR'), nomatch=0]

# Note: b2_harmonized should be identical to b2, but this ensures alignment
cat('  B1 site-year pairs:', uniqueN(b1[, .(SITE_ID, YEAR)]), '\n')
cat('  B2 site-year pairs:', uniqueN(b2[, .(SITE_ID, YEAR)]), '\n')
cat('  Common pairs (using B2 as reference):', uniqueN(b2_pairs), '\n')

cat('  B1 after harmonization:', nrow(b1_harmonized), 'rows\n')
cat('  B2 after harmonization:', nrow(b2_harmonized), 'rows\n')

# Verify they're identical
if (nrow(b1_harmonized) == nrow(b2_harmonized)) {
  cat('  ✅ B1 and B2 have IDENTICAL site-years (both', nrow(b1_harmonized), 'rows)\n')
  cat('  Common sites:', uniqueN(b1_harmonized$SITE_ID), '\n')
  cat('  Year range:', min(b1_harmonized$YEAR), '-', max(b1_harmonized$YEAR), '\n\n')
} else {
  cat('  ⚠️ ERROR: Harmonization failed\n\n')
}

# =========================================================
# PHASE 7: Save benchmarks
# =========================================================

cat('PHASE 7: Saving benchmarks...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V7_benchmarks'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

file_b1 <- file.path(out_dir, 'benchmark_B1_lag1only.csv')
file_b2 <- file.path(out_dir, 'benchmark_B2_lag1and2.csv')

fwrite(b1_harmonized, file_b1)
fwrite(b2_harmonized, file_b2)

cat('  Saved B1 to:', file_b1, '\n')
cat('  Size:', round(file.size(file_b1)/1024/1024, 1), 'MB\n')
cat('  Saved B2 to:', file_b2, '\n')
cat('  Size:', round(file.size(file_b2)/1024/1024, 1), 'MB\n\n')

# =========================================================
# SUMMARY
# =========================================================

cat('====================================================================\n')
cat('BENCHMARK SUMMARY\n')
cat('====================================================================\n\n')

cat('BENCHMARK 1 (Lag1 Only):\n')
cat('  Rows:', nrow(b1_harmonized), 'site-years\n')
cat('  Sites:', uniqueN(b1_harmonized$SITE_ID), '\n')
cat('  Years:', min(b1_harmonized$YEAR), '-', max(b1_harmonized$YEAR), '\n')
cat('  Columns:', ncol(b1_harmonized), '\n')
cat('  Contains: EFPs (current + lag1), EFP anomalies, meteo (current + lag1), \n')
cat('            meteo anomalies, mortality (current + lag1), traits, tree cover\n\n')

cat('BENCHMARK 2 (Lag1 + Lag2):\n')
cat('  Rows:', nrow(b2_harmonized), 'site-years\n')
cat('  Sites:', uniqueN(b2_harmonized$SITE_ID), '\n')
cat('  Years:', min(b2_harmonized$YEAR), '-', max(b2_harmonized$YEAR), '\n')
cat('  Columns:', ncol(b2_harmonized), '\n')
cat('  Contains: EFPs (current + lag1 + lag2), EFP anomalies, meteo (current + lag1 + lag2), \n')
cat('            mortality (current + lag1 + lag2), traits, tree cover\n\n')

cat('Key Features:\n')
cat('  ✅ Identical site-years across benchmarks for fair comparison\n')
cat('  ✅ Tree cover filtered (>=30%)\n')
cat('  ✅ Plant traits included (static per site)\n')
cat('  ✅ EFP anomalies (z-scores per site)\n')
cat('  ✅ Meteorology aggregated by center-of-growing-season\n')
cat('  ✅ Continuous years only (no data gaps)\n')
cat('  ✅ Two memory types available: raw EFP lags + anomaly EFP lags\n\n')

cat('Next Steps:\n')
cat('  1. Create separate versions with raw vs anomaly EFP memory\n')
cat('  2. Define model predictor sets (M01-M08 × 2 memory types)\n')
cat('  3. Run RF LOSO training (run_NN_RF_*.R scripts)\n\n')

cat('====================================================================\n')
cat('✅ V7 BENCHMARKS COMPLETE!\n')
cat('====================================================================\n\n')


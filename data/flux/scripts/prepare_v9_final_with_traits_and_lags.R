#!/usr/bin/env Rscript
# V9: Final dataset with zarr mortality, plant traits, and rolling lags
# Create Benchmark 1 (lag1) and Benchmark 2 (lag1+lag2)

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('V9 FINAL BENCHMARKS - ZARR MORTALITY + TRAITS + LAGS\n')
cat('====================================================================\n\n')

# =========================================================
# PHASE 1: Load v8 data (with lags already created)
# =========================================================

cat('PHASE 1: Loading v8 dataset with zarr mortality...\n')

v8 <- fread('derived_tables/outputs_afterEGU_results/V8_zarr_mortality/EFP_meteo_mortality_v8_with_lags.csv')

cat('  Rows:', nrow(v8), '\n')
cat('  Sites:', uniqueN(v8$SITE_ID), '\n')
cat('  Columns:', ncol(v8), '\n\n')

# =========================================================
# PHASE 2: Add plant traits (from v3 as static per site)
# =========================================================

cat('PHASE 2: Adding plant traits...\n')

# Load v3 for traits
v3 <- fread('derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv')

# Extract hydraulic traits (from TIF source)
trait_cols <- grep('^(P12|P50|P88|gsmax|rdmax)_mean$', names(v3), value=TRUE)

if (length(trait_cols) == 0) {
  # Fallback: use original trait names
  trait_cols <- grep('^(Leaf|SLA|SSD|Stem|Rooting|gsmax|P12|P50|P88|rdmax)', names(v3), value=TRUE)
}

v3_traits <- v3[, c('SITE_ID', trait_cols), with=FALSE]
v3_traits_static <- v3_traits[!duplicated(SITE_ID)]

cat('  Trait columns found:', length(trait_cols), '\n')
cat('  Sites with traits:', nrow(v3_traits_static), '\n')

# Merge with v8
v8_with_traits <- merge(v8, v3_traits_static, by='SITE_ID', all.x=TRUE)

cat('  After adding traits:', nrow(v8_with_traits), 'rows x', ncol(v8_with_traits), 'cols\n\n')

# =========================================================
# PHASE 3: Create Benchmark 1 (lag1 only)
# =========================================================

cat('PHASE 3: Creating Benchmark 1 (lag1 only)...\n')

efp_vars <- c('uWUE', 'WUE', 'ETmax', 'GPPsat', 'NEPmax')
lag1_cols <- paste0(c(efp_vars), '_lag1')

# Keep rows with complete lag1 data
b1_candidate <- v8_with_traits[can_use_lag1 == TRUE]

for (col in lag1_cols) {
  b1_candidate <- b1_candidate[!is.na(get(col))]
}

# Remove lag2 columns
lag2_cols_to_remove <- grep('_lag2$', names(b1_candidate), value=TRUE)
b1 <- b1_candidate[, (lag2_cols_to_remove) := NULL]

cat('  Rows with lag1 data:', nrow(b1), '\n')
cat('  Sites:', uniqueN(b1$SITE_ID), '\n')
cat('  Columns:', ncol(b1), '\n\n')

# =========================================================
# PHASE 4: Create Benchmark 2 (lag1 + lag2)
# =========================================================

cat('PHASE 4: Creating Benchmark 2 (lag1 + lag2)...\n')

lag2_cols <- paste0(c(efp_vars), '_lag2')

# Keep rows with complete lag1 AND lag2 data
b2_candidate <- v8_with_traits[can_use_lag2 == TRUE]

for (col in c(lag1_cols, lag2_cols)) {
  b2_candidate <- b2_candidate[!is.na(get(col))]
}

b2 <- copy(b2_candidate)

cat('  Rows with lag1+lag2 data:', nrow(b2), '\n')
cat('  Sites:', uniqueN(b2$SITE_ID), '\n')
cat('  Columns:', ncol(b2), '\n\n')

# =========================================================
# PHASE 5: Harmonize B1 and B2 (identical site-years)
# =========================================================

cat('PHASE 5: Harmonizing benchmarks to identical site-years...\n')

# Use B2 (lag1+lag2, most restrictive) as reference
b2_pairs <- b2[, .(SITE_ID, YEAR)]

# Filter B1 to B2's site-years
b1_harmonized <- b1[b2_pairs, on=c('SITE_ID', 'YEAR'), nomatch=0]
b2_harmonized <- b2[b2_pairs, on=c('SITE_ID', 'YEAR'), nomatch=0]

cat('  B1 after harmonization:', nrow(b1_harmonized), 'rows\n')
cat('  B2 after harmonization:', nrow(b2_harmonized), 'rows\n')

if (nrow(b1_harmonized) == nrow(b2_harmonized)) {
  cat('  ✅ IDENTICAL site-years\n')
  cat('  Sites:', uniqueN(b1_harmonized$SITE_ID), '\n')
  cat('  Year range:', min(b1_harmonized$YEAR), '-', max(b1_harmonized$YEAR), '\n\n')
} else {
  cat('  ⚠️ Row count mismatch\n\n')
}

# =========================================================
# PHASE 6: Save benchmarks
# =========================================================

cat('PHASE 6: Saving final benchmarks...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V9_final_benchmarks'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

file_b1 <- file.path(out_dir, 'benchmark_B1_lag1only_final.csv')
file_b2 <- file.path(out_dir, 'benchmark_B2_lag1and2_final.csv')

fwrite(b1_harmonized, file_b1)
fwrite(b2_harmonized, file_b2)

cat('  Saved B1:', file_b1, '\n')
cat('  Size:', round(file.size(file_b1)/1024/1024, 2), 'MB\n')
cat('  Saved B2:', file_b2, '\n')
cat('  Size:', round(file.size(file_b2)/1024/1024, 2), 'MB\n\n')

# =========================================================
# SUMMARY
# =========================================================

cat('====================================================================\n')
cat('FINAL BENCHMARKS SUMMARY\n')
cat('====================================================================\n\n')

cat('BENCHMARK 1 (Lag1 Only):\n')
cat('  Site-years:', nrow(b1_harmonized), '\n')
cat('  Sites:', uniqueN(b1_harmonized$SITE_ID), '\n')
cat('  Years:', min(b1_harmonized$YEAR), '-', max(b1_harmonized$YEAR), '\n')
cat('  Columns:', ncol(b1_harmonized), '\n')
cat('  Contents: EFPs (current+lag1+anomalies), meteo (CGS+lag1), \n')
cat('            mortality (zarr+lag1), traits (static), tree cover\n\n')

cat('BENCHMARK 2 (Lag1+Lag2):\n')
cat('  Site-years:', nrow(b2_harmonized), '\n')
cat('  Sites:', uniqueN(b2_harmonized$SITE_ID), '\n')
cat('  Years:', min(b2_harmonized$YEAR), '-', max(b2_harmonized$YEAR), '\n')
cat('  Columns:', ncol(b2_harmonized), '\n')
cat('  Contents: EFPs (current+lag1+lag2+anomalies), meteo (CGS+lag1+lag2), \n')
cat('            mortality (zarr+lag1+lag2), traits (static), tree cover\n\n')

cat('Key Features:\n')
cat('  ✅ Zarr-extracted mortality (357 sites originally)\n')
cat('  ✅ CGS-centered meteorology with lags\n')
cat('  ✅ Plant traits (static per site)\n')
cat('  ✅ EFP anomalies (z-scores per site)\n')
cat('  ✅ Identical site-years (fair model comparison)\n')
cat('  ✅ Tree cover >=30% filter applied\n')
cat('  ✅ Continuous years only (no data gaps)\n\n')

cat('Next Steps:\n')
cat('  1. Extract memory types (raw lag vs anomaly)\n')
cat('  2. Define M01-M08 predictor sets\n')
cat('  3. Run RF LOSO training\n\n')

cat('====================================================================\n')
cat('✅ V9 FINAL BENCHMARKS READY FOR RF MODELING!\n')
cat('====================================================================\n\n')


#!/usr/bin/env Rscript
# Combine v4 rolling 3-year with plant traits and mortality data
# Simplified approach: extract from v3_harmonized

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('📊 Creating v4 Complete: EFP + Meteorology + Traits + Mortality\n')
cat('==============================================================\n\n')

# =========================================================
# 1) Load v4 rolling 3-year data
# =========================================================

cat('Loading v4 rolling 3-year dataset...\n')
v4_3year <- fread('derived_tables/outputs_afterEGU_results/V4_combined/EFP_meteo_combined_v4_rolling3year.csv')

cat('  Rows: ', nrow(v4_3year), '\n')
cat('  Sites: ', uniqueN(v4_3year$SITE_ID), '\n')
cat('  Columns: ', ncol(v4_3year), '\n\n')

# =========================================================
# 2) Load v3_harmonized for traits and mortality
# =========================================================

cat('Loading v3_harmonized for traits and mortality...\n')
v3 <- fread('derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv')

# Extract plant traits (columns 207-228 = static, one value per site)
trait_cols <- names(v3)[207:228]
mortality_cols <- grep('^(mortality|deadwood|forest_loss|new_mortality)', names(v3), value = TRUE)

cat('  Plant traits (columns 207-228): ', length(trait_cols), ' variables\n')
cat('  Mortality/disturbance: ', length(mortality_cols), ' variables\n\n')

# =========================================================
# 3) Extract static traits (one row per site)
# =========================================================

cat('Extracting static plant traits (per site)...\n')

# Traits are static, so just take the first row per site
v3_traits <- v3[, c('SITE_ID', trait_cols), with = FALSE]
v3_traits <- v3_traits[!duplicated(SITE_ID)]

cat('  Trait rows: ', nrow(v3_traits), ' (one per site)\n')
cat('  Complete trait cases: ', nrow(v3_traits[complete.cases(v3_traits)]), '\n\n')

# =========================================================
# 4) Extract mortality data (yearly)
# =========================================================

cat('Extracting mortality/disturbance data (yearly)...\n')

v3_mortality <- v3[, c('SITE_ID', 'YEAR', mortality_cols), with = FALSE]

cat('  Mortality rows: ', nrow(v3_mortality), ' (site-years)\n')
cat('  Unique sites: ', uniqueN(v3_mortality$SITE_ID), '\n\n')

# =========================================================
# 5) Merge v4 + mortality + traits
# =========================================================

cat('Merging datasets...\n')

# First merge v4 with mortality (by SITE_ID, YEAR)
v4_complete <- merge(
  v4_3year,
  v3_mortality,
  by = c('SITE_ID', 'YEAR'),
  all.x = TRUE
)

cat('  After adding mortality: ', nrow(v4_complete), ' rows\n')

# Then merge with traits (by SITE_ID only - static traits)
v4_complete <- merge(
  v4_complete,
  v3_traits,
  by = 'SITE_ID',
  all.x = TRUE
)

cat('  After adding traits: ', nrow(v4_complete), ' rows\n')
cat('  Total columns: ', ncol(v4_complete), '\n\n')

# =========================================================
# 6) Save complete dataset
# =========================================================

cat('Saving complete v4 dataset...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V4_combined'
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

out_file <- file.path(out_dir, 'EFP_meteo_traits_mortality_v4_rolling3year_complete.csv')
fwrite(v4_complete, out_file)

cat('✅ Saved to: ', out_file, '\n\n')

# =========================================================
# 7) Summary statistics
# =========================================================

cat('📊 FINAL v4 COMPLETE DATASET SUMMARY:\n')
cat('=====================================\n\n')

cat('Rows: ', nrow(v4_complete), ' site-years\n')
cat('Sites: ', uniqueN(v4_complete$SITE_ID), '\n')
cat('Years: ', min(v4_complete$YEAR, na.rm=TRUE), '-', max(v4_complete$YEAR, na.rm=TRUE), '\n')
cat('Columns: ', ncol(v4_complete), '\n\n')

cat('Content breakdown:\n')
cat('  EFP variables: 7\n')
cat('  Lagged EFP: 14 (lag1 + lag2)\n')
cat('  Meteorology: 11\n')
cat('  Lagged meteorology: 22 (lag1 + lag2)\n')
cat('  Plant traits: ', length(trait_cols), ' (static per site)\n')
cat('  Mortality/disturbance: ', length(mortality_cols), ' (yearly)\n')
cat('  Meta: 2 (SITE_ID, YEAR)\n\n')

# Data quality
complete_rows <- nrow(v4_complete[complete.cases(v4_complete)])
cat('Complete cases (no NAs): ', complete_rows, ' / ', nrow(v4_complete), ' (',
    round(100*complete_rows/nrow(v4_complete), 1), '%)\n\n')

cat('✅ v4 COMPLETE DATASET READY FOR MODELING!\n')

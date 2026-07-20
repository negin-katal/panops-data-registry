#!/usr/bin/env Rscript
# Step 15: Extract and merge ALL plant traits from V3 to RF-ready dataset

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 15: MERGE ALL PLANT TRAITS TO RF-READY DATASET\n')
cat('====================================================================\n\n')

# Load RF-ready dataset
cat('Loading RF-ready dataset...\n')
dt_rf <- fread('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready.csv')

cat('  Rows:', nrow(dt_rf), '\n')
cat('  Sites:', uniqueN(dt_rf$SITE_ID), '\n')
cat('  Columns (before traits):', ncol(dt_rf), '\n\n')

# Load V3 traits
cat('Loading V3 plant traits...\n')
v3_file <- 'derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv'
dt_v3 <- fread(v3_file)

cat('  V3 rows:', nrow(dt_v3), '\n')
cat('  V3 columns:', ncol(dt_v3), '\n\n')

# Extract trait columns from V3
# Hydraulic traits
hydraulic_cols <- c('P12_mean', 'P50_mean', 'P88_mean', 'gsmax_mean', 'rdmax_mean')

# Analysis-ready coded traits (from column inspection of V3)
analysis_cols <- c(
  'SSD', 'SLA',
  'Leaf C', 'Leaf C/N ratio', 'Leaf N (area)', 'Leaf N (mass)', 'Leaf P',
  'Leaf area', 'Leaf area (3112)', 'Leaf area (3114)',
  'Leaf delta 15N', 'Leaf dry mass', 'Leaf thickness', 'Leaf width',
  'rooting_depth',  # If it exists
  'Stem conduit density', 'Stem conduit diameter'
)

# Verify columns exist and select
cat('Checking trait columns in V3...\n')
available_traits <- c()

for (col in hydraulic_cols) {
  if (col %in% names(dt_v3)) {
    available_traits <- c(available_traits, col)
    cat(sprintf('  ✓ %s\n', col))
  } else {
    cat(sprintf('  ✗ %s (not found)\n', col))
  }
}

for (col in analysis_cols) {
  if (col %in% names(dt_v3)) {
    available_traits <- c(available_traits, col)
    cat(sprintf('  ✓ %s\n', col))
  }
}

cat('\n')

# Keep only SITE_ID and trait columns from V3
select_cols <- c('SITE_ID', available_traits)
dt_v3_traits <- dt_v3[, ..select_cols]

# Keep only unique sites (traits are static per site)
dt_v3_traits <- dt_v3_traits[!duplicated(SITE_ID)]

cat(sprintf('Selected trait columns: %d\n', length(available_traits)))
cat(sprintf('Sites with traits: %d\n\n', nrow(dt_v3_traits)))

# Merge traits to RF dataset
cat('Merging traits by SITE_ID...\n')

dt_final <- merge(dt_rf, dt_v3_traits, by='SITE_ID', all.x=TRUE)

cat('  Final rows:', nrow(dt_final), '\n')
cat('  Final columns:', ncol(dt_final), '\n')
cat(sprintf('  Columns added: %d trait variables\n\n', length(available_traits)))

# Check trait availability
cat('Trait availability:\n')
for (col in available_traits) {
  n_avail <- sum(!is.na(dt_final[[col]]))
  pct <- 100 * n_avail / nrow(dt_final)
  cat(sprintf('  %s: %d/%d (%.1f%%)\n', col, n_avail, nrow(dt_final), pct))
}

cat('\n')

# Save final dataset with all traits
cat('Saving final RF-ready dataset with ALL traits...\n')

out_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_rf_ready_with_traits.csv'
fwrite(dt_final, out_file)

cat(sprintf('  Saved: %s\n', out_file))
cat(sprintf('  Size: %.1f MB\n', file.size(out_file)/1024/1024))
cat(sprintf('  Rows: %d site-years\n', nrow(dt_final)))
cat(sprintf('  Columns: %d\n', ncol(dt_final)))
cat(sprintf('    - RF-ready base: 556\n'))
cat(sprintf('    - Plant traits added: %d\n', length(available_traits)))
cat(sprintf('    - TOTAL: %d\n\n', ncol(dt_final)))

# Summary
cat('DATASET SUMMARY:\n')
cat('  Response variables: 5 (GPPsat, NEPmax, ETmax, uWUE, WUE)\n')
cat('  Response anomalies: 5\n')
cat('  Disturbance metrics (current + lag1 + lag2): 225\n')
cat('  Meteo lags (CGS monthly): 286\n')
cat(sprintf('  Plant traits (static): %d\n', length(available_traits)))
cat('    - Hydraulic: 5 (P12, P50, P88, gsmax, rdmax)\n')
cat(sprintf('    - Analysis-ready coded: %d\n', length(available_traits) - 5))
cat('  Metadata: 2\n')
cat(sprintf('  TOTAL: %d columns\n\n', ncol(dt_final)))


cat('✅ STEP 15 COMPLETE - READY FOR RF MODELING WITH ALL TRAITS\n')
cat('====================================================================\n\n')


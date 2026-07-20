#!/usr/bin/env Rscript
# Prepare v5 integrated dataset with:
# 1. EFP data (keep as is)
# 2. Monthly meteo aggregated to yearly (replace old meteo)
# 3. Mortality data from deadtree zarr files
# 4. Plant traits from TIF files
# 5. Tree cover filter (>=30%)

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('V5 INTEGRATED DATASET PREPARATION\n')
cat('====================================================================\n\n')

# =========================================================
# PHASE 1: Load base data and remove old meteo
# =========================================================

cat('PHASE 1: Loading base data...\n')

# Load v4 base (EFP + lags only, remove meteo)
v4_base <- fread('derived_tables/outputs_afterEGU_results/V4_combined/EFP_meteo_combined_v4_rolling3year.csv')

cat('  v4 base loaded:', nrow(v4_base), 'rows x', ncol(v4_base), 'cols\n')

# Columns to keep from v4 (EFPs + lags, exclude old meteo)
meteo_to_remove <- grep('^(TA|VPD|SW_IN|P_)', names(v4_base), value=TRUE)

cat('  Removing', length(meteo_to_remove), 'old meteo columns\n')

# Keep: SITE_ID, YEAR, EFPs (including lags), other vars
# grep with _lag[12] will include both lags automatically
cols_to_keep <- c('SITE_ID', 'YEAR',
                  grep('^(uWUE|WUE|ETmax|GPPsat|NEPmax|Rb|Rbmax|aCUE|TZ|precipAvail|Gavail|GSmax|CO2avail|G1|EF|EFampl|GSmax_lag|G1_lag|nyears|status|n_months)',
                       names(v4_base), value=TRUE))

# Remove duplicates
cols_to_keep <- unique(cols_to_keep)

v4_clean <- v4_base[, ..cols_to_keep]

cat('  After removing meteo: ', nrow(v4_clean), 'rows x', ncol(v4_clean), 'cols\n\n')

# =========================================================
# PHASE 2: Add aggregated monthly meteo (CGS-based)
# =========================================================

cat('PHASE 2: Processing monthly meteorology...\n')

# Load monthly meteo (wide format)
meteo_wide <- fread('fluxnet_2017_2025_V02/EFP_outputs_corrected/MONTHLY_METEO_WIDE.csv')
cgs_data <- fread('derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv')

# Fix column name: 'year' -> 'YEAR'
setnames(cgs_data, 'year', 'YEAR')

cat('  Monthly meteo:', nrow(meteo_wide), 'rows\n')
cat('  CGS data:', nrow(cgs_data), 'rows\n')

# Convert meteo wide to long format for easier aggregation
meteo_long <- melt(meteo_wide, id.vars=c('SITE_ID', 'YEAR'),
                   variable.name='var_month', value.name='value')

# Extract variable type and month from column name (e.g., "TA_mean_M01" -> "TA_mean", "01")
meteo_long[, c('var_type', 'month_str') := tstrsplit(var_month, '_M', fixed=TRUE)]
meteo_long[, month := as.integer(month_str)]
meteo_long[, var_month := NULL]
meteo_long[, month_str := NULL]

# Merge with CGS to get CGS month for each site-year
meteo_cgs <- merge(meteo_long, cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)],
                   by=c('SITE_ID', 'YEAR'), all.x=TRUE)

# Calculate CGS month
meteo_cgs[, cgs_month := ceiling(CGS_weighted_doy / (365.25/12))]
meteo_cgs[, cgs_month := pmin(pmax(cgs_month, 1L), 12L)]

# Aggregate within ±6 months of CGS month (12-month window)
meteo_cgs[, month_diff := abs(month - cgs_month)]
meteo_cgs[, month_diff := pmin(month_diff, 12 - month_diff)]  # Account for year wrap
meteo_cgs[, in_gs_window := month_diff <= 6]

# Aggregate to yearly (CGS-based)
meteo_yearly <- meteo_cgs[in_gs_window == TRUE,
  .(value_mean = mean(value, na.rm=TRUE)),
  by=.(SITE_ID, YEAR, var_type)
]

# Pivot to wide format
meteo_wide_cgs <- dcast(meteo_yearly, SITE_ID + YEAR ~ var_type,
                        value.var='value_mean')

cat('  CGS-aggregated meteo:', nrow(meteo_wide_cgs), 'rows x', ncol(meteo_wide_cgs), 'cols\n\n')

# Merge with v4_clean (check for overlapping columns)
overlapping <- intersect(names(v4_clean), names(meteo_wide_cgs))
overlapping <- setdiff(overlapping, c('SITE_ID', 'YEAR'))

if (length(overlapping) > 0) {
  cat('  WARNING: Overlapping columns:', length(overlapping), '\n')
  cat('  These will be kept from v4_clean (meteo_wide version will be ignored)\n')
  meteo_wide_cgs[, (overlapping) := NULL]
}

v4_with_meteo <- merge(v4_clean, meteo_wide_cgs, by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  After adding meteo:', nrow(v4_with_meteo), 'rows x', ncol(v4_with_meteo), 'cols\n\n')

# =========================================================
# PHASE 3: Add mortality data from zarr files
# =========================================================

cat('PHASE 3: Extracting mortality data from zarr files...\n')
cat('  (Zarr extraction code to follow - requires rgdal/raster)\n')
cat('  Placeholder: Will extract mortality_intensity, deadwood_mean at 100-500m\n\n')

# TODO: Implement zarr reading and mortality metric calculation
# For now, merge with v3 to get mortality data as a workaround
v3 <- fread('derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv')

mort_cols <- grep('^(mortality|deadwood|forest_loss|new_mortality)', names(v3), value=TRUE)
mort_cols <- setdiff(mort_cols, grep('_lag', mort_cols, value=TRUE))

v3_mort <- v3[, c('SITE_ID', 'YEAR', mort_cols), with=FALSE]

v4_with_mort <- merge(v4_with_meteo, v3_mort, by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  Mortality columns added:', length(mort_cols), '\n')
cat('  Dataset now:', nrow(v4_with_mort), 'rows x', ncol(v4_with_mort), 'cols\n\n')

# =========================================================
# PHASE 4: Add tree cover data
# =========================================================

cat('PHASE 4: Adding tree cover data...\n')

tree_cover_cols <- grep('forest_mean_pct', names(v3), value=TRUE)
v3_tree <- v3[, c('SITE_ID', 'YEAR', tree_cover_cols), with=FALSE]

v4_with_tree <- merge(v4_with_mort, v3_tree, by=c('SITE_ID', 'YEAR'), all.x=TRUE)

cat('  Tree cover columns added:', length(tree_cover_cols), '\n')
cat('  Dataset now:', nrow(v4_with_tree), 'rows x', ncol(v4_with_tree), 'cols\n\n')

# =========================================================
# PHASE 5: Add plant traits (from v3 as proxy for now)
# =========================================================

cat('PHASE 5: Adding plant traits...\n')
cat('  (Detailed TIF extraction to follow)\n')

# For now, use traits from v3
trait_cols <- grep('^(Leaf|SLA|SSD|Stem|Rooting|gsmax|P12|P50|P88|rdmax)', names(v3), value=TRUE)
v3_traits <- v3[, c('SITE_ID', trait_cols), with=FALSE]

# Traits are static per site, so merge without YEAR
v3_traits_static <- v3_traits[!duplicated(SITE_ID)]

v4_with_traits <- merge(v4_with_tree, v3_traits_static, by='SITE_ID', all.x=TRUE)

cat('  Trait columns added:', length(trait_cols), '\n')
cat('  Dataset now:', nrow(v4_with_traits), 'rows x', ncol(v4_with_traits), 'cols\n\n')

# =========================================================
# PHASE 6: Apply tree cover filter (>=30%)
# =========================================================

cat('PHASE 6: Applying tree cover filter...\n')

# Calculate mean tree cover per site (use 500m buffer)
tree_cover_site <- v4_with_traits[, .(mean_tree_cover = mean(forest_mean_pct_500m, na.rm=TRUE)),
                                   by=SITE_ID]

sites_low_cover <- tree_cover_site[mean_tree_cover < 30, SITE_ID]

cat('  Sites with <30% tree cover:', length(sites_low_cover), '\n')
cat('  Sites to keep:', nrow(tree_cover_site) - length(sites_low_cover), '\n')

# Filter dataset
v4_filtered <- v4_with_traits[!(SITE_ID %in% sites_low_cover)]

cat('  After filtering:', nrow(v4_filtered), 'rows x', ncol(v4_filtered), 'cols\n')
cat('  Sites: ', uniqueN(v4_filtered$SITE_ID), '\n')
cat('  Years: ', min(v4_filtered$YEAR, na.rm=TRUE), '-', max(v4_filtered$YEAR, na.rm=TRUE), '\n\n')

# =========================================================
# PHASE 7: Save output
# =========================================================

cat('PHASE 7: Saving v5 integrated dataset...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/V5_integrated'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

out_file <- file.path(out_dir, 'EFP_meteo_mortality_traits_v5_integrated.csv')
fwrite(v4_filtered, out_file)

cat('  Saved to:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n\n')

# =========================================================
# SUMMARY
# =========================================================

cat('====================================================================\n')
cat('V5 INTEGRATED DATASET SUMMARY\n')
cat('====================================================================\n\n')

cat('Dataset dimensions:\n')
cat('  Rows:', nrow(v4_filtered), 'site-years\n')
cat('  Columns:', ncol(v4_filtered), 'variables\n')
cat('  Sites:', uniqueN(v4_filtered$SITE_ID), '\n')
cat('  Years:', min(v4_filtered$YEAR, na.rm=TRUE), '-', max(v4_filtered$YEAR, na.rm=TRUE), '\n\n')

cat('Variable groups:\n')
cat('  EFPs (response):', sum(grepl('^(uWUE|WUE|ETmax|GPPsat|NEPmax)$', names(v4_filtered))), '\n')
cat('  EFP lags:', sum(grepl('^(uWUE|WUE|ETmax|GPPsat|NEPmax)_lag', names(v4_filtered))), '\n')
cat('  Meteorology (CGS):', sum(grepl('^(TA|VPD|P|SW_IN)_', names(v4_filtered))), '\n')
cat('  Mortality:', sum(grepl('^(mortality|deadwood|forest_loss|new_mortality)', names(v4_filtered))), '\n')
cat('  Tree cover:', sum(grepl('forest_mean_pct', names(v4_filtered))), '\n')
cat('  Plant traits:', length(trait_cols), '\n\n')

cat('Data completeness:\n')
complete_rows <- sum(complete.cases(v4_filtered))
cat('  Complete rows:', complete_rows, '/', nrow(v4_filtered),
    '(', round(100*complete_rows/nrow(v4_filtered), 1), '%)\n\n')

cat('✅ V5 INTEGRATED DATASET READY FOR BENCHMARKING!\n')
cat('====================================================================\n\n')


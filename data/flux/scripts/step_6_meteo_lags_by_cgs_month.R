#!/usr/bin/env Rscript
# Step 6: Create meteo lags based on CGS_midpoint_doy
# Lag1: From CGS month (Y-1) to CGS month (Y)
# Lag2: From CGS month (Y-2) to CGS month (Y-1)
# Keep all individual monthly values (not aggregated)

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 6: CREATE METEO LAGS BASED ON CGS MONTH (INDIVIDUAL MONTHLY VALUES)\n')
cat('====================================================================\n\n')

# Load CGS data
cat('Loading CGS data...\n')
cgs <- fread('derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv')
setnames(cgs, 'year', 'YEAR')

cat('  Rows:', nrow(cgs), '\n')
cat('  Sites:', uniqueN(cgs$SITE_ID), '\n\n')

# Convert CGS DOY to month (1-12)
cgs[, CGS_month := ceiling(CGS_weighted_doy / (365.25/12))]
cgs[, CGS_month := pmin(pmax(CGS_month, 1L), 12L)]

cat('Sample CGS conversions:\n')
print(cgs[1:5, .(SITE_ID, YEAR, CGS_weighted_doy, CGS_month)])
cat('\n')

# Load monthly meteo
cat('Loading monthly meteo...\n')
meteo <- fread('derived_tables/outputs_afterEGU_results/v10/meteo_monthly_cleaned.csv')

cat('  Rows:', nrow(meteo), '\n')
cat('  Sites:', uniqueN(meteo$SITE_ID), '\n\n')

# Meteo variables to process
meteo_vars <- c('TA_mean', 'TA_p05', 'TA_p95', 'VPD_mean', 'VPD_p05', 'VPD_p95',
                'SW_IN_mean', 'SW_IN_p05', 'SW_IN_p95', 'P_sum', 'P_mean')

cat('Processing meteo variables:', paste(meteo_vars, collapse=', '), '\n\n')

# Create output dataset
cat('Creating meteo lags...\n')

result_list <- list()

for (i in 1:nrow(cgs)) {
  site <- cgs[i, SITE_ID]
  year <- cgs[i, YEAR]
  cgs_month <- cgs[i, CGS_month]

  if (i %% 100 == 0) cat(sprintf('  Processing %d/%d\n', i, nrow(cgs)))

  # Initialize row
  row_data <- data.table(SITE_ID = site, YEAR = year)

  # LAG1: From CGS month (Y-1) to CGS month (Y)
  lag1_months <- c()

  # Add months from Y-1: from CGS_month to 12
  for (m in cgs_month:12) {
    lag1_months <- c(lag1_months, paste0(year-1, sprintf('%02d', m)))
  }

  # Add months from Y: from 1 to CGS_month
  for (m in 1:cgs_month) {
    lag1_months <- c(lag1_months, paste0(year, sprintf('%02d', m)))
  }

  # Extract lag1 meteo for each month
  for (j in seq_along(lag1_months)) {
    ym <- lag1_months[j]
    year_j <- as.integer(substr(ym, 1, 4))
    month_j <- as.integer(substr(ym, 5, 6))

    meteo_subset <- meteo[SITE_ID == site & YEAR == year_j & MONTH == month_j]

    if (nrow(meteo_subset) > 0) {
      for (var in meteo_vars) {
        col_name <- sprintf('lag1_M%02d_%s', j, var)
        row_data[[col_name]] <- meteo_subset[[var]][1]
      }
    }
  }

  # LAG2: From CGS month (Y-2) to CGS month (Y-1)
  lag2_months <- c()

  # Add months from Y-2: from CGS_month to 12
  for (m in cgs_month:12) {
    lag2_months <- c(lag2_months, paste0(year-2, sprintf('%02d', m)))
  }

  # Add months from Y-1: from 1 to CGS_month
  for (m in 1:cgs_month) {
    lag2_months <- c(lag2_months, paste0(year-1, sprintf('%02d', m)))
  }

  # Extract lag2 meteo for each month
  for (j in seq_along(lag2_months)) {
    ym <- lag2_months[j]
    year_j <- as.integer(substr(ym, 1, 4))
    month_j <- as.integer(substr(ym, 5, 6))

    meteo_subset <- meteo[SITE_ID == site & YEAR == year_j & MONTH == month_j]

    if (nrow(meteo_subset) > 0) {
      for (var in meteo_vars) {
        col_name <- sprintf('lag2_M%02d_%s', j, var)
        row_data[[col_name]] <- meteo_subset[[var]][1]
      }
    }
  }

  result_list[[i]] <- row_data
}

cat('\nCombining results...\n')
result <- rbindlist(result_list, fill=TRUE)

cat('  Result rows:', nrow(result), '\n')
cat('  Result columns:', ncol(result), '\n\n')

# Save output
cat('Saving meteo lags dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/meteo_lags_by_cgs_month.csv'
fwrite(result, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n\n')

cat('✅ STEP 6 COMPLETE\n')
cat('====================================================================\n\n')

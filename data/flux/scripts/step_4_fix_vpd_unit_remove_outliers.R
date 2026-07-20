#!/usr/bin/env Rscript
# Step 4: Fix VPD unit conversion and remove outliers

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 4: FIX VPD UNIT & REMOVE OUTLIERS\n')
cat('====================================================================\n\n')

# Load combined meteo data
cat('Loading combined meteo data...\n')
dt <- fread('derived_tables/outputs_afterEGU_results/v10/meteo_monthly_combined.csv')

cat('  Rows:', nrow(dt), '\n')
cat('  Sites:', uniqueN(dt$SITE_ID), '\n\n')

# VPD columns: VPD_mean, VPD_p05, VPD_p95
vpd_cols <- c('VPD_mean', 'VPD_p05', 'VPD_p95')

cat('Processing VPD columns:', paste(vpd_cols, collapse=', '), '\n\n')

# Check for VPD values that appear to be in Pa instead of hPa
# Normal VPD range: 0-50 hPa. If > 100, likely Pa and should be divided by 100
cat('Step 1: Identify and convert Pa to hPa...\n')

for (col in vpd_cols) {
  vals <- dt[[col]]

  # Find values that are suspiciously high (> 100 hPa, likely in Pa)
  high_vals <- which(vals > 100 & !is.na(vals))

  if (length(high_vals) > 0) {
    cat(sprintf('  %s: Found %d values > 100 (likely Pa units)\n', col, length(high_vals)))

    # Convert from Pa to hPa by dividing by 100
    dt[high_vals, (col) := get(col) / 100]

    cat(sprintf('    Converted %d values from Pa to hPa\n', length(high_vals)))
  }
}

cat('\n')

# Step 2: Remove remaining outliers (3-sigma rule) and replace with NA
cat('Step 2: Remove remaining outliers (set to NA)...\n\n')

numeric_cols <- c('TA_mean', 'TA_p05', 'TA_p95', 'VPD_mean', 'VPD_p05', 'VPD_p95',
                  'SW_IN_mean', 'SW_IN_p05', 'SW_IN_p95', 'P_sum', 'P_mean')

removed_count <- 0

for (col in numeric_cols) {
  vals <- dt[[col]]

  # Skip if mostly NAs
  non_na <- vals[!is.na(vals)]
  if (length(non_na) < 10) next

  mean_val <- mean(non_na, na.rm=TRUE)
  sd_val <- sd(non_na, na.rm=TRUE)

  if (is.na(sd_val) || sd_val == 0) next

  lower_bound <- mean_val - 3 * sd_val
  upper_bound <- mean_val + 3 * sd_val

  outliers <- which(vals < lower_bound | vals > upper_bound)

  if (length(outliers) > 0) {
    dt[outliers, (col) := NA_real_]
    removed_count <- removed_count + length(outliers)

    cat(sprintf('  %s: Removed %d outliers (set to NA)\n', col, length(outliers)))
  }
}

cat(sprintf('\nTotal outliers removed: %d\n\n', removed_count))

# Save cleaned dataset
cat('Saving cleaned meteo dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/meteo_monthly_cleaned.csv'
fwrite(dt, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n\n')

# Summary statistics after cleaning
cat('Summary statistics after cleaning:\n\n')

for (col in vpd_cols) {
  vals <- dt[[col]]
  non_na <- vals[!is.na(vals)]

  if (length(non_na) > 0) {
    cat(sprintf('%s:\n', col))
    cat(sprintf('  Mean: %.2f hPa\n', mean(non_na)))
    cat(sprintf('  SD: %.2f hPa\n', sd(non_na)))
    cat(sprintf('  Range: [%.2f, %.2f] hPa\n', min(non_na), max(non_na)))
    cat(sprintf('  Missing: %d values\n\n', sum(is.na(vals))))
  }
}

cat('✅ STEP 4 COMPLETE\n')
cat('====================================================================\n\n')

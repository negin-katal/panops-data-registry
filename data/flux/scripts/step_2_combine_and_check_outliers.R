#!/usr/bin/env Rscript
# Step 2: Combine all yearly EFP files and check for outliers

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 2: COMBINE YEARLY EFP FILES & CHECK FOR OUTLIERS\n')
cat('====================================================================\n\n')

# Load all yearly EFP files
cat('Loading all yearly EFP files...\n')
efp_dir <- 'fluxnet_2017_2025_V02/EFP_outputs_corrected/yearly_EFP_per_site'
efp_files <- list.files(efp_dir, pattern='_yearly_EFP.csv$', full.names=TRUE)

cat('  Found', length(efp_files), 'files\n')

# Read all files
efp_list <- lapply(efp_files, fread)
dt <- rbindlist(efp_list, fill=TRUE)

cat('  Combined:', nrow(dt), 'rows\n')
cat('  Sites:', uniqueN(dt$SITE_ID), '\n')
cat('  Years:', min(dt$YEAR, na.rm=TRUE), '-', max(dt$YEAR, na.rm=TRUE), '\n')
cat('  Columns:', ncol(dt), '\n\n')

# Identify numeric columns (exclude metadata)
numeric_cols <- names(dt)[sapply(dt, is.numeric) & names(dt) != 'YEAR']
numeric_cols <- numeric_cols[numeric_cols != 'TZ']  # TZ is categorical

cat('Numeric EFP variables:', length(numeric_cols), '\n')
cat('  ', paste(numeric_cols, collapse=', '), '\n\n')

# Check for outliers using 3-sigma rule (mean ± 3*sd)
cat('Checking for outliers (3-sigma rule: mean ± 3*sd)...\n\n')

outlier_summary <- list()

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
    outlier_data <- dt[outliers, .(SITE_ID, YEAR, value = get(col))]
    outlier_data[, variable := col]
    outlier_data[, mean := mean_val]
    outlier_data[, sd := sd_val]
    outlier_data[, lower_bound := lower_bound]
    outlier_data[, upper_bound := upper_bound]
    outlier_data[, deviation := abs(value - mean_val) / sd_val]

    outlier_summary[[col]] <- outlier_data

    cat(sprintf('%s: %d outliers (mean=%.2f, sd=%.2f, bounds=[%.2f, %.2f])\n',
                col, length(outliers), mean_val, sd_val, lower_bound, upper_bound))
  }
}

cat('\n')

# Combine outlier results
if (length(outlier_summary) > 0) {
  outliers_combined <- rbindlist(outlier_summary)
  cat('Total outliers found:', nrow(outliers_combined), '\n\n')

  # Save outlier report
  out_file <- 'derived_tables/outputs_afterEGU_results/v10/outlier_report.csv'
  fwrite(outliers_combined, out_file)
  cat('Saved outlier report:', out_file, '\n\n')

  # Show top outliers
  cat('Top 10 most extreme outliers:\n')
  top_outliers <- outliers_combined[order(-deviation)][1:10]
  print(top_outliers[, .(SITE_ID, YEAR, variable, value, mean, deviation)])
} else {
  cat('✅ No outliers found!\n\n')
}

# Save combined dataset
cat('Saving combined dataset...\n')
out_file_combined <- 'derived_tables/outputs_afterEGU_results/v10/EFP_yearly_combined.csv'
fwrite(dt, out_file_combined)

cat('  Saved:', out_file_combined, '\n')
cat('  Size:', round(file.size(out_file_combined)/1024/1024, 1), 'MB\n\n')

cat('✅ STEP 2 COMPLETE\n')
cat('====================================================================\n\n')

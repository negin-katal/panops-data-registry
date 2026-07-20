#!/usr/bin/env Rscript
# Step 11: Calculate relative disturbance metric for all buffers and merge with EFP data

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 11: CALCULATE RELATIVE DISTURBANCE FOR ALL BUFFERS\n')
cat('====================================================================\n\n')

# Load disturbance data
cat('Loading disturbance v2-2 data...\n')
dist <- fread('derived_tables/final_disturbance_v2-2_multibuffer.csv')
setnames(dist, c('site_id', 'year'), c('SITE_ID', 'YEAR'))

cat('  Rows:', nrow(dist), '\n')
cat('  Sites:', uniqueN(dist$SITE_ID), '\n\n')

# Calculate relative disturbance for each buffer
buffers <- c('100m', '200m', '300m', '400m', '500m')

cat('Calculating relative disturbance for buffers:', paste(buffers, collapse=', '), '\n\n')

for (buf in buffers) {
  # Get column names for this buffer
  deadwood_col <- paste0('deadwood_mean_pct_', buf)
  forest_col <- paste0('tree_cover_mean_pct_', buf)
  loss_col <- paste0('tree_loss_pp_', buf)
  rel_dist_col <- paste0('relative_disturbance_', buf)

  # Calculate relative disturbance
  # Formula: (deadwood + loss) / (forest + loss) × 100
  dist[, (rel_dist_col) := {
    dw <- get(deadwood_col)
    fc <- get(forest_col)
    ls <- get(loss_col)

    # Handle NAs and edge cases
    result <- rep(NA_real_, length(dw))

    # Calculate only where we have valid data
    valid_idx <- !is.na(dw) & !is.na(fc) & !is.na(ls)

    if (sum(valid_idx) > 0) {
      numerator <- dw[valid_idx] + ls[valid_idx]
      denominator <- fc[valid_idx] + ls[valid_idx]

      # Avoid division by zero
      valid_denom <- denominator > 0

      result[valid_idx] <- NA_real_
      result[valid_idx][valid_denom] <- (numerator[valid_denom] / denominator[valid_denom]) * 100

      # Cap at 100% (shouldn't exceed based on formula)
      result[result > 100 & !is.na(result)] <- 100
    }

    result
  }]

  cat(sprintf('  ✓ %s calculated\n', rel_dist_col))
}

cat('\n')

# Save relative disturbance data
cat('Saving relative disturbance metrics...\n')
dist_relative <- dist[, c('SITE_ID', 'YEAR', paste0('relative_disturbance_', buffers)), with=FALSE]

out_file_dist <- 'derived_tables/outputs_afterEGU_results/v10/relative_disturbance_all_buffers.csv'
fwrite(dist_relative, out_file_dist)

cat('  Saved:', out_file_dist, '\n\n')

# Load EFP + disturbance combined
cat('Loading EFP + disturbance combined data...\n')
combined <- fread('derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_combined.csv')

cat('  Rows:', nrow(combined), '\n')
cat('  Columns:', ncol(combined), '\n\n')

# Merge relative disturbance with combined data
cat('Merging relative disturbance with EFP + disturbance...\n')

combined_final <- merge(combined, dist_relative, by=c('SITE_ID', 'YEAR'), all=TRUE)

cat('  Combined rows:', nrow(combined_final), '\n')
cat('  Combined columns:', ncol(combined_final), '\n\n')

# Save final combined dataset
cat('Saving final EFP + disturbance + relative disturbance dataset...\n')
out_file_final <- 'derived_tables/outputs_afterEGU_results/v10/EFP_disturbance_combined.csv'
fwrite(combined_final, out_file_final)

cat('  Saved:', out_file_final, '\n')
cat('  Size:', round(file.size(out_file_final)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(combined_final), '\n')
cat('  Columns:', ncol(combined_final), '\n\n')

# Summary
cat('Dataset summary:\n')
cat('  EFP variables: 20 (includes anomalies)\n')
cat('  Disturbance variables: 70 (old: deadwood, tree_cover, losses by buffer)\n')
cat('  Relative disturbance: 5 (one per buffer: 100m-500m)\n')
cat('  Total columns: ', ncol(combined_final), '\n\n')

# Show sample relative disturbance values
cat('Sample relative disturbance statistics:\n\n')
for (buf in buffers) {
  col <- paste0('relative_disturbance_', buf)
  vals <- combined_final[[col]]
  non_na <- vals[!is.na(vals)]

  if (length(non_na) > 0) {
    cat(sprintf('%s:\n', col))
    cat(sprintf('  Mean: %.1f%%\n', mean(non_na)))
    cat(sprintf('  Range: [%.1f%%, %.1f%%]\n', min(non_na), max(non_na)))
    cat(sprintf('  Missing: %d\n\n', sum(is.na(vals))))
  }
}

cat('✅ STEP 11 COMPLETE\n')
cat('====================================================================\n\n')

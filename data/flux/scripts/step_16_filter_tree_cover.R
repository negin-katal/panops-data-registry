#!/usr/bin/env Rscript
# Step 16: Filter dataset to keep only sites with >=30% tree cover

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 16: FILTER SITES BY TREE COVER (>=30%)\n')
cat('====================================================================\n\n')

# Load RF-ready dataset with traits
cat('Loading RF-ready dataset with traits...\n')
dt_rf <- fread('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready_with_traits.csv')

cat('  Initial rows:', nrow(dt_rf), '\n')
cat('  Initial sites:', uniqueN(dt_rf$SITE_ID), '\n')
cat('  Initial columns:', ncol(dt_rf), '\n\n')

# Load disturbance data for tree cover
cat('Loading tree cover data from disturbance file...\n')
dt_dist <- fread('derived_tables/final_disturbance_v2-2_multibuffer.csv')

# Extract tree cover at 500m buffer (mean across all years per site)
dt_tree_cover <- dt_dist[, .(
  tree_cover_500m = mean(tree_cover_mean_pct_500m, na.rm=TRUE)
), by=.(site_id)]

setnames(dt_tree_cover, 'site_id', 'SITE_ID')

cat('  Sites with tree cover data:', nrow(dt_tree_cover), '\n\n')

# Check tree cover distribution
cat('Tree cover distribution (500m buffer):\n')
cat('  Min:', min(dt_tree_cover$tree_cover_500m, na.rm=TRUE), '%\n')
cat('  Max:', max(dt_tree_cover$tree_cover_500m, na.rm=TRUE), '%\n')
cat('  Mean:', mean(dt_tree_cover$tree_cover_500m, na.rm=TRUE), '%\n')
cat('  Median:', median(dt_tree_cover$tree_cover_500m, na.rm=TRUE), '%\n\n')

# Identify sites with <30% tree cover
n_low_cover <- sum(dt_tree_cover$tree_cover_500m < 30, na.rm=TRUE)
cat(sprintf('Sites with <30%% tree cover: %d\n\n', n_low_cover))

# Merge tree cover to RF dataset
dt_rf_merged <- merge(dt_rf, dt_tree_cover, by='SITE_ID', all.x=TRUE)

# Filter to keep only sites with >=30% tree cover
dt_filtered <- dt_rf_merged[tree_cover_500m >= 30 | is.na(tree_cover_500m) == FALSE]

cat('After filtering to >=30% tree cover:\n')
cat('  Rows:', nrow(dt_filtered), '\n')
cat('  Sites:', uniqueN(dt_filtered$SITE_ID), '\n')
cat('  Rows removed:', nrow(dt_rf) - nrow(dt_filtered), '\n\n')

# Site breakdown before/after
sites_before <- dt_rf[, .N, by=SITE_ID][, .(n_sites=.N, n_siteyears=sum(N))]
sites_after <- dt_filtered[, .N, by=SITE_ID][, .(n_sites=.N, n_siteyears=sum(N))]

cat('Site-year distribution:\n')
cat(sprintf('  Before: %d sites, %d site-years\n', sites_before$n_sites, sites_before$n_siteyears))
cat(sprintf('  After:  %d sites, %d site-years\n', sites_after$n_sites, sites_after$n_siteyears))
cat(sprintf('  Reduction: %d sites (%.1f%%), %d site-years (%.1f%%)\n',
    sites_before$n_sites - sites_after$n_sites,
    100*(sites_before$n_sites - sites_after$n_sites)/sites_before$n_sites,
    sites_before$n_siteyears - sites_after$n_siteyears,
    100*(sites_before$n_siteyears - sites_after$n_siteyears)/sites_before$n_siteyears))

cat('\n')

# Remove tree_cover column before saving (it's just for filtering)
dt_filtered[, tree_cover_500m := NULL]

# Save filtered dataset
cat('Saving filtered RF-ready dataset...\n')
out_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_rf_ready_with_traits_treecover_filtered.csv'
fwrite(dt_filtered, out_file)

cat('  Saved:', out_file, '\n')
cat('  Size:', round(file.size(out_file)/1024/1024, 1), 'MB\n')
cat('  Rows:', nrow(dt_filtered), '\n')
cat('  Columns:', ncol(dt_filtered), '\n\n')

# Summary statistics
cat('Response variable coverage (after filtering):\n')
response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')
for (var in response_vars) {
  n_avail <- sum(!is.na(dt_filtered[[var]]))
  cat(sprintf('  %s: %d rows (%.1f%%)\n', var, n_avail, 100*n_avail/nrow(dt_filtered)))
}

cat('\n✅ STEP 16 COMPLETE - TREE COVER FILTERED DATASET READY\n')
cat('====================================================================\n\n')


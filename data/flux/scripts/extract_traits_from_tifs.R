#!/usr/bin/env Rscript
# Extract plant traits from TIF files using terra package

library(data.table)
library(terra)
library(sf)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('EXTRACTING PLANT TRAITS FROM TIF FILES\n')
cat('====================================================================\n\n')

# Configuration
trait_dir <- 'data/trait_maps/lusk_et-al_2025/cwms/Shrub_Tree_Grass/1km/hydraulic'
metadata_file <- 'Flux4Daniel/fluxnet_site_metadata_clean_with_elevation.csv'
output_file <- 'derived_tables/outputs_afterEGU_results/traits_from_tifs.csv'

traits <- c('P12', 'P50', 'P88', 'gsmax', 'rdmax')
buffer_m <- 500  # Using 500m buffer

cat('STEP 1: Loading site metadata...\n')

metadata <- fread(metadata_file)

cat('  Sites:', nrow(metadata), '\n')
cat('  Traits to extract:', paste(traits, collapse=', '), '\n\n')

# =========================================================
# Extract traits
# =========================================================

cat('STEP 2: Extracting traits from TIF files...\n\n')

results <- list()
failed_count <- 0

for (i in 1:nrow(metadata)) {
  site_id <- metadata[i, SITE_ID]
  lat <- metadata[i, LOCATION_LAT]
  lon <- metadata[i, LOCATION_LONG]

  site_result <- list(SITE_ID = site_id)

  for (trait in traits) {
    trait_file <- file.path(trait_dir, trait, 'splot_gbif', paste0(trait, '_splot_gbif_predict.tif'))

    tryCatch({
      if (file.exists(trait_file)) {
        # Load raster
        r <- terra::rast(trait_file)

        # Extract value at point
        point <- terra::vect(matrix(c(lon, lat), ncol=2), geom=c('x', 'y'), crs='EPSG:4326')

        # Reproject if needed
        if (terra::crs(r) != 'EPSG:4326') {
          point <- terra::project(point, terra::crs(r))
        }

        # Extract value
        value <- terra::extract(r, point, method='bilinear')[1, 2]

        site_result[[paste0(trait, '_500m')]] <- value

      } else {
        site_result[[paste0(trait, '_500m')]] <- NA
      }

    }, error = function(e) {
      site_result[[paste0(trait, '_500m')]] <<- NA
    })
  }

  results[[i]] <- site_result

  if (i %% 50 == 0) {
    cat(sprintf('  Processed %d / %d sites\n', i, nrow(metadata)))
  }
}

cat(sprintf('  Processed %d / %d sites\n\n', nrow(metadata), nrow(metadata)))

# =========================================================
# Combine results
# =========================================================

cat('STEP 3: Combining results...\n')

df_results <- rbindlist(results, fill=TRUE)

cat('  Rows:', nrow(df_results), '\n')
cat('  Columns:', ncol(df_results), '\n\n')

# =========================================================
# Save
# =========================================================

cat('STEP 4: Saving...\n')

dir.create(dirname(output_file), showWarnings=FALSE, recursive=TRUE)
fwrite(df_results, output_file)

cat('  Saved to:', output_file, '\n')
cat('  Size:', round(file.size(output_file)/1024, 1), 'KB\n\n')

# =========================================================
# Summary
# =========================================================

cat('====================================================================\n')
cat('SUMMARY\n')
cat('====================================================================\n\n')

# Count non-NA values
cat('Trait data completeness:\n')
for (trait in traits) {
  col_name <- paste0(trait, '_500m')
  n_valid <- sum(!is.na(df_results[[col_name]]))
  pct <- 100 * n_valid / nrow(df_results)
  cat(sprintf('  %s: %d / %d sites (%.1f%%)\n', col_name, n_valid, nrow(df_results), pct))
}

cat('\n✅ TRAITS EXTRACTED!\n')
cat('====================================================================\n\n')


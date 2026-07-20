#!/usr/bin/env Rscript
# Extract ALL plant traits from TIF files with proper CRS handling

library(data.table)
library(raster)
library(sf)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('STEP 15: EXTRACT ALL PLANT TRAITS (HYDRAULIC + ANALYSIS-READY)\n')
cat('====================================================================\n\n')

# Trait codec for analysis-ready folder
ANALYSIS_CODEC <- list(
  "4" = "SSD",
  "6" = "rooting_depth",
  "11" = "SLA",
  "13" = "Leaf_C",
  "14" = "Leaf_N_mass",
  "15" = "Leaf_P",
  "46" = "Leaf_thickness",
  "50" = "Leaf_N_area",
  "55" = "Leaf_dry_mass",
  "78" = "Leaf_delta15N",
  "145" = "Leaf_width",
  "146" = "Leaf_CN_ratio",
  "169" = "Stem_conduit_density",
  "281" = "Stem_conduit_diameter",
  "3112" = "Leaf_area_v1",
  "3113" = "Leaf_area_v2",
  "3114" = "Leaf_area_v3",
  "3117" = "Leaf_area_v4"
)

# Step 1: Load flux tower coordinates
cat('Step 1: Loading flux tower coordinates...\n')

dt_rf <- fread('derived_tables/outputs_afterEGU_results/v10/v10_rf_ready.csv',
              select=c('SITE_ID'))
sites_unique <- dt_rf[!duplicated(SITE_ID), .(SITE_ID)]

meta_file <- 'fluxnet_2017_2025_V02/EFP_outputs_corrected/EFP_metadata_monthlyMeteo_WIDE.csv'
meta <- fread(meta_file, select=c('SITE_ID', 'LOCATION_LAT', 'LOCATION_LONG'))
meta <- meta[!duplicated(SITE_ID)]

sites_unique <- merge(sites_unique, meta, by='SITE_ID', all.x=TRUE)

cat('  Sites:', nrow(sites_unique), '\n')
cat('  Lat range:', min(sites_unique$LOCATION_LAT, na.rm=TRUE), '-',
    max(sites_unique$LOCATION_LAT, na.rm=TRUE), '\n')
cat('  Lon range:', min(sites_unique$LOCATION_LONG, na.rm=TRUE), '-',
    max(sites_unique$LOCATION_LONG, na.rm=TRUE), '\n\n')

# Convert to sf object with lat/lon, then reproject to EPSG:6933
sites_sf <- st_as_sf(sites_unique, coords=c('LOCATION_LONG', 'LOCATION_LAT'),
                      crs=4326)  # WGS84
sites_sf <- st_transform(sites_sf, crs=6933)  # EASE-Grid 2.0

cat('  Reprojected to EPSG:6933 (EASE-Grid 2.0)\n\n')

# Step 2: Extract hydraulic traits
cat('Step 2: Extracting hydraulic traits...\n')

trait_base <- '/mnt/gsdata/projects/panops/panops-data-registry/data/trait_maps/lusk_et-al_2025/cwms/Shrub_Tree_Grass/1km'
hydraulic_path <- file.path(trait_base, 'hydraulic')
hydraulic_traits <- c('P12', 'P50', 'P88', 'gsmax', 'rdmax')

trait_list <- list(SITE_ID = sites_unique$SITE_ID)

for (trait in hydraulic_traits) {
  trait_dir <- file.path(hydraulic_path, trait)
  tif_files <- list.files(trait_dir, pattern='\\.tif$', full.names=TRUE)

  if (length(tif_files) == 0) {
    cat(sprintf('  %s: WARNING - no TIF found\n', trait))
    trait_list[[paste0(trait, '_mean')]] <- rep(NA_real_, nrow(sites_unique))
    next
  }

  tif_file <- tif_files[1]
  cat(sprintf('  %s: ', trait))

  trait_values <- rep(NA_real_, nrow(sites_unique))

  try({
    r <- raster(tif_file)

    for (i in 1:nrow(sites_sf)) {
      pt <- sites_sf[i, ]
      coords <- st_coordinates(pt)

      # Extract using raster's extract with coordinates
      val <- extract(r, as.matrix(coords[, 1:2]))

      if (!is.na(val) && val > 0) {
        trait_values[i] <- val
      }
    }

    n_extracted <- sum(!is.na(trait_values))
    cat(sprintf('✓ %d/%d sites\n', n_extracted, nrow(sites_unique)))
  })

  trait_list[[paste0(trait, '_mean')]] <- trait_values
}

cat('\n')

# Step 3: Extract analysis-ready traits
cat('Step 3: Extracting analysis-ready traits...\n')

analysis_path <- file.path(trait_base, 'analysis-ready')
analysis_files <- list.files(analysis_path, pattern='^X[0-9]+_mean.*\\.tif$')

for (tif_filename in sort(analysis_files)) {
  # Extract code from filename
  code <- gsub('^X([0-9]+)_.*$', '\\1', tif_filename)
  trait_name <- ANALYSIS_CODEC[[code]]

  if (is.null(trait_name)) {
    next
  }

  cat(sprintf('  X%s (%s): ', code, trait_name))

  tif_file <- file.path(analysis_path, tif_filename)
  trait_values <- rep(NA_real_, nrow(sites_unique))

  try({
    r <- raster(tif_file)

    for (i in 1:nrow(sites_sf)) {
      pt <- sites_sf[i, ]
      coords <- st_coordinates(pt)

      val <- extract(r, as.matrix(coords[, 1:2]))

      if (!is.na(val) && val > 0) {
        trait_values[i] <- val
      }
    }

    n_extracted <- sum(!is.na(trait_values))
    cat(sprintf('✓ %d/%d sites\n', n_extracted, nrow(sites_unique)))
  })

  trait_list[[paste0(trait_name, '_mean')]] <- trait_values
}

cat('\n')

# Step 4: Save all traits
cat('Step 4: Saving all traits...\n')

df_traits <- as.data.table(trait_list)

out_file <- 'derived_tables/outputs_afterEGU_results/v10/plant_traits_all_extracted.csv'
fwrite(df_traits, out_file)

cat(sprintf('  Saved: %s\n', out_file))
cat(sprintf('  Rows: %d\n', nrow(df_traits)))
cat(sprintf('  Columns: %d\n', ncol(df_traits)))
cat(sprintf('    - Hydraulic traits: %d\n', length(hydraulic_traits)))
cat(sprintf('    - Analysis-ready traits: %d\n\n', length(ANALYSIS_CODEC)))

# Availability summary
cat('Trait availability:\n')
trait_cols <- names(df_traits)[names(df_traits) != 'SITE_ID']
for (col in trait_cols) {
  n_avail <- sum(!is.na(df_traits[[col]]))
  pct <- 100 * n_avail / nrow(df_traits)
  cat(sprintf('  %s: %d/%d (%.1f%%)\n', col, n_avail, nrow(df_traits), pct))
}

cat('\n✅ STEP 15 COMPLETE - ALL TRAITS EXTRACTED\n')
cat('====================================================================\n\n')


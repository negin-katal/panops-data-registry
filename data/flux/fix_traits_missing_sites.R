library(terra)
library(data.table)
library(jsonlite)
library(stringr)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

# ============================================================
# FIX MISSING TRAIT VALUES FOR 5 EXCLUDED SITES
#
# These sites returned NA on exact-pixel extraction because:
#   - Wetland sites (CZ-wet, ES-FtD): trait rasters mask wetlands
#   - Others (CH-Dav, CN-BeO, US-UMd): edge/masked pixel at site coords
#
# Fix: project to EASE-Grid 2.0 manually, then extract via a grid
# window of ±PX_RADIUS pixels (no terra buffer, which fails due to
# the raster's ENGCRS not being resolvable by the conda PROJ db).
# PX_RADIUS=3 → 7×7 = 49 cells ≈ 3 km radius at 1 km resolution.
# ============================================================

PX_RADIUS  <- 3L   # primary: 3 pixels (~3 km)
PX_FALLBK  <- 5L   # fallback if primary is all-NA

SITES_TO_FIX <- c("CH-Dav", "CN-BeO", "CZ-wet", "ES-FtD", "US-UMd")

trait_dir_leaf <- "plant_trait/analysis-ready"
trait_dir_hydr <- "plant_trait/hydraulic"
trait_lookup   <- "/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes/clean_data/trait_lookup.json"
combined_file  <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
out_file       <- combined_file

# ============================================================
# 1) Site coordinates
# ============================================================

dt <- fread(combined_file)

coords <- unique(dt[SITE_ID %in% SITES_TO_FIX, .(SITE_ID, LOCATION_LAT, LOCATION_LONG)])
cat("Sites to fix:\n")
print(coords)

# Project WGS84 → EASE-Grid 2.0 using proj4 strings
# (EPSG codes fail due to old PROJ database in conda env)
WGS84_CRS <- "+proj=longlat +datum=WGS84 +no_defs"
EASE_CRS  <- "+proj=cea +lat_ts=30 +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs"

pts_wgs84 <- vect(coords, geom = c("LOCATION_LONG", "LOCATION_LAT"), crs = WGS84_CRS)
pts_proj  <- project(pts_wgs84, EASE_CRS)
xy_ease   <- crds(pts_proj)   # n_sites × 2 matrix

# ============================================================
# 2) Helper: extract mean over a pixel grid window
# ============================================================

extract_window_mean <- function(rast_layer, x, y, px_radius) {
  NR <- nrow(rast_layer)
  NC <- ncol(rast_layer)
  cell_id <- cellFromXY(rast_layer, cbind(x, y))
  rc      <- rowColFromCell(rast_layer, cell_id)
  row_vec <- max(1L, rc[1, 1] - px_radius):min(NR, rc[1, 1] + px_radius)
  col_vec <- max(1L, rc[1, 2] - px_radius):min(NC, rc[1, 2] + px_radius)
  rc_grid <- expand.grid(row = row_vec, col = col_vec)
  cells   <- cellFromRowCol(rast_layer, rc_grid[, 1], rc_grid[, 2])
  mean(rast_layer[cells][, 1], na.rm = TRUE)
}

extract_all_sites <- function(rast_layer, xy_mat, px_radius1, px_radius2) {
  n <- nrow(xy_mat)
  vals <- numeric(n)
  for (i in seq_len(n)) {
    v <- extract_window_mean(rast_layer, xy_mat[i, 1], xy_mat[i, 2], px_radius1)
    if (is.na(v) || is.nan(v)) {
      v <- extract_window_mean(rast_layer, xy_mat[i, 1], xy_mat[i, 2], px_radius2)
    }
    vals[i] <- v
  }
  vals
}

# ============================================================
# 3) Extract leaf traits (analysis-ready, 3 bands per raster)
# ============================================================

leaf_files <- list.files(trait_dir_leaf, pattern = "[.]tif$", full.names = TRUE)
leaf_codes <- sapply(leaf_files, function(f) str_extract(basename(f), "^[^_]+"))

cat("\nExtracting leaf traits (band 1 = mean) with", PX_RADIUS, "px radius...\n")

leaf_vals <- lapply(seq_along(leaf_files), function(i) {
  r <- rast(leaf_files[i])[[1]]   # band 1 = mean
  vals <- extract_all_sites(r, xy_ease, PX_RADIUS, PX_FALLBK)
  data.frame(v = vals, row.names = NULL)
})
leaf_mat <- do.call(cbind, leaf_vals)
colnames(leaf_mat) <- paste0(leaf_codes, "_mean")

# Map X-codes to short trait names via lookup JSON
trait_info <- fromJSON(trait_lookup)
trait_map  <- data.table(
  code_mean = paste0("X", names(trait_info), "_mean"),
  short     = sapply(trait_info, function(x) x$short)
)
for (col in names(leaf_mat)) {
  m <- trait_map[code_mean == col, short]
  if (length(m) == 1 && !is.na(m)) names(leaf_mat)[names(leaf_mat) == col] <- m
}

cat("Leaf traits extracted. Sample:\n")
print(cbind(coords[, .(SITE_ID)], round(leaf_mat, 3)))

# ============================================================
# 4) Extract hydraulic traits (single band per raster)
# ============================================================

hydr_files <- list.files(trait_dir_hydr, pattern = "[.]tif$", full.names = TRUE)
hydr_codes <- sapply(hydr_files, function(f) str_extract(basename(f), "^[^_]+"))

cat("\nExtracting hydraulic traits with", PX_RADIUS, "px radius...\n")

hydr_vals <- lapply(seq_along(hydr_files), function(i) {
  r <- rast(hydr_files[i])
  if (nlyr(r) > 1) r <- r[[1]]
  vals <- extract_all_sites(r, xy_ease, PX_RADIUS, PX_FALLBK)
  data.frame(v = vals, row.names = NULL)
})
hydr_mat <- do.call(cbind, hydr_vals)
colnames(hydr_mat) <- paste0(hydr_codes, "_mean")

cat("Hydraulic traits extracted. Sample:\n")
print(cbind(coords[, .(SITE_ID)], round(hydr_mat, 3)))

# ============================================================
# 5) Patch the combined dataset
# ============================================================

fix_df  <- cbind(data.frame(SITE_ID = coords$SITE_ID, stringsAsFactors = FALSE), leaf_mat, hydr_mat)
fix_dt  <- as.data.table(fix_df)
trait_cols <- setdiff(names(fix_dt), "SITE_ID")

n_patched <- 0L
for (s in SITES_TO_FIX) {
  for (col in trait_cols) {
    if (col %in% names(dt)) {
      new_val <- fix_dt[SITE_ID == s, get(col)]
      if (length(new_val) == 1 && !is.na(new_val) && !is.nan(new_val)) {
        dt[SITE_ID == s, (col) := new_val]
        n_patched <- n_patched + 1L
      }
    }
  }
}

cat(sprintf("\nPatched %d trait×site combinations across %d sites.\n", n_patched, length(SITES_TO_FIX)))

# ============================================================
# 6) Verify and save
# ============================================================

check_cols <- intersect(c("SLA", "Leaf N (mass)", "Leaf C (mass)", "gsmax_mean", "P50_mean"), names(dt))
cat("\nTrait coverage after fix for the 5 sites:\n")
print(unique(dt[SITE_ID %in% SITES_TO_FIX, c("SITE_ID", check_cols), with = FALSE]))

fwrite(dt, out_file)
cat("\nSaved patched dataset to:", out_file, "\n")
cat("Rows:", nrow(dt), "| Cols:", ncol(dt), "\n")

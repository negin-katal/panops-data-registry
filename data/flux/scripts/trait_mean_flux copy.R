rm(list = ls())

library(terra)
library(data.table)
library(dplyr)
library(stringr)

# --- Paths
trait_dir <- "/mnt/gsdata/projects/panops/panops-data-registry/data/trait_maps/lusk_et-al_2025/cwms/Shrub_Tree_Grass/1km"
meta_file <- "/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes/clean_data/combined_site_metadata.csv"

# --- Load tower metadata
towermeta <- fread(meta_file)


# --- List all trait rasters
trait_files <- list.files(trait_dir, pattern = "\\.tif$", full.names = TRUE)

# Helper: extract trait code from filename (first part before "_mean")
get_trait_code <- function(f) {
  basename(f) |> str_extract("^[^_]+")  # e.g. "X237"
}

trait_codes <- sapply(trait_files, get_trait_code)

# --- Create SpatVector of tower locations
tower_pts <- vect(towermeta, geom = c("LOCATION_LONG", "LOCATION_LAT"), crs = "EPSG:4326")

# --- Extract mean value at each tower for each trait
trait_values <- lapply(seq_along(trait_files), function(i) {
  r <- rast(trait_files[i])
  val <- terra::extract(r, tower_pts)[,2]  # skip ID column
  return(val)
})

# Combine into dataframe
trait_df <- as.data.table(trait_values)
setnames(trait_df, trait_codes)

# --- Bind with tower metadata
final_df <- cbind(
  towermeta[, .(SITE_ID, IGBP, LOCATION_LAT, LOCATION_LONG, LOCATION_ELEV)],
  trait_df
)


# --- Save result
fwrite(final_df, "clean_data/flux_traits_1km.csv")
#####
#### Visualize the data
final_df <- fread("clean_data/flux_traits_1km.csv")

head(final_df)


library(ggplot2)
library(data.table)
library(tidyr)

# Assuming final_df is already created from the previous step
df_long <- final_df %>%
  pivot_longer(
    cols = starts_with("X"),   # all trait columns (assuming they start with X…)
    names_to = "Trait",
    values_to = "Value"
  )

# Plot: boxplot of trait values grouped by IGBP
ggplot(df_long, aes(x = IGBP, y = Value, fill = IGBP)) +
  geom_boxplot(outlier.size = 0.8, alpha = 0.7) +
  facet_wrap(~ Trait, scales = "free_y") +
  labs(
    title = "Distribution of Plant Traits by IGBP",
    x = "IGBP (Vegetation Type)",
    y = "Trait Value"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1)#,
    #legend.position = "none"
  )
## write the json file with trait names:
library(jsonlite)
library(data.table)

# --- Load your lookup JSON
trait_info <- fromJSON("clean_data/trait_lookup.json")

# Convert into a data.table for easier mapping
trait_map <- data.table(
  code = names(trait_info),
  short = sapply(trait_info, function(x) x$short),
  long = sapply(trait_info, function(x) x$long),
  unit = sapply(trait_info, function(x) x$unit)
)

# Example: your final_df has columns like X237, X1080 etc.
trait_cols <- grep("^X[0-9]+", names(final_df), value = TRUE)

# Strip the X and match with map
new_names <- sapply(trait_cols, function(x) {
  code <- sub("^X", "", x)
  match_row <- trait_map[code == code]
  if (nrow(match_row) > 0) {
    return(match_row$short)
  } else {
    return(x) # fallback if not found
  }
})

# Rename columns
setnames(final_df, old = trait_cols, new = new_names)

head(final_df)
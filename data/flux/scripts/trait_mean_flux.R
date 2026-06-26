rm(list = ls())
getwd()
setwd("/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes")

library(terra)
library(data.table)
library(dplyr)
library(stringr)

# --- Paths
trait_dir <- "/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes/data/1km/analysis-ready"
meta_file <- "/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes/clean_data/combined_site_metadata.csv"
towermeta <- read.table("MigliavaccaEcosystemfunctionsReprWorkflow/data/InputData_withPCs_Migliavacca2021.csv", header = T, sep = ";")
towermeta <- fread("uligom/Input data.csv")
# --- Load tower metadata
towermeta <- fread(meta_file)

# --- List all trait rasters
trait_files <- list.files(trait_dir, pattern = "\\.tif$", full.names = TRUE)

# Helper: extract trait code from filename (first part before "_")
get_trait_code <- function(f) {
  basename(f) |> str_extract("^[^_]+")  # e.g. "X237"
}
trait_codes <- sapply(trait_files, get_trait_code)

# --- Create SpatVector of tower locations (EPSG:4326)
#tower_pts <- vect(towermeta, geom = c("LOCATION_LONG", "LOCATION_LAT"), crs = "EPSG:4326")
tower_pts <- vect(towermeta, geom = c("longitude", "latitude"), crs = "EPSG:4326")

# --- Reproject tower points to raster CRS (EPSG:6933)
r <- rast(trait_files[1])
tower_pts_proj <- project(tower_pts, crs(r))

# --- Extract values (band 1 = mean, 2 = cv, 3 = applicability)
trait_values <- lapply(seq_along(trait_files), function(i) {
  r <- rast(trait_files[i])
  vals <- terra::extract(r, tower_pts_proj)[, -1]  # drop ID column
  colnames(vals) <- paste0(trait_codes[i], c("_mean", "_cv", "_applic"))
  return(vals)
})

# Combine all traits into one table
trait_df <- do.call(cbind, trait_values)
trait_df <- cbind(trait_df_ex, trait_df_an)
# --- Bind with tower metadata
#final_df <- cbind(
#  towermeta[, .(SITE_ID, IGBP, LOCATION_LAT, LOCATION_LONG, LOCATION_ELEV)],
#  trait_df
#)
final_df <- cbind(
  towermeta,
  trait_df
)
# --- Save

# --- Save result
fwrite(final_df, "clean_data/flux_traits_1km_Ulisse.csv")
#####
#### Visualize the data
final_df <- fread("clean_data/flux_traits_1km.csv")

head(final_df)

#final_df_mean <- final_df %>%
#  dplyr::select(SITE_ID, IGBP, LOCATION_LAT, LOCATION_LONG, LOCATION_ELEV, ends_with("_mean"))

final_df_mean <- final_df %>%
  dplyr::select(-ends_with("_cv"), -ends_with("_applic"))

library(ggplot2)
library(data.table)
library(tidyr)

# Assuming final_df is already created from the previous step
df_long <- final_df_mean %>%
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

library(dplyr)

# Add "X" prefix to code column in trait_map
trait_map <- trait_map %>%
  mutate(codeX = paste0("X", code))

trait_map_mean <- trait_map %>%
  mutate(codeX_mean = paste0(codeX, "_mean"))
# Join df_long with trait_map to get short/long names
df_long_named <- df_long %>%
  left_join(trait_map_mean, by = c("Trait" = "codeX_mean"))

## rename the short column with trait_name
colnames(df_long_named)[38] <- "trait_name"

ggplot(df_long_named, aes( y = Value, fill = PFT)) +
  geom_boxplot(outlier.size = 0.8, alpha = 0.7) +
  facet_wrap(~ trait_name, scales = "free_y") +
  labs(
    title = "Distribution of Plant Traits by IGBP",
    x = "IGBP (Vegetation Type)",
    y = "Trait Value"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1))


str(df_long_named)
library(dplyr)
library(tidyr)

df_wide_named <- df_long_named %>%
  tibble::as_tibble() %>%
  dplyr::select(SITE_ID, IGBP, LOCATION_LAT, LOCATION_LONG, LOCATION_ELEV, trait_name, Value) %>%
  dplyr::distinct() %>%
  tidyr::pivot_wider(
    names_from = trait_name,
    values_from = Value
  )
###Mirco
df_wide_named <- df_long_named %>%
  tibble::as_tibble() %>%
  dplyr::distinct() %>%
  tidyr::pivot_wider(
    id_cols = SITE_ID:Grass,   # all site metadata
    names_from = trait_name,
    values_from = Value,
    values_fn = list(Value = mean)     # collapse duplicates
  )
#### write the file
fwrite(df_wide_named, "clean_data/traitmean_efp_Mirco.csv")
#####################
### filter the data
filtered_IGBP_df <- df_wide_named %>%
  dplyr::filter(IGBP %in% c("CSH", "DBF", "DNF", "EBF", "ENF", "MF", "OSH", "SAV", "WET", "WSA"))

efp_all <- fread("clean_data/efp_by_site_year_V2.csv")
efp_sites <- unique(efp_all$SITE_ID)
efp_trait <- filtered_IGBP_df %>% 
  dplyr::filter(SITE_ID %in% efp_sites)

#### write the file
fwrite(efp_trait, "clean_data/traitmean_flux_efpsites.csv")


df_long <- efp_trait %>%
  pivot_longer(
    cols = 6:22,
    names_to = "trait_name",
    values_to = "Value"
  )
### plot it
ggplot(df_long, aes( y = Value, fill = IGBP)) +
  geom_boxplot(outlier.size = 0.8, alpha = 0.7) +
  facet_wrap(~ trait_name, scales = "free_y") +
  labs(
    title = "Distribution of Plant Traits by IGBP",
    x = "IGBP (Vegetation Type)",
    y = "Trait Value"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1))


rm(list = ls())

## libraries
library(terra)
library(data.table)
library(dplyr)
library(tibble)
library(dplyr)
library(reticulate)
### make an environment
use_condaenv("dheed_env", required = TRUE)
py_config()

# Import Python modules
xr <- import("xarray")

# Open the label cube
labelcube <- xr$open_zarr("YOUR_PATH/mergedlabels.zarr", consolidated = FALSE)

# Load event metadata once
event_stats <- read.csv("YOUR_PATH/MergedEventStats_landonly.csv")

# Coordinates from DHEED cube
lat_vals <- as.numeric(labelcube$coords["latitude"]$values)
lon_vals <- as.numeric(labelcube$coords["longitude"]$values)
time_vals <- as.character(labelcube$coords["Ti"]$values)
labels_var <- labelcube$labels
### read your location file
my_sites <- fread("YOUR_PATH_TO_DESIRE_LOCATIONS")
#####replace the example dataset with eddy tower locations
### first replace LOCATION_LAT and LONG with

# Loop over sites
all_sites_event_history <- lapply(1:nrow(my_sites), function(i) {
  site <- my_sites[i, ]
  
  lat_idx <- which.min(abs(lat_vals - site$latitude))
  lon_idx <- which.min(abs(lon_vals - site$longitude))
  
  label_series <- labels_var$isel(
    latitude = lat_idx,
    longitude = lon_idx
  )$to_numpy()
  ### here depoends to your data what you want to keep
  tibble(
    SITE_ID = site$SITE_ID,
    date = time_vals,
    label = as.integer(label_series),
    IGBP = site$IGBP,
    MAP = site$MAP,
    MAT = site$MAT
  ) %>%
    filter(label > 0)
}) %>% bind_rows()

# Join all with event stats
all_sites_with_metadata <- left_join(all_sites_event_history, event_stats, by = "label")
unique(all_sites_with_metadata$SITE_ID)
# write the file
write.csv(all_sites_with_metadata, "YOUR_PATH", row.names = FALSE)



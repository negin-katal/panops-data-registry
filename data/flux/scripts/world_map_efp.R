setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

library(ggplot2)
library(sf)        # for spatial data (simple features)
library(rnaturalearth)
library(rnaturalearthdata)
library(data.table)
library(dplyr)

EFP_per_site <- fread("efp_per_site/EFP_per_sitesV0Dec.csv")

Site_location <- EFP_per_site %>% 
  select(c(SITE_ID, LOCATION_LAT, LOCATION_LONG, LOCATION_ELEV, IGBP))

#fwrite(Site_location, "348EFP_Locations.csv")

world <- ne_countries(scale = "medium", returnclass = "sf")

ggplot(world) +
  geom_sf(fill = "grey95", color = "grey40") +
  theme_minimal()

sites_sf <- st_as_sf(Site_location, coords = c("LOCATION_LONG", "LOCATION_LAT"), crs = 4326)
### Normal and flat
ggplot() +
  geom_sf(data = world, fill = "grey95", color = "grey40") +
  geom_sf(data = sites_sf, aes(color = IGBP), size = 2) +
  theme_minimal()
### Natural Earth projection
ggplot() +
  geom_sf(data = world, fill = "grey95", color = "grey60") +
  geom_sf(data = sites_sf, aes(color = IGBP), size = 2) +
  coord_sf(crs = "+proj=natearth") +
  theme_minimal()
### Robinson Projection
ggplot() +
  geom_sf(data = world, fill = "grey30", color = "grey70") +
  geom_sf(data = sites_sf, aes(color = IGBP), size = 2) +
  scale_color_viridis_d(option = "turbo") +
  coord_sf(crs = "+proj=robin") +
  theme_void() +
  theme(
    panel.background = element_rect(fill = "black", color = NA),
    plot.background  = element_rect(fill = "black", color = NA),
    legend.text = element_text(color = "white"),
    legend.title = element_text(color = "white")
  )

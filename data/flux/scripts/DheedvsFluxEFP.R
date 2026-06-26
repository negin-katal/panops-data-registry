########## last modification:04.08.2025 by NK
########### This code is modified to investigate heat and drought events across EC towers based on the Dheed dataset
getwd()
setwd("/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes")
### load the libraries

### Let's read the ecosystem functional properties dataset
EFP_all <- fread("clean_data/efp_by_site_year_V2.csv")
EFP_all <- fread("clean_data/EFP_per_sitesV01.csv")
#remove PFT from the begining
unique(EFP_all$SITE_ID)
mean(EFP_all$nyears)
count(EFP_all$nyears>5)
### Keep only following IGBP: CSH, DBF, DNF, EBF, ENF, MF, OSH, SAV, WET, WSA
EFP_filtered <- EFP_all[IGBP %in% c("CSH", "DBF", "DNF", "EBF", "ENF", "MF", "OSH", "SAV", "WET", "WSA")]

### read the dheed data for flux sites
dheed <- fread("clean_data/flux_dheed_events.csv")
unique(dheed$SITE_ID)
dheed_filtered <- dheed[IGBP %in% c("CSH", "DBF", "DNF", "EBF", "ENF", "MF", "OSH", "SAV", "WET", "WSA")]
### Let's plot them on th wold map

dheed_filtered <- dheed_filtered %>% 
  mutate(year = year(date))
world <- ne_countries(scale = "medium", returnclass = "sf")
germany <- world %>% filter(admin == "Germany")

# Plot Germany
ggplot(data = germany) +
  geom_sf(fill = "gray90", color = "black") +
  geom_point(data = efp_de, 
             aes(x = LOCATION_LONG, y = LOCATION_LAT, color = IGBP), 
             size = 2, alpha = 0.8) +  # site points
  scale_color_viridis_d(option = "turbo") +  # colorful palette
  coord_sf() +
  theme_minimal() +
  labs(title = "Current available data 07.08.2025",
       x = "Longitude", y = "Latitude", color = "IGBP")

# Plot
ggplot() +
  geom_sf(data = world, fill = "gray95", color = "gray80") +  # background map
  geom_point(data = EFP_all, 
             aes(x = LOCATION_LONG, y = LOCATION_LAT, color = IGBP), 
             size = 2, alpha = 0.8) +  # site points
  scale_color_viridis_d(option = "turbo") +  # colorful palette
  coord_sf() +
  theme_minimal() +
  labs(title = "Current available data 07.08.2025",
       x = "Longitude", y = "Latitude", color = "IGBP")

unique(EFP_all$SITE_ID)


# Filter German sites
efp_de <- EFP_all %>% filter(grepl("^DE-", SITE_ID))
dheed_de <- dheed_filtered %>% filter(grepl("^DE-", SITE_ID))


library(dplyr)
#### number of events for each site
dheed_de %>%
  group_by(SITE_ID) %>%
  summarise(
    n_events = n_distinct(label),
    first_event = min(start_time),
    last_event = max(end_time),
    avg_duration = mean(as.numeric(gsub(" days", "", duration)))
  ) %>%
  arrange(desc(n_events))


ggplot(dheed_de, aes(x = date, y = SITE_ID, color = as.factor(label))) +
  geom_point(size = 1.2) +
  labs(title = "Compound extreme events at German flux sites",
       x = "Date", y = "Site", color = "Event Label") +
  theme_minimal()
#### select one site
site_plot_data <- dheed_de %>%
  filter(SITE_ID == "DE-Tha") %>%
  select(date, pei_30_mean, pei_90_mean, pei_180_mean, t2mmax_max) %>%
  pivot_longer(cols = -date, names_to = "metric", values_to = "value")

ggplot(site_plot_data, aes(x = date, y = value, color = metric)) +
  geom_line() +
  facet_wrap(~metric, scales = "free_y", ncol = 1) +
  labs(title = "Drought and Heat Indicators at DE-Tha", y = "", x = "Date") +
  theme_minimal()
# Harmonize site IDs
efp_de <- efp_de %>% mutate(SITE_ID = gsub("DE-", "DE-", SITE_ID))

# Extract event years
dheed_de <- dheed_de %>% mutate(year = as.integer(substr(start_time, 1, 4))) %>%
  select(SITE_ID, year) %>% distinct() %>% mutate(event = TRUE)

# Merge EFP with event years
efp_de <- efp_de %>%
  mutate(year = as.integer(year)) %>%
  left_join(dheed_de, by = c("SITE_ID", "year")) %>%
  mutate(event = ifelse(is.na(event), FALSE, event))

# Pivot for plotting
plot_df <- efp_de %>%
  select(SITE_ID, year, GPPsat, NEPmax, ETmax, uWUE, event) %>%
  pivot_longer(cols = c(GPPsat, NEPmax, ETmax, uWUE), names_to = "metric", values_to = "value")

# Plot with red dots for event years
ggplot(plot_df, aes(x = year, y = value)) +
  geom_line() +
  geom_point(aes(color = event), size = 2) +
  scale_color_manual(values = c("FALSE" = "black", "TRUE" = "red")) +
  facet_grid(metric ~ SITE_ID, scales = "free_y") +
  theme_minimal() +
  labs(title = "Ecosystem Functional Properties at German Flux Sites",
       subtitle = "Red = year with extreme compound event",
       y = NULL, x = "Year")



library(dplyr)

dheed_de %>%
  group_by(SITE_ID) %>%
  summarise(
    compound_events = n_distinct(label[compound == 1]),
    heat_only = n_distinct(label[heat == 100 & compound == 0]),
    drought_only = n_distinct(label[drought30 == 100 & compound == 0])
  ) %>%
  arrange(desc(compound_events))


library(ggplot2)

dheed_de %>%
  filter(SITE_ID == "DE-Tha") %>%
  distinct(label, t2mmax_max, pei_30_min, duration) %>%
  ggplot(aes(x = pei_30_min, y = t2mmax_max, size = as.numeric(gsub(" days", "", duration)))) +
  geom_point(alpha = 0.7) +
  labs(x = "Minimum PEI (Drought severity)", y = "Max Temperature (Heat severity)",
       size = "Duration (days)", title = "Extreme Events at DE-Tha") +
  theme_minimal()

library(dplyr)
library(lubridate)
library(ggplot2)

# Convert duration to numeric


dheed_events <- dheed_de %>%
  distinct(SITE_ID, label, start_time, duration, heat, drought30, drought90, drought180, compound, IGBP) %>%
  mutate(
    year = year(start_time),
    duration_days = as.numeric(gsub(" days", "", duration))
  ) %>%
  pivot_longer(
    cols = c(heat, drought30, drought90, drought180, compound),
    names_to = "event_type",
    values_to = "percent"
  ) %>%
  filter(percent == 100)

library(ggplot2)

ggplot(dheed_events, aes(x = year, y = event_type, color = IGBP, size = duration_days)) +
  geom_point(alpha = 0.5) +
  facet_wrap(.~ SITE_ID) +
  scale_size_continuous(name = "Duration (days)") +
  scale_color_brewer(palette = "Set1") +
  theme_minimal(base_size = 13) +
  theme(
    legend.position = "right",
    axis.text.x = element_text(angle = 45, hjust = 1)
  ) +
  labs(
    title = "Extreme Heat and Drought Events at Flux Sites (DHEED)",
    x = "Year",
    y = "Event Type",
    color = "IGBP"
  )

ggplot(dheed_events %>% filter(year > 1995), 
       aes(x = year, y = event_type, color = IGBP, size = duration_days)) +
  geom_point(alpha = 0.5) +
  #facet_wrap(. ~ SITE_ID) +
  facet_grid(rows = vars(SITE_ID), scales = "free_y", space = "free_y") +
  scale_x_continuous(breaks = seq(1996, max(dheed_events$year, na.rm = TRUE), by = 1)) +
  scale_size_continuous(name = "Duration (days)") +
  scale_color_brewer(palette = "Set1") +
  theme_minimal(base_size = 13) +
  theme(
    legend.position = "right",
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text.y = element_text(angle = 0)  # horizontal facet labels
  ) +
  labs(
    title = "Extreme Heat and Drought Events at Flux Sites (DHEED)",
    x = "Year",
    y = "Event Type",
    color = "IGBP"
  )
ggplot(dheed_events, aes(x = year, y = SITE_ID, color = event_type, shape = event_type, size = duration_days)) +
  geom_point(alpha = 0.7) +
  scale_size_continuous(name = "Duration (days)") +
  scale_color_brewer(palette = "Set1") +
  scale_shape_manual(values = c(16, 17, 15, 3, 7)) +
  scale_x_continuous(
    breaks = seq(min(dheed_events$year), max(dheed_events$year), by = 1)
  ) +
  theme_minimal(base_size = 13) +
  theme(
    legend.position = "right",
    axis.text.x = element_text(angle = 45, hjust = 1)
  ) +
  labs(
    title = "Extreme Heat and Drought Events at Flux Sites (DHEED)",
    x = "Year",
    y = "Site",
    color = "Event Type",
    shape = "Event Type"
  )

### Dheed Germany after 1990
ggplot(dheed_events, aes(x = year, y = SITE_ID, color = event_type, shape = event_type, size = duration_days)) +
  geom_point(alpha = 0.7) +
  scale_size_continuous(name = "Duration (days)") +
  scale_color_brewer(palette = "Set1") +
  scale_shape_manual(values = c(16, 17, 15, 3, 7)) +
  scale_x_continuous(
    limits = c(1991, max(dheed_events$year)),
    breaks = seq(1991, max(dheed_events$year), by = 1)
  ) +
  theme_minimal(base_size = 13) +
  theme(
    legend.position = "right",
    axis.text.x = element_text(angle = 45, hjust = 1)
  ) +
  labs(
    title = "Extreme Heat and Drought Events at Flux Sites (DHEED)",
    x = "Year",
    y = "Site",
    color = "Event Type",
    shape = "Event Type"
  )
###### available EFP
target_sites <- c(
  "DE-Har", "DE-HoH", "DE-Hzd", "DE-Lkb", "DE-Lnf",
  "DE-Obe", "DE-RuW", "DE-Spw", "DE-Tha")

unique(efp_de$SITE_ID)
efp_de_filtered <- efp_de %>%
  filter(SITE_ID %in% target_sites)

# Filter and reshape to long format
efp_long <- efp_de_filtered %>%
  select(SITE_ID, year, uWUE, ETmax, GSmax, GPPsat, NEPmax, IGBP) %>%
  pivot_longer(cols = c(uWUE, ETmax, GSmax, GPPsat, NEPmax),
               names_to = "variable",
               values_to = "value")



ggplot(efp_long, aes(x = year, y = value, color = variable)) +
  geom_line(size = 1) +
  facet_wrap(~ SITE_ID, scales = "free_y") +
  #facet_grid(rows = vars(variable), scales = "free_y", space = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Yearly EFPs per Site",
    x = "Year",
    y = "Value",
    color = "variable"
  ) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold")
  )

install.packages("ggtext")
library(ggplot2)
library(dplyr)
library(ggtext)  # for HTML in facet strips

# Define custom colors for IGBP
igbp_colors <- c(
  "ENF" = "forestgreen",
  "DBF" = "sienna",
  "MF"  = "darkorange",
  "WSA" = "goldenrod",
  "GRA" = "chartreuse4",
  "CRO" = "darkgoldenrod1",
  "WET" = "darkblue"
  # Add others as needed
)

# Create a new label with HTML span to color the site ID
efp_long <- efp_long %>%
  mutate(strip_label = paste0(
    "<span style='color:", igbp_colors[IGBP], "'>", SITE_ID, "</span>"
  ))

# Plot with colored strip text
ggplot(efp_long, aes(x = year, y = value, color = variable)) +
  geom_line(size = 1) +
  facet_wrap(~ strip_label, scales = "free_y") +
  theme_minimal(base_size = 14) +
  # Add event year lines
  geom_vline(
    data = target_events,
    aes(xintercept = event_year),
    linetype = "dashed",
    color = "black",
    inherit.aes = FALSE
  ) +
  labs(
    title = "Yearly EFPs per Site",
    x = "Year",
    y = "Value",
    color = "variable"
  ) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_markdown(face = "bold")  # enable HTML rendering
  )

# Make sure efp_long$SITE_ID is a factor or character, matching target_events$SITE_ID
efp_long$SITE_ID <- as.character(efp_long$SITE_ID)

# Plot with vertical dashed lines for event years
ggplot(efp_long, aes(x = year, y = value, color = variable)) +
  geom_line(size = 1) +
  # Add event year lines
  geom_vline(
    data = target_events,
    aes(xintercept = event_year),
    linetype = "dashed",
    color = "black",
    inherit.aes = FALSE
  ) +
  facet_wrap(~ SITE_ID, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Yearly EFPs per Site with Marked Extreme Event Years",
    x = "Year",
    y = "Value",
    color = "EFP Variable"
  ) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold")
  )


ggplot(efp_long_filtered, aes(x = year, y = value, color = variable)) +
  geom_line(size = 1) +
  
  # Add event year lines specific to each site
  geom_vline(
    data = target_events,
    aes(xintercept = event_year, group = SITE_ID),
    linetype = "dashed",
    color = "black",
    inherit.aes = FALSE
  ) +
  
  facet_wrap(~ SITE_ID, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Yearly EFPs per Site with Marked Extreme Event Years",
    x = "Year",
    y = "Value",
    color = "EFP Variable"
  ) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold")
  )


# Vector of sites to exclude
exclude_sites <- c("DE-Lkb", "DE-Lnf", "DE-RuW", "DE-Spw")

# Filter efp_long and target_events to exclude unwanted sites
efp_long_filtered <- efp_long %>% filter(!SITE_ID %in% exclude_sites)
target_events_filtered <- target_events %>% filter(!SITE_ID %in% exclude_sites)

# Plot
ggplot(efp_long_filtered, aes(x = year, y = value, color = variable)) +
  geom_line(size = 1) +
  # Add event year lines for remaining sites
  geom_vline(
    data = target_events_filtered,
    aes(xintercept = event_year),
    linetype = "dashed",
    color = "black",
    inherit.aes = FALSE
  ) +
  facet_wrap(~ SITE_ID, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Yearly EFPs per Site with Marked Extreme Event Years",
    x = "Year",
    y = "Value",
    color = "EFP Variable"
  ) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold")
  )
####### anomalies for german flux based on dheed
library(dplyr)

target_events <- tibble::tibble(
  SITE_ID = c("DE-Har", "DE-HoH", "DE-HoH", "DE-Hzd", "DE-Lkb", "DE-Lnf", 
              "DE-Obe", "DE-Obe", "DE-RuW", "DE-Spw", "DE-Tha"),
  event_year = c(2019, 2006, 2010, 2018, 2015, 2018, 
                 2015, 2018, 2019, 2018, 2018)
)

# Check your data format
head(efp_de)

# Should have at least: SITE_ID, year, uWUE, ETmax, GSmax, GPPsat, NEPmax
# Expand each event year to a ±1 year window
target_sites <- c("DE-Obe", "DE-Tha", "DE-Hzd")
efp_filtered <- efp_de %>%
  filter(SITE_ID %in% target_sites) %>%
  select(SITE_ID, year, uWUE, ETmax, GSmax, GPPsat, NEPmax)
library(tidyr)

efp_long <- efp_filtered %>%
  pivot_longer(cols = -c(SITE_ID, year), names_to = "variable", values_to = "value")

baseline_means <- efp_long %>%
  filter(year < 2018) %>%
  group_by(SITE_ID, variable) %>%
  summarise(baseline_mean = mean(value, na.rm = TRUE), .groups = "drop")

efp_anomalies <- efp_long %>%
  left_join(baseline_means, by = c("SITE_ID", "variable")) %>%
  mutate(anomaly = value - baseline_mean)

target_events <- tibble::tibble(
  SITE_ID = c("DE-Obe", "DE-Tha", "DE-Hzd"),
  event_year = 2018
)

library(ggplot2)

ggplot(efp_anomalies, aes(x = year, y = anomaly, color = variable)) +
  geom_line(size = 1) +
  geom_point(size = 2) +
  geom_vline(data = target_events,
             aes(xintercept = event_year),
             linetype = "dashed",
             color = "red",
             inherit.aes = FALSE) +
  facet_wrap(~ SITE_ID, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Anomalies Relative to Pre-2018 Baseline (Selected Sites)",
    x = "Year",
    y = "Anomaly",
    color = "EFP Variable"
  ) +
  theme(
    strip.text = element_text(face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )


efp_obe <- efp_anomalies %>%
  filter(SITE_ID == "DE-Obe")

ggplot(efp_obe, aes(x = year, y = anomaly)) +
  geom_line(color = "steelblue", size = 1) +
  geom_point(color = "steelblue", size = 2) +
  geom_vline(xintercept = 2018, linetype = "dashed", color = "red") +
  geom_hline(yintercept = 0, linetype = "dotted", color = "black") +   # Zero anomaly
  facet_grid(rows = vars(variable), scales = "free_y") +
  #facet_wrap(~ variable, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Anomalies Relative to Pre-2018 Baseline – DE-Obe",
    x = "Year",
    y = "Anomaly"
  ) +
  theme(
    strip.text = element_text(face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

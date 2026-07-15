#!/usr/bin/env Rscript
# Plot mortality and tree cover change for 164+ RF model sites
# Using: forest_mean_pct_500m, mortality_intensity_pct_500m, deadwood_mean_pct_500m

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

# Create output directory
OUT_DIR <- "plots/mortality_Tcoverchange"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# Dark theme colors
DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

cat("Loading RF v3 harmonized dataset...\n")
# Load the main modeling dataset with all variables
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

cat("Loading 164 RF+SHAP analysis sites...\n")
# Load the disturbance analysis dataset which contains the 164 sites used in RF+SHAP
dist_analysis <- fread("derived_tables/disturbance_metric_test/tertiles_method.csv")
rf_shap_sites <- unique(dist_analysis$SITE_ID)
cat("Found", length(rf_shap_sites), "RF+SHAP sites\n")

# Filter main data to only include RF+SHAP sites
main_data <- main_data[SITE_ID %in% rf_shap_sites]

# Get unique sites
sites_list <- unique(main_data$SITE_ID)
cat("Will plot", length(sites_list), "sites with data\n")

cat("Loading IGBP data...\n")
# Load IGBP data from site metadata
igbp_map <- fread("combined_site_metadata.csv")[, .(SITE_ID, IGBP)]

# Define dark theme
dark_theme <- theme_bw(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border     = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.5),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
    panel.grid.minor = element_blank(),
    axis.text        = element_text(colour = AXIS_COL, size = 8),
    axis.title       = element_text(colour = AXIS_COL, size = 9),
    axis.ticks       = element_line(colour = GRID_COL),
    plot.title       = element_text(colour = TEXT_COL, size = 12, face = "bold"),
    plot.subtitle    = element_text(colour = AXIS_COL, size = 9),
    legend.background = element_rect(fill = PANEL_BG, colour = GRID_COL),
    legend.text      = element_text(colour = AXIS_COL, size = 8),
    legend.title     = element_text(colour = AXIS_COL, size = 9)
  )

# Function to create mortality vs tree cover plot for one site
create_site_plot <- function(site_id, data, igbp_info) {
  site_data <- data[SITE_ID == site_id]

  if (nrow(site_data) == 0) return(NULL)

  # Get IGBP type
  igbp <- igbp_info[SITE_ID == site_id, IGBP]
  if (length(igbp) == 0 || is.na(igbp)) igbp <- "Unknown"

  # Select relevant columns and rename for clarity
  site_data <- site_data[, .(
    YEAR,
    tree_cover = forest_mean_pct_500m * 100,  # Convert to percentage
    deadwood = deadwood_mean_pct_500m * 100  # Convert to percentage
  )]

  # Remove rows with NA values
  site_data <- site_data[complete.cases(site_data)]

  if (nrow(site_data) == 0) return(NULL)

  # Create two-variable plot (tree cover and deadwood)
  p <- ggplot(site_data, aes(x = YEAR)) +
    geom_line(aes(y = tree_cover, colour = "Tree Cover (%)"), linewidth = 1) +
    geom_point(aes(y = tree_cover, colour = "Tree Cover (%)"), size = 2) +
    geom_line(aes(y = deadwood, colour = "Deadwood (%)"), linewidth = 1) +
    geom_point(aes(y = deadwood, colour = "Deadwood (%)"), size = 2) +
    scale_colour_manual(
      name = "",
      values = c(
        "Tree Cover (%)" = "#3498db",
        "Deadwood (%)" = "#e74c3c"
      )
    ) +
    scale_y_continuous(
      name = "Percentage (%)",
      limits = c(0, max(site_data$tree_cover, site_data$deadwood, na.rm = TRUE) * 1.1)
    ) +
    scale_x_continuous(
      name = "Year",
      breaks = seq(floor(min(site_data$YEAR)), ceiling(max(site_data$YEAR)), 2)
    ) +
    labs(
      title = paste(site_id, " | ", igbp, sep = ""),
      subtitle = paste("Years:", min(site_data$YEAR), "-", max(site_data$YEAR))
    ) +
    dark_theme +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
      legend.position = "top"
    )

  return(p)
}

# Generate plots for each site
cat("Creating plots for", length(sites_list), "sites...\n")
success_count <- 0
fail_count <- 0

for (site in sites_list) {
  tryCatch({
    p <- create_site_plot(site, main_data, igbp_map)

    if (!is.null(p)) {
      filename <- file.path(OUT_DIR, paste0(site, "_mortality_Tcover_change.png"))
      ggsave(filename, p, width = 120, height = 100, units = "mm", dpi = 300, bg = DARK_BG)
      success_count <- success_count + 1

      if (success_count %% 25 == 0) {
        cat(sprintf("  ✓ Plotted %d sites\n", success_count))
      }
    }
  }, error = function(e) {
    fail_count <<- fail_count + 1
  })
}

cat(sprintf("\n✅ Completed!\n"))
cat(sprintf("   Successfully plotted: %d sites\n", success_count))
cat(sprintf("   Failed: %d sites\n", fail_count))
cat(sprintf("   Output directory: %s\n", OUT_DIR))

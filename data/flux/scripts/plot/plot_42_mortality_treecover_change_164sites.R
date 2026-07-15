#!/usr/bin/env Rscript
# Plot mortality (deadwood) and tree cover change for 164 RF model sites

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

cat("Loading RF model sites...\n")
# Get the 164 sites from the RF model dataset
rf_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv")
rf_sites <- unique(rf_data$SITE_ID)
cat("Found", length(rf_sites), "sites in RF model\n")

cat("Loading forest/deadwood data...\n")
# Load forest and deadwood data
fw_data <- fread("derived_tables/deadtree_deadwood_forest_siteyear_mean_500m.csv")

# Filter for RF model sites
fw_data <- fw_data[SITE_ID %in% rf_sites]
fw_data <- fw_data[order(SITE_ID, year)]

cat("Creating plots for", length(unique(fw_data$SITE_ID)), "sites...\n")

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
create_site_plot <- function(site_id, data) {
  site_data <- data[SITE_ID == site_id]

  if (nrow(site_data) == 0) return(NULL)

  # Convert to percentage
  site_data[, deadwood_pct := deadwood_mean_500m * 100]
  site_data[, forest_pct := forest_mean_500m * 100]

  # Create two-axis plot
  p <- ggplot(site_data, aes(x = year)) +
    geom_line(aes(y = deadwood_pct, colour = "Deadwood (%)"), linewidth = 1) +
    geom_point(aes(y = deadwood_pct, colour = "Deadwood (%)"), size = 2) +
    geom_line(aes(y = forest_pct, colour = "Tree Cover (%)"), linewidth = 1) +
    geom_point(aes(y = forest_pct, colour = "Tree Cover (%)"), size = 2) +
    scale_colour_manual(
      name = "",
      values = c("Deadwood (%)" = "#e74c3c", "Tree Cover (%)" = "#3498db")
    ) +
    scale_y_continuous(
      name = "Deadwood & Tree Cover (%)",
      limits = c(0, max(site_data$deadwood_pct, site_data$forest_pct, na.rm = TRUE) * 1.1)
    ) +
    scale_x_continuous(name = "Year", breaks = seq(floor(min(site_data$year)), ceiling(max(site_data$year)), 2)) +
    labs(
      title = paste("Site:", site_id),
      subtitle = paste("Years:", min(site_data$year), "-", max(site_data$year))
    ) +
    dark_theme +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
      legend.position = "top"
    )

  return(p)
}

# Generate plots for each site
sites_to_plot <- unique(fw_data$SITE_ID)
success_count <- 0
fail_count <- 0

for (site in sites_to_plot) {
  tryCatch({
    p <- create_site_plot(site, fw_data)

    if (!is.null(p)) {
      filename <- file.path(OUT_DIR, paste0(site, "_mortality_Tcover_change.png"))
      ggsave(filename, p, width = 120, height = 100, units = "mm", dpi = 300, bg = DARK_BG)
      success_count <- success_count + 1

      if (success_count %% 20 == 0) {
        cat(sprintf("  ✓ Plotted %d sites\n", success_count))
      }
    }
  }, error = function(e) {
    fail_count <<- fail_count + 1
    cat(sprintf("  ✗ Error plotting %s: %s\n", site, e$message))
  })
}

cat(sprintf("\n✅ Completed!\n"))
cat(sprintf("   Successfully plotted: %d sites\n", success_count))
cat(sprintf("   Failed: %d sites\n", fail_count))
cat(sprintf("   Output directory: %s\n", OUT_DIR))

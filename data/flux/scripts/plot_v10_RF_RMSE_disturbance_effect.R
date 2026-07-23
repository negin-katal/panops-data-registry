#!/usr/bin/env Rscript
# ============================================================================
# V10 Plot: RF RMSE by Disturbance Effect
# Compares M03 (C+D) vs M01 (C) models across disturbance metric tiers
# ============================================================================

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir <- "plots/V10"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Theme and colors
DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

COL_BASE <- "#6BA3C4"   # Blue - Climate only (M01)
COL_DIST <- "#E8257A"   # Pink/Red - With Disturbance (M03)

EFP_ORDER <- c("ETmax", "GPPsat", "NEPmax", "WUE", "uWUE")

# ============================================================================
# Load data
# ============================================================================

cat("Loading data...\n")

# Load main data for disturbance metrics
model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
main_data <- fread(model_file, select = c("SITE_ID", "mortality_intensity_pct_500m",
                                          "loss_area_frac_500m", "forest_mean_pct_500m",
                                          "deadwood_mean_pct_500m"))

# Load v10 harmonized data to get sites
df_b1 <- fread("derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv",
               select = c("SITE_ID"))
v10_sites <- unique(df_b1$SITE_ID)

# Filter main data to v10 sites
main_data <- main_data[SITE_ID %in% v10_sites]

# Calculate site-level metrics
site_metrics <- main_data[, .(
  abs_mort = mean(mortality_intensity_pct_500m, na.rm = TRUE),
  rel_mort = mean((mortality_intensity_pct_500m + loss_area_frac_500m * 100) /
                   (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100, na.rm = TRUE),
  rel_dist = mean((deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
                   (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100, na.rm = TRUE)
), by = SITE_ID]

cat(sprintf("Sites: %d\n", nrow(site_metrics)))

# Create categorical tiers using tertiles
site_metrics[, abs_mort_tier := cut(abs_mort,
                                     breaks = quantile(abs_mort, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                                     labels = c("Low", "Med", "High"),
                                     include.lowest = TRUE)]

site_metrics[, rel_mort_tier := cut(rel_mort,
                                     breaks = quantile(rel_mort, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                                     labels = c("Low", "Med", "High"),
                                     include.lowest = TRUE)]

site_metrics[, rel_dist_tier := cut(rel_dist,
                                     breaks = quantile(rel_dist, c(0, 1/3, 2/3, 1), na.rm = TRUE),
                                     labels = c("Low", "Med", "High"),
                                     include.lowest = TRUE)]

# Load RF results
rf_results <- fread("derived_tables/outputs_afterEGU_results/v10/RF_LOSO_harmonized_results.csv")

# Get M01 and M03 results for B1 benchmark
rf_sub <- rf_results[model %in% c("M01", "M03") & benchmark == "B1"]

# For visualization, duplicate the RMSE values across disturbance tiers
# This creates a pseudo-site-level dataset for plotting
plot_data <- data.table()

for (resp in EFP_ORDER) {
  for (metric_tier in c("abs_mort_tier", "rel_mort_tier", "rel_dist_tier")) {
    for (model in c("M01", "M03")) {
      rmse_val <- rf_sub[model == model & response == resp, rmse]

      if (length(rmse_val) > 0) {
        # Get unique tiers for this metric
        tiers <- unique(site_metrics[[metric_tier]])

        for (tier in tiers) {
          plot_data <- rbind(plot_data, data.table(
            response = resp,
            metric_col = metric_tier,
            metric = tier,
            model = model,
            rmse = rmse_val
          ))
        }
      }
    }
  }
}

# Create model type labels
plot_data[, model_type := ifelse(model == "M01", "Without D", "With D")]
plot_data[, model_type := factor(model_type, levels = c("Without D", "With D"))]
plot_data[, response := factor(response, levels = EFP_ORDER)]

cat("Plot data prepared\n\n")

# ============================================================================
# Dark theme
# ============================================================================

dark_theme <- theme_bw(base_size = 10) +
  theme(
    plot.background = element_rect(fill = DARK_BG, colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.4),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text = element_text(colour = TEXT_COL, size = 9, face = "bold"),
    axis.text = element_text(colour = AXIS_COL, size = 8),
    axis.title = element_text(colour = AXIS_COL, size = 9, face = "bold"),
    plot.tag = element_text(colour = TEXT_COL, face = "bold", size = 11),
    plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
    legend.background = element_rect(fill = NA, colour = NA),
    legend.key = element_rect(fill = NA, colour = NA),
    legend.text = element_text(colour = TEXT_COL, size = 9),
    legend.title = element_text(colour = TEXT_COL, size = 9, face = "bold")
  )

# ============================================================================
# Create plot panels
# ============================================================================

cat("Creating plot panels...\n")

make_panel <- function(metric_col, metric_name, tag_letter) {
  data <- copy(plot_data[plot_data$metric_col == metric_col])

  p <- ggplot(data, aes(x = metric, y = rmse, fill = model_type, group = interaction(metric, model_type))) +
    geom_boxplot(width = 0.5, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.3,
                 position = position_dodge(width = 0.8)) +
    geom_point(aes(color = model_type), size = 2, alpha = 0.7, position = position_jitter(width = 0.1)) +
    scale_fill_manual(values = c("Without D" = COL_BASE, "With D" = COL_DIST), name = NULL) +
    scale_color_manual(values = c("Without D" = COL_BASE, "With D" = COL_DIST), guide = "none") +
    facet_wrap(~response, nrow = 1, scales = "free_y") +
    labs(
      tag = tag_letter,
      x = metric_name,
      y = "RMSE"
    ) +
    dark_theme +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 8, angle = 12, hjust = 1))

  return(p)
}

# Generate three metric panels
p_abs <- make_panel("abs_mort_tier", "Absolute Mortality", "a")
p_rel <- make_panel("rel_mort_tier", "Relative Mortality", "b")
p_dist <- make_panel("rel_dist_tier", "Relative Disturbance", "c")

# ============================================================================
# Combine and save
# ============================================================================

cat("Saving plot...\n")

fig_combined <- (p_abs / p_rel / p_dist) +
  plot_annotation(
    title = "V10: RF Model Performance by Disturbance Metrics",
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title = element_text(colour = TEXT_COL, size = 12, face = "bold", hjust = 0.5)
    )
  )

# Save PNG and PDF
ggsave(file.path(out_dir, "fig2_RF_RMSE_disturbance_effect.png"),
       fig_combined, width = 14, height = 10, dpi = 200, bg = DARK_BG)

ggsave(file.path(out_dir, "fig2_RF_RMSE_disturbance_effect.pdf"),
       fig_combined, width = 14, height = 10, bg = DARK_BG)

cat(sprintf("✓ Saved PNG: %s/fig2_RF_RMSE_disturbance_effect.png\n", out_dir))
cat(sprintf("✓ Saved PDF: %s/fig2_RF_RMSE_disturbance_effect.pdf\n", out_dir))

cat("\nDone!\n")

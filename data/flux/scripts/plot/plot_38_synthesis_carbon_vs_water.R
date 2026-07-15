#!/usr/bin/env Rscript
# Synthesis Plot: Carbon vs Water Fluxes - Delta RMSE by Disturbance Level
# Shows whether disturbance helps carbon but not water

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- "plots/disturbance_metric_test/synthesis"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

# Load data
cat("Loading data...\n")
predictions <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv")
cat_data <- fread("derived_tables/disturbance_metric_test/tertiles_method.csv")

# Calculate RMSE per site and model
predictions[, residual := (predicted - observed)^2]
metrics_site <- predictions[, .(rmse = sqrt(mean(residual, na.rm = TRUE))),
                             by = .(model, response, SITE_ID)]

# Extract window and model parts
metrics_site[, c("model_part", "window_part", "response") := tstrsplit(model, "_")]
metrics_site[, model := model_part]
metrics_site[, window := window_part]

# Classify EFPs
metrics_site[, efp_type := fcase(
  response %in% c("GPPsat", "NEPmax"), "Carbon",
  response %in% c("ETmax", "uWUE", "WUE"), "Water",
  default = "Other"
)]

# Merge with categorization
metrics_site <- merge(metrics_site, cat_data, by = "SITE_ID", all.x = TRUE)

# Calculate Delta RMSE for 24m window only
comparison_pairs <- list(c("M01", "M02"), c("M03", "M04"), c("M05", "M06"), c("M07", "M08"))

delta_data <- data.table()

for (pair in comparison_pairs) {
  m_without <- pair[1]
  m_with <- pair[2]

  data_without <- metrics_site[model == m_without & window == "24m", .(SITE_ID, rmse_without = rmse, response, efp_type)]
  data_with <- metrics_site[model == m_with & window == "24m", .(SITE_ID, rmse_with = rmse, response)]

  delta <- merge(data_without, data_with, by = c("SITE_ID", "response"))
  delta[, delta_rmse := rmse_with - rmse_without]
  delta[, model_comparison := paste0(m_with, " vs ", m_without)]

  delta_data <- rbindlist(list(delta_data, delta))
}

# Merge with categorization
delta_data <- merge(delta_data, cat_data[, .(SITE_ID, abs_mort_cat, rel_mort_cat, rel_dist_cat)],
                    by = "SITE_ID", all.x = TRUE)

cat("Creating synthesis plots...\n")

# Theme
dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border     = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text       = element_text(colour = TEXT_COL, size = 8, face = "bold"),
    axis.text        = element_text(colour = AXIS_COL, size = 7),
    axis.title       = element_text(colour = AXIS_COL, size = 8),
    plot.title       = element_text(colour = TEXT_COL, size = 11, face = "bold"),
    legend.position  = "bottom",
    legend.text      = element_text(colour = AXIS_COL, size = 7),
    legend.title     = element_text(colour = AXIS_COL, size = 7)
  )

# Create data for heatmap: Mean Delta RMSE by EFP × Disturbance Category
heatmap_data <- delta_data[, .(mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
                                sd_delta_rmse = sd(delta_rmse, na.rm = TRUE),
                                n = .N),
                           by = .(response, abs_mort_cat, efp_type)]

# Reorder categories
heatmap_data[, abs_mort_cat := factor(abs_mort_cat,
                                      levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
heatmap_data[, response := factor(response, levels = c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE"))]
heatmap_data[, efp_type := factor(efp_type, levels = c("Carbon", "Water"))]

# Color scale: Red (positive = bad), White (zero), Green (negative = good)
p_heatmap <- ggplot(heatmap_data, aes(x = abs_mort_cat, y = response, fill = mean_delta_rmse)) +
  geom_tile(colour = AXIS_COL, linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.2f", mean_delta_rmse)),
            colour = TEXT_COL, size = 2.5) +
  scale_fill_gradient2(low = "#2ecc71", mid = "#f5f5f5", high = "#e74c3c",
                       midpoint = 0,
                       name = "Mean ΔRMSE") +
  facet_wrap(~efp_type, ncol = 2, scales = "free_y") +
  labs(
    title = "Delta RMSE Heatmap: Carbon vs Water Fluxes",
    subtitle = "Stratified by Absolute Mortality (Tertiles)",
    x = "Disturbance Level",
    y = "EFP Variable"
  ) +
  dark_theme +
  theme(
    axis.text.x = element_text(angle = 20, hjust = 1),
    panel.grid = element_blank()
  )

ggsave(file.path(OUT_DIR, "01_delta_rmse_heatmap_carbon_vs_water.png"),
       p_heatmap, width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
cat("✓ Saved: 01_delta_rmse_heatmap_carbon_vs_water.png\n")

# --- Box plot version: 5 INDIVIDUAL PLOTS with independent scales ---
# Layout: 2 carbon plots on top (GPPsat, NEPmax)
#         3 water plots on bottom (ETmax, uWUE, WUE)

create_efp_plot <- function(data, efp_name, show_x_title = FALSE, show_y_title = TRUE) {
  p <- ggplot(data, aes(x = abs_mort_cat, y = delta_rmse, fill = abs_mort_cat)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
    geom_boxplot(outlier.shape = NA, colour = "white", linewidth = 0.3, alpha = 0.7) +
    geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = "white") +
    scale_fill_manual(values = c("Tertile 1 (Low)" = "#4DAECC",
                                 "Tertile 2 (Mid)" = "#F0A500",
                                 "Tertile 3 (High)" = "#E8257A"), guide = "none") +
    labs(
      title = efp_name,
      x = if(show_x_title) "Disturbance Level" else "",
      y = if(show_y_title) "ΔRMSE" else ""
    ) +
    dark_theme +
    theme(
      axis.text.x = element_text(angle = 20, hjust = 1, size = 6),
      axis.text.y = element_text(size = 6),
      plot.title = element_text(size = 9, colour = TEXT_COL, face = "bold"),
      axis.title.x = if(!show_x_title) element_blank() else element_text(size = 7),
      axis.title.y = if(!show_y_title) element_blank() else element_text(size = 7)
    )

  p
}

# Create 5 individual plots (each with independent y-scale)
p_gppsat <- create_efp_plot(delta_data[response == "GPPsat"], "GPPsat", show_x_title = FALSE, show_y_title = TRUE)
p_nepmax <- create_efp_plot(delta_data[response == "NEPmax"], "NEPmax", show_x_title = FALSE, show_y_title = FALSE)
p_etmax <- create_efp_plot(delta_data[response == "ETmax"], "ETmax", show_x_title = TRUE, show_y_title = TRUE)
p_uwue <- create_efp_plot(delta_data[response == "uWUE"], "uWUE", show_x_title = TRUE, show_y_title = FALSE)
p_wue <- create_efp_plot(delta_data[response == "WUE"], "WUE", show_x_title = TRUE, show_y_title = FALSE)

# Arrange with patchwork: 2 plots top row (carbon), 3 plots bottom row (water)
p_box <- (p_gppsat + p_nepmax + plot_spacer()) / (p_etmax + p_uwue + p_wue) +
  plot_layout(guides = 'collect', heights = c(1, 1)) +
  plot_annotation(
    title = "Delta RMSE Distribution: Carbon vs Water Fluxes by Disturbance Level",
    subtitle = "Each plot has INDEPENDENT y-axis scale. Top row: Carbon fluxes (GPPsat, NEPmax). Bottom row: Water fluxes (ETmax, uWUE, WUE).",
    theme = theme(
      plot.title = element_text(size = 11, face = "bold", colour = TEXT_COL, hjust = 0.5),
      plot.subtitle = element_text(size = 8, colour = AXIS_COL, hjust = 0.5),
      plot.background = element_rect(fill = DARK_BG, colour = NA)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

ggsave(file.path(OUT_DIR, "02_delta_rmse_boxplot_carbon_vs_water.png"),
       p_box, width = 280, height = 160, units = "mm", dpi = 300, bg = DARK_BG)
cat("✓ Saved: 02_delta_rmse_boxplot_carbon_vs_water.png\n")

# --- Summary statistics table ---
summary_stats <- delta_data[, .(
  mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
  median_delta_rmse = median(delta_rmse, na.rm = TRUE),
  sd_delta_rmse = sd(delta_rmse, na.rm = TRUE),
  n_negative = sum(delta_rmse < 0, na.rm = TRUE),
  pct_negative = round(sum(delta_rmse < 0, na.rm = TRUE) / .N * 100, 1),
  n_sites = .N
), by = .(efp_type, response, abs_mort_cat)]

cat("\n=== Summary: Delta RMSE by EFP Type and Disturbance ===\n")
print(summary_stats)

# Save summary
fwrite(summary_stats, file.path(OUT_DIR, "delta_rmse_summary_by_disturbance.csv"))

cat("\n✓ Analysis complete!\n")
cat("Outputs saved to:", OUT_DIR, "\n")

#!/usr/bin/env Rscript
# SHAP Direction Analysis: Signed SHAP (not absolute) to show positive vs negative direction
# Shows whether disturbance variables push predictions up or down

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

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

cat("Loading SHAP and prediction data...\n")
shap <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv")
predictions <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv")

# Keep M04 (C+T+D), 24m window, Disturbance group only
shap_m04 <- shap[grepl("^M04_24m_", model) & group == "Disturbance"]
shap_m04[, response := sub("M04_24m_", "", model)]

# Calculate absolute mean SHAP per site
shap_data <- shap_m04[, .(mean_abs_shap = mean(mean_abs_shap, na.rm = TRUE),
                          n_vars = .N),
                      by = .(SITE_ID = test_site, response)]

# Get predictions for M04 24m to infer direction (residuals)
predictions_m04 <- predictions[grepl("^M04_24m_", model)]
predictions_m04[, c("model_part", "window", "resp") := tstrsplit(model, "_")]
predictions_m04[, residual := predicted - observed]  # Positive = over-prediction, Negative = under-prediction

# Calculate mean residual per site (proxy for SHAP direction influence)
residuals <- predictions_m04[, .(mean_residual = mean(residual, na.rm = TRUE),
                                  abs_mean_residual = mean(abs(residual), na.rm = TRUE)),
                             by = .(SITE_ID, response = resp)]

# Merge
shap_signed <- merge(shap_data, residuals, by = c("SITE_ID", "response"))
setnames(shap_signed, "SITE_ID", "SITE_ID")

# Load categorization
cat_data <- fread("derived_tables/disturbance_metric_test/tertiles_method.csv")

# Merge
shap_signed <- merge(shap_signed, cat_data, by = "SITE_ID")
shap_signed[, response := factor(response, levels = EFP_ORDER)]

# Classify EFPs
shap_signed[, efp_type := fcase(
  response %in% c("GPPsat", "NEPmax"), "Carbon",
  response %in% c("ETmax", "uWUE", "WUE"), "Water",
  default = "Other"
)]

cat("Creating SHAP direction plots...\n")

dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border     = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    axis.text        = element_text(colour = AXIS_COL, size = 7.5),
    axis.title       = element_text(colour = AXIS_COL, size = 8),
    plot.title       = element_text(colour = TEXT_COL, size = 9, face = "bold"),
    plot.subtitle    = element_text(colour = AXIS_COL, size = 8)
  )

# Plot 1: Violin plot showing mean residual (prediction error direction)
# Positive residual = over-prediction (model predicts too high)
# This correlates with SHAP direction
# Five individual plots with independent y-scales
create_violin_plot <- function(data, efp_name, show_x_title = FALSE, show_y_title = TRUE) {
  p <- ggplot(data, aes(x = abs_mort_cat, y = mean_residual, fill = abs_mort_cat)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    scale_fill_manual(values = c("Tertile 1 (Low)" = "#4DAECC",
                                 "Tertile 2 (Mid)" = "#F0A500",
                                 "Tertile 3 (High)" = "#E8257A"), guide = "none") +
    labs(
      title = efp_name,
      x = if(show_x_title) "Disturbance Level" else "",
      y = if(show_y_title) "Mean Residual" else ""
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

# Create 5 individual plots
p_gppsat <- create_violin_plot(shap_signed[response == "GPPsat"], "GPPsat", show_x_title = FALSE, show_y_title = TRUE)
p_nepmax <- create_violin_plot(shap_signed[response == "NEPmax"], "NEPmax", show_x_title = FALSE, show_y_title = FALSE)
p_etmax <- create_violin_plot(shap_signed[response == "ETmax"], "ETmax", show_x_title = TRUE, show_y_title = TRUE)
p_uwue <- create_violin_plot(shap_signed[response == "uWUE"], "uWUE", show_x_title = TRUE, show_y_title = FALSE)
p_wue <- create_violin_plot(shap_signed[response == "WUE"], "WUE", show_x_title = TRUE, show_y_title = FALSE)

# Arrange with patchwork: 2 plots top row (carbon), 3 plots bottom row (water)
p1 <- (p_gppsat + p_nepmax + plot_spacer()) / (p_etmax + p_uwue + p_wue) +
  plot_layout(guides = 'collect', heights = c(1, 1)) +
  plot_annotation(
    title = "Prediction Direction: Mean Residual by Disturbance Level",
    subtitle = "Each plot has INDEPENDENT y-axis scale. Negative residual = over-prediction. Top: Carbon fluxes. Bottom: Water fluxes.",
    theme = theme(
      plot.title = element_text(size = 11, face = "bold", colour = TEXT_COL, hjust = 0.5),
      plot.subtitle = element_text(size = 8, colour = AXIS_COL, hjust = 0.5),
      plot.background = element_rect(fill = DARK_BG, colour = NA)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

ggsave(file.path(OUT_DIR, "03_shap_direction_violin.png"),
       p1, width = 320, height = 160, units = "mm", dpi = 300, bg = DARK_BG)
cat("✓ Saved: 03_shap_direction_violin.png\n")

# Plot 2: Heatmap of mean residual (prediction direction)
heatmap_shap <- shap_signed[, .(mean_residual = mean(mean_residual, na.rm = TRUE)),
                             by = .(response, abs_mort_cat, efp_type)]

heatmap_shap[, abs_mort_cat := factor(abs_mort_cat,
                                      levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
heatmap_shap[, response := factor(response, levels = EFP_ORDER)]

# Find range for symmetric scale
max_val <- max(abs(heatmap_shap$mean_residual), na.rm = TRUE)

p2 <- ggplot(heatmap_shap, aes(x = abs_mort_cat, y = response, fill = mean_residual)) +
  geom_tile(colour = AXIS_COL, linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.3f", mean_residual)),
            colour = TEXT_COL, size = 2.5) +
  scale_fill_gradient2(low = "#2ecc71", mid = "#f5f5f5", high = "#e74c3c",
                       midpoint = 0,
                       limits = c(-max_val, max_val),
                       name = "Mean Residual") +
  facet_wrap(~efp_type, ncol = 2, scales = "free_y") +
  labs(
    title = "Prediction Error Direction Heatmap",
    subtitle = "Red = over-prediction (negative residual) | Green = under-prediction (positive residual)",
    x = "Disturbance Level",
    y = "EFP Variable"
  ) +
  dark_theme +
  theme(
    axis.text.x = element_text(angle = 20, hjust = 1),
    panel.grid = element_blank()
  )

ggsave(file.path(OUT_DIR, "04_shap_direction_heatmap.png"),
       p2, width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
cat("✓ Saved: 04_shap_direction_heatmap.png\n")

# Plot 3: Relationship between SHAP magnitude and prediction error direction
shap_comparison <- shap_signed[, .(mean_residual = mean(mean_residual, na.rm = TRUE),
                                   mean_abs_shap = mean(mean_abs_shap, na.rm = TRUE)),
                               by = .(response, abs_mort_cat)]

shap_comparison[, abs_mort_cat := factor(abs_mort_cat,
                                         levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
shap_comparison[, response := factor(response, levels = EFP_ORDER)]

p3 <- ggplot(shap_comparison) +
  geom_point(aes(x = mean_abs_shap, y = mean_residual, colour = response, size = 3), alpha = 0.7) +
  geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
  scale_colour_manual(values = c(
    "GPPsat" = "#1f77b4", "NEPmax" = "#ff7f0e", "ETmax" = "#2ca02c",
    "uWUE" = "#d62728", "WUE" = "#9467bd"
  )) +
  labs(
    title = "SHAP Magnitude vs Prediction Direction",
    subtitle = "X = how important disturbance variables are; Y = whether they push predictions up or down",
    x = "Mean |SHAP| (Disturbance Importance)",
    y = "Mean Residual (Prediction Direction)",
    colour = "EFP"
  ) +
  dark_theme +
  theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "05_shap_signed_vs_absolute.png"),
       p3, width = 160, height = 120, units = "mm", dpi = 300, bg = DARK_BG)
cat("✓ Saved: 05_shap_signed_vs_absolute.png\n")

# Summary statistics
summary_shap <- shap_signed[, .(
  mean_residual = mean(mean_residual, na.rm = TRUE),
  mean_abs_shap = mean(mean_abs_shap, na.rm = TRUE),
  sd_residual = sd(mean_residual, na.rm = TRUE),
  n_sites = .N,
  pct_overprediction = round(sum(mean_residual < 0, na.rm = TRUE) / .N * 100, 1),
  pct_underprediction = round(sum(mean_residual > 0, na.rm = TRUE) / .N * 100, 1)
), by = .(efp_type, response, abs_mort_cat)]

cat("\n=== Summary: Prediction Direction by EFP and Disturbance ===\n")
print(summary_shap)

fwrite(summary_shap, file.path(OUT_DIR, "shap_direction_summary_by_disturbance.csv"))

cat("\n✓ Analysis complete!\n")
cat("Key interpretation:\n")
cat("  • If Mean Residual is NEGATIVE → model OVER-predicts (predicts too high)\n")
cat("  • If Mean Residual is POSITIVE → model UNDER-predicts (predicts too low)\n")
cat("  • HIGH Mean |SHAP| + POSITIVE Mean Residual → disturbance helps (corrects under-prediction)\n")
cat("  • HIGH Mean |SHAP| + NEGATIVE Mean Residual → disturbance hurts (worsens over-prediction)\n")

#!/usr/bin/env Rscript
# Mechanism Evidence: Dose-Response Relationship
# Shows continuous relationship between disturbance intensity and Delta RMSE

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

cat("Loading data...\n")
predictions <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv")
cat_data <- fread("derived_tables/disturbance_metric_test/tertiles_method.csv")

# Calculate RMSE
predictions[, residual := (predicted - observed)^2]
metrics_site <- predictions[, .(rmse = sqrt(mean(residual, na.rm = TRUE))),
                             by = .(model, response, SITE_ID)]

# Extract parts
metrics_site[, c("model_part", "window_part", "response") := tstrsplit(model, "_")]
metrics_site[, model := model_part]
metrics_site[, window := window_part]

# Classify EFPs
metrics_site[, efp_type := fcase(
  response %in% c("GPPsat", "NEPmax"), "Carbon",
  response %in% c("ETmax", "uWUE", "WUE"), "Water",
  default = "Other"
)]

# Merge with categorization (get continuous disturbance values)
metrics_site <- merge(metrics_site, cat_data[, .(SITE_ID, abs_mort, rel_mort, rel_dist)],
                      by = "SITE_ID", all.x = TRUE)

# Calculate Delta RMSE for 24m
comparison_pairs <- list(c("M01", "M02"), c("M03", "M04"), c("M05", "M06"), c("M07", "M08"))

delta_data <- data.table()

for (pair in comparison_pairs) {
  m_without <- pair[1]
  m_with <- pair[2]

  data_without <- metrics_site[model == m_without & window == "24m", .(SITE_ID, rmse_without = rmse, response, efp_type)]
  data_with <- metrics_site[model == m_with & window == "24m", .(SITE_ID, rmse_with = rmse, response)]

  delta <- merge(data_without, data_with, by = c("SITE_ID", "response"))
  delta[, delta_rmse := rmse_with - rmse_without]

  delta_data <- rbindlist(list(delta_data, delta))
}

# Merge with continuous disturbance
delta_data <- merge(delta_data, cat_data[, .(SITE_ID, abs_mort, rel_mort, rel_dist)],
                    by = "SITE_ID", all.x = TRUE)

cat("Creating dose-response plots...\n")

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
    plot.subtitle    = element_text(colour = AXIS_COL, size = 8),
    legend.text      = element_text(colour = AXIS_COL, size = 7),
    legend.title     = element_text(colour = AXIS_COL, size = 7)
  )

# Helper function to create dose-response plots for any metric
create_doseresponse_plots <- function(metric_name, metric_col, threshold_5pct,
                                      x_label_disturbed, x_label_nondisturbed, x_label_full,
                                      out_dir) {
  # Filter by threshold (5% of metric distribution)
  disturbed_sites <- delta_data[get(metric_col) > threshold_5pct]
  nondisturbed_sites <- delta_data[get(metric_col) <= threshold_5pct]

  # --- PANEL 1: Disturbance Sites Only ---
  p1 <- ggplot(disturbed_sites, aes(x = get(metric_col), y = delta_rmse, colour = response)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
    geom_point(alpha = 0.5, size = 2) +
    geom_smooth(se = TRUE, method = "loess", alpha = 0.2, linewidth = 1) +
    scale_colour_manual(values = c(
      "GPPsat" = "#1f77b4", "NEPmax" = "#ff7f0e", "ETmax" = "#2ca02c",
      "uWUE" = "#d62728", "WUE" = "#9467bd"
    )) +
    facet_wrap(~efp_type, scales = "free") +
    labs(
      title = "Mechanism 1: Disturbed Sites Only",
      subtitle = sprintf("Sites with %s > %.2f%%", metric_name, threshold_5pct),
      x = x_label_disturbed,
      y = "ΔRMSE",
      colour = "EFP"
    ) +
    dark_theme

  # --- PANEL 2: Non-Disturbed Sites ---
  p2 <- ggplot(nondisturbed_sites, aes(x = get(metric_col), y = delta_rmse, colour = response)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
    geom_point(alpha = 0.5, size = 2) +
    geom_smooth(se = TRUE, method = "loess", alpha = 0.2, linewidth = 1) +
    scale_colour_manual(values = c(
      "GPPsat" = "#1f77b4", "NEPmax" = "#ff7f0e", "ETmax" = "#2ca02c",
      "uWUE" = "#d62728", "WUE" = "#9467bd"
    )) +
    facet_wrap(~efp_type, scales = "free") +
    labs(
      title = "Mechanism 2: Non-Disturbed Sites",
      subtitle = sprintf("Sites with %s ≤ %.2f%% (low/no disturbance)", metric_name, threshold_5pct),
      x = x_label_nondisturbed,
      y = "ΔRMSE",
      colour = "EFP"
    ) +
    dark_theme

  # --- PANEL 3: All Sites - Dose Response ---
  p3 <- ggplot(delta_data, aes(x = get(metric_col), y = delta_rmse, colour = efp_type)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
    geom_vline(xintercept = threshold_5pct, colour = "#666666", linewidth = 0.8, linetype = "dotted", alpha = 0.5) +
    geom_point(alpha = 0.3, size = 1.5) +
    geom_smooth(se = TRUE, method = "loess", linewidth = 1.2, alpha = 0.15) +
    scale_colour_manual(values = c("Carbon" = "#f39c12", "Water" = "#3498db"), name = "EFP Type") +
    labs(
      title = "Mechanism 3: Full Dose-Response (All Sites)",
      subtitle = sprintf("Vertical line at %.2f%% shows disturbance threshold", threshold_5pct),
      x = x_label_full,
      y = "ΔRMSE",
      colour = "EFP Type"
    ) +
    dark_theme

  # Combine and save
  combined <- (p1 / p2 / p3) +
    plot_annotation(
      title = sprintf("Mechanism Evidence (%s): How does disturbance impact Delta RMSE?", metric_name),
      theme = theme(plot.title = element_text(face = "bold", size = 13, hjust = 0.5),
                    plot.background = element_rect(fill = DARK_BG, colour = NA))
    ) &
    theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

  ggsave(file.path(out_dir, "mechanism_doseresponse.png"),
         combined, width = 280, height = 220, units = "mm", dpi = 300, bg = DARK_BG)
  cat(sprintf("✓ Saved: %s/mechanism_doseresponse.png\n", out_dir))

  return(list(disturbed = disturbed_sites, nondisturbed = nondisturbed_sites))
}

# --- CALCULATE THRESHOLDS (5% of each distribution) ---
threshold_abs <- quantile(delta_data$abs_mort, 0.05, na.rm = TRUE)
threshold_rel_mort <- quantile(delta_data$rel_mort, 0.05, na.rm = TRUE)
threshold_rel_dist <- quantile(delta_data$rel_dist, 0.05, na.rm = TRUE)

cat(sprintf("Using 5th percentile thresholds:\n"))
cat(sprintf("  Absolute Mortality: %.2f%%\n", threshold_abs))
cat(sprintf("  Relative Mortality: %.2f%%\n", threshold_rel_mort))
cat(sprintf("  Relative Disturbance: %.2f%%\n", threshold_rel_dist))

# --- GENERATE SEPARATE ANALYSIS FOR EACH METRIC ---
out_abs <- "plots/disturbance_metric_test/abs_mort_analysis"
dir.create(out_abs, showWarnings = FALSE, recursive = TRUE)

out_rel_mort <- "plots/disturbance_metric_test/rel_mort_analysis"
dir.create(out_rel_mort, showWarnings = FALSE, recursive = TRUE)

out_rel_dist <- "plots/disturbance_metric_test/rel_dist_analysis"
dir.create(out_rel_dist, showWarnings = FALSE, recursive = TRUE)

# 1. Absolute Mortality
cat("\n╔════════════════════════════════════════════════════════════╗\n")
cat("║ ABSOLUTE MORTALITY ANALYSIS                                ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
result_abs <- create_doseresponse_plots(
  "Absolute Mortality",
  "abs_mort",
  threshold_abs,
  "Absolute Mortality (%)",
  "Absolute Mortality (%)",
  "Absolute Mortality (%) - Continuous",
  out_abs
)

# 2. Relative Mortality
cat("\n╔════════════════════════════════════════════════════════════╗\n")
cat("║ RELATIVE MORTALITY ANALYSIS                                ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
result_rel_mort <- create_doseresponse_plots(
  "Relative Mortality",
  "rel_mort",
  threshold_rel_mort,
  "Relative Mortality (%)",
  "Relative Mortality (%)",
  "Relative Mortality (%) - Continuous",
  out_rel_mort
)

# 3. Relative Disturbance
cat("\n╔════════════════════════════════════════════════════════════╗\n")
cat("║ RELATIVE DISTURBANCE ANALYSIS                              ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
result_rel_dist <- create_doseresponse_plots(
  "Relative Disturbance",
  "rel_dist",
  threshold_rel_dist,
  "Relative Disturbance (%)",
  "Relative Disturbance (%)",
  "Relative Disturbance (%) - Continuous",
  out_rel_dist
)

# --- Summary Statistics for EACH METRIC ---
# Absolute Mortality
summary_abs_disturbed <- result_abs$disturbed[, .(
  mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
  median_delta_rmse = median(delta_rmse, na.rm = TRUE),
  n_sites = .N,
  pct_improvement = round(sum(delta_rmse < 0, na.rm = TRUE) / .N * 100, 1)
), by = .(efp_type, response)]

summary_abs_nondisturbed <- result_abs$nondisturbed[, .(
  mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
  median_delta_rmse = median(delta_rmse, na.rm = TRUE),
  n_sites = .N,
  pct_improvement = round(sum(delta_rmse < 0, na.rm = TRUE) / .N * 100, 1)
), by = .(efp_type, response)]

cat("\n=== DISTURBED SITES (Abs Mort >", round(threshold_abs, 2), "%) ===\n")
print(summary_abs_disturbed)
cat("\n=== NON-DISTURBED SITES (Abs Mort ≤", round(threshold_abs, 2), "%) ===\n")
print(summary_abs_nondisturbed)

fwrite(summary_abs_disturbed, file.path(out_abs, "disturbed_sites_summary.csv"))
fwrite(summary_abs_nondisturbed, file.path(out_abs, "nondisturbed_sites_summary.csv"))

# Relative Mortality
summary_rel_mort_disturbed <- result_rel_mort$disturbed[, .(
  mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
  median_delta_rmse = median(delta_rmse, na.rm = TRUE),
  n_sites = .N,
  pct_improvement = round(sum(delta_rmse < 0, na.rm = TRUE) / .N * 100, 1)
), by = .(efp_type, response)]

summary_rel_mort_nondisturbed <- result_rel_mort$nondisturbed[, .(
  mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
  median_delta_rmse = median(delta_rmse, na.rm = TRUE),
  n_sites = .N,
  pct_improvement = round(sum(delta_rmse < 0, na.rm = TRUE) / .N * 100, 1)
), by = .(efp_type, response)]

cat("\n=== DISTURBED SITES (Rel Mort >", round(threshold_rel_mort, 2), "%) ===\n")
print(summary_rel_mort_disturbed)
cat("\n=== NON-DISTURBED SITES (Rel Mort ≤", round(threshold_rel_mort, 2), "%) ===\n")
print(summary_rel_mort_nondisturbed)

fwrite(summary_rel_mort_disturbed, file.path(out_rel_mort, "disturbed_sites_summary.csv"))
fwrite(summary_rel_mort_nondisturbed, file.path(out_rel_mort, "nondisturbed_sites_summary.csv"))

# Relative Disturbance
summary_rel_dist_disturbed <- result_rel_dist$disturbed[, .(
  mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
  median_delta_rmse = median(delta_rmse, na.rm = TRUE),
  n_sites = .N,
  pct_improvement = round(sum(delta_rmse < 0, na.rm = TRUE) / .N * 100, 1)
), by = .(efp_type, response)]

summary_rel_dist_nondisturbed <- result_rel_dist$nondisturbed[, .(
  mean_delta_rmse = mean(delta_rmse, na.rm = TRUE),
  median_delta_rmse = median(delta_rmse, na.rm = TRUE),
  n_sites = .N,
  pct_improvement = round(sum(delta_rmse < 0, na.rm = TRUE) / .N * 100, 1)
), by = .(efp_type, response)]

cat("\n=== DISTURBED SITES (Rel Dist >", round(threshold_rel_dist, 2), "%) ===\n")
print(summary_rel_dist_disturbed)
cat("\n=== NON-DISTURBED SITES (Rel Dist ≤", round(threshold_rel_dist, 2), "%) ===\n")
print(summary_rel_dist_nondisturbed)

fwrite(summary_rel_dist_disturbed, file.path(out_rel_dist, "disturbed_sites_summary.csv"))
fwrite(summary_rel_dist_nondisturbed, file.path(out_rel_dist, "nondisturbed_sites_summary.csv"))

cat("\n✓ Analysis complete!\n")
cat("Key hypothesis test:\n")
cat("  IF hypothesis is correct:\n")
cat("    • Carbon fluxes should improve (negative ΔRMSE) at HIGH disturbance\n")
cat("    • Water fluxes should show NO improvement regardless of disturbance\n")
cat("    • Effect should be strongest in disturbed sites, weak in undisturbed\n")

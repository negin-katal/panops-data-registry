library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- "plots/manuscript_candidates"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

# Load v3 harmonized dataset
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

# Get common sites from M06 and M08 SHAP data (164 sites)
shap_m06 <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06.csv")
shap_m08 <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv")[grepl("^M08_", model)]

m06_sites <- unique(shap_m06$test_site)
m08_sites <- unique(shap_m08$test_site)
common_sites <- intersect(m06_sites, m08_sites)

cat("M06 sites:", length(m06_sites), "\n")
cat("M08 sites:", length(m08_sites), "\n")
cat("Common sites:", length(common_sites), "\n\n")

# Calculate site-level metrics (only for common sites)
site_metrics <- main_data[SITE_ID %in% common_sites, .(
  abs_mort = mean(deadwood_mean_pct_500m, na.rm = TRUE),
  rel_mort = mean((deadwood_mean_pct_500m / forest_mean_pct_500m * 100), na.rm = TRUE),
  rel_dist = mean(((deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
                    (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100), na.rm = TRUE)
), by = SITE_ID]

# Remove NAs and Infs
site_metrics <- site_metrics[is.finite(abs_mort) & is.finite(rel_mort) & is.finite(rel_dist)]

# Calculate quantile thresholds (33.33 and 66.67 percentiles for tertiles)
abs_mort_q33 <- as.numeric(quantile(site_metrics$abs_mort, 0.3333, na.rm = TRUE))
abs_mort_q67 <- as.numeric(quantile(site_metrics$abs_mort, 0.6667, na.rm = TRUE))

rel_mort_q33 <- as.numeric(quantile(site_metrics$rel_mort, 0.3333, na.rm = TRUE))
rel_mort_q67 <- as.numeric(quantile(site_metrics$rel_mort, 0.6667, na.rm = TRUE))

rel_dist_q33 <- as.numeric(quantile(site_metrics$rel_dist, 0.3333, na.rm = TRUE))
rel_dist_q67 <- as.numeric(quantile(site_metrics$rel_dist, 0.6667, na.rm = TRUE))

cat("=== QUANTILE THRESHOLDS ===\n\n")
cat("Absolute Mortality Quantiles:\n")
cat("  Q33 (tertile 1/2 boundary):", sprintf("%.2f", abs_mort_q33), "%\n")
cat("  Q67 (tertile 2/3 boundary):", sprintf("%.2f", abs_mort_q67), "%\n\n")

cat("Relative Mortality Quantiles:\n")
cat("  Q33 (tertile 1/2 boundary):", sprintf("%.2f", rel_mort_q33), "%\n")
cat("  Q67 (tertile 2/3 boundary):", sprintf("%.2f", rel_mort_q67), "%\n\n")

cat("Relative Disturbance Quantiles:\n")
cat("  Q33 (tertile 1/2 boundary):", sprintf("%.2f", rel_dist_q33), "%\n")
cat("  Q67 (tertile 2/3 boundary):", sprintf("%.2f", rel_dist_q67), "%\n\n")

# Create quantile categories (tertiles)
site_metrics[, abs_mort_tertile := fcase(
  abs_mort <= abs_mort_q33,  "Tertile 1 (Low)",
  abs_mort <= abs_mort_q67,  "Tertile 2 (Mid)",
  default =                   "Tertile 3 (High)"
)]

site_metrics[, rel_mort_tertile := fcase(
  rel_mort <= rel_mort_q33,  "Tertile 1 (Low)",
  rel_mort <= rel_mort_q67,  "Tertile 2 (Mid)",
  default =                   "Tertile 3 (High)"
)]

site_metrics[, rel_dist_tertile := fcase(
  rel_dist <= rel_dist_q33,  "Tertile 1 (Low)",
  rel_dist <= rel_dist_q67,  "Tertile 2 (Mid)",
  default =                   "Tertile 3 (High)"
)]

# Factor levels
site_metrics[, abs_mort_tertile := factor(abs_mort_tertile, levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
site_metrics[, rel_mort_tertile := factor(rel_mort_tertile, levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
site_metrics[, rel_dist_tertile := factor(rel_dist_tertile, levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]

# Theme
dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border     = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    axis.text        = element_text(colour = AXIS_COL, size = 7.5),
    axis.title       = element_text(colour = AXIS_COL, size = 8.5),
    plot.title       = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle    = element_text(colour = AXIS_COL, size = 8)
  )

# Color palette for tertiles
TERTILE_COLS <- c(
  "Tertile 1 (Low)"  = "#4DAECC",
  "Tertile 2 (Mid)"  = "#F0A500",
  "Tertile 3 (High)" = "#E8257A"
)

# Plot 1: Absolute Mortality with Tertile Overlay
p1 <- ggplot(site_metrics, aes(x = abs_mort, fill = abs_mort_tertile)) +
  geom_histogram(bins = 30, alpha = 0.7, colour = TEXT_COL, linewidth = 0.3) +
  geom_vline(aes(xintercept = abs_mort_q33),
             colour = "#FFFFFF", linewidth = 0.8, linetype = "dashed") +
  geom_vline(aes(xintercept = abs_mort_q67),
             colour = "#FFFFFF", linewidth = 0.8, linetype = "dashed") +
  scale_fill_manual(values = TERTILE_COLS, name = "Category") +
  labs(title = "Absolute Mortality Tertile Distribution",
       subtitle = sprintf("Q33 = %.2f%%, Q67 = %.2f%% | n = %d sites", abs_mort_q33, abs_mort_q67, nrow(site_metrics)),
       x = "Absolute Mortality (deadwood, %)", y = "Frequency") +
  dark_theme +
  theme(legend.position = "right")

# Plot 2: Relative Mortality with Tertile Overlay
p2 <- ggplot(site_metrics, aes(x = rel_mort, fill = rel_mort_tertile)) +
  geom_histogram(bins = 30, alpha = 0.7, colour = TEXT_COL, linewidth = 0.3) +
  geom_vline(aes(xintercept = rel_mort_q33),
             colour = "#FFFFFF", linewidth = 0.8, linetype = "dashed") +
  geom_vline(aes(xintercept = rel_mort_q67),
             colour = "#FFFFFF", linewidth = 0.8, linetype = "dashed") +
  scale_fill_manual(values = TERTILE_COLS, name = "Category") +
  labs(title = "Relative Mortality Tertile Distribution",
       subtitle = sprintf("Q33 = %.2f%%, Q67 = %.2f%% | n = %d sites", rel_mort_q33, rel_mort_q67, nrow(site_metrics)),
       x = "Relative Mortality (deadwood / forest × 100, %)", y = "Frequency") +
  dark_theme +
  theme(legend.position = "right")

# Plot 3: Relative Disturbance with Tertile Overlay
p3 <- ggplot(site_metrics, aes(x = rel_dist, fill = rel_dist_tertile)) +
  geom_histogram(bins = 30, alpha = 0.7, colour = TEXT_COL, linewidth = 0.3) +
  geom_vline(aes(xintercept = rel_dist_q33),
             colour = "#FFFFFF", linewidth = 0.8, linetype = "dashed") +
  geom_vline(aes(xintercept = rel_dist_q67),
             colour = "#FFFFFF", linewidth = 0.8, linetype = "dashed") +
  scale_fill_manual(values = TERTILE_COLS, name = "Category") +
  labs(title = "Relative Disturbance Tertile Distribution",
       subtitle = sprintf("Q33 = %.2f%%, Q67 = %.2f%% | n = %d sites", rel_dist_q33, rel_dist_q67, nrow(site_metrics)),
       x = "Relative Disturbance ((deadwood + loss) / (forest + loss) × 100, %)", y = "Frequency") +
  dark_theme +
  theme(legend.position = "right")

# Combine plots
fig_combined <- (p1 / p2 / p3) +
  plot_annotation(
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

stem <- file.path(OUT_DIR, "mortality_metrics_tertiles")
ggsave(paste0(stem, ".png"), fig_combined,
       width = 220, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig_combined,
       width = 220, height = 240, units = "mm", bg = DARK_BG)

cat("\n=== Figure saved ===\n")
cat("PNG:", paste0(stem, ".png\n"))
cat("PDF:", paste0(stem, ".pdf\n"))

# Save quantile categories to CSV for later use
site_metrics_export <- site_metrics[, .(SITE_ID, abs_mort, rel_mort, rel_dist,
                                        abs_mort_tertile, rel_mort_tertile, rel_dist_tertile)]

export_path <- "derived_tables/site_mortality_tertiles_v3.csv"
fwrite(site_metrics_export, export_path)
cat("\n=== Tertile categories saved ===\n")
cat("File:", export_path, "\n")
cat("Rows:", nrow(site_metrics_export), "\n")

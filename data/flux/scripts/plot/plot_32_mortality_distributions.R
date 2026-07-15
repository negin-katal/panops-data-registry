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

# Calculate site-level metrics
site_metrics <- main_data[, .(
  abs_mort = mean(deadwood_mean_pct_500m, na.rm = TRUE),
  rel_mort = mean((deadwood_mean_pct_500m / forest_mean_pct_500m * 100), na.rm = TRUE),
  rel_dist = mean(((deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
                    (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100), na.rm = TRUE)
), by = SITE_ID]

# Remove NAs and Infs
site_metrics <- site_metrics[is.finite(abs_mort) & is.finite(rel_mort) & is.finite(rel_dist)]

cat("Absolute Mortality stats:\n")
print(site_metrics[, .(
  min = min(abs_mort, na.rm = TRUE),
  q25 = quantile(abs_mort, 0.25, na.rm = TRUE),
  median = median(abs_mort, na.rm = TRUE),
  q75 = quantile(abs_mort, 0.75, na.rm = TRUE),
  max = max(abs_mort, na.rm = TRUE),
  mean = mean(abs_mort, na.rm = TRUE)
)])

cat("\nRelative Mortality stats:\n")
print(site_metrics[, .(
  min = min(rel_mort, na.rm = TRUE),
  q25 = quantile(rel_mort, 0.25, na.rm = TRUE),
  median = median(rel_mort, na.rm = TRUE),
  q75 = quantile(rel_mort, 0.75, na.rm = TRUE),
  max = max(rel_mort, na.rm = TRUE),
  mean = mean(rel_mort, na.rm = TRUE)
)])

cat("\nRelative Disturbance stats:\n")
print(site_metrics[, .(
  min = min(rel_dist, na.rm = TRUE),
  q25 = quantile(rel_dist, 0.25, na.rm = TRUE),
  median = median(rel_dist, na.rm = TRUE),
  q75 = quantile(rel_dist, 0.75, na.rm = TRUE),
  max = max(rel_dist, na.rm = TRUE),
  mean = mean(rel_dist, na.rm = TRUE)
)])

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

# Plot 1: Absolute Mortality
p1 <- ggplot(site_metrics, aes(x = abs_mort)) +
  geom_histogram(bins = 30, fill = "#4DAECC", alpha = 0.7, colour = TEXT_COL, linewidth = 0.3) +
  geom_vline(aes(xintercept = median(abs_mort, na.rm = TRUE)),
             colour = "#E8257A", linewidth = 1, linetype = "dashed", label = "Median") +
  geom_vline(aes(xintercept = quantile(abs_mort, 0.33, na.rm = TRUE)),
             colour = "#F0A500", linewidth = 0.8, linetype = "dotted", label = "33rd percentile") +
  geom_vline(aes(xintercept = quantile(abs_mort, 0.67, na.rm = TRUE)),
             colour = "#F0A500", linewidth = 0.8, linetype = "dotted", label = "67th percentile") +
  labs(title = "Distribution of Absolute Mortality (%)",
       subtitle = sprintf("n = %d sites", nrow(site_metrics)),
       x = "Absolute Mortality (deadwood, %)", y = "Frequency") +
  dark_theme

# Plot 2: Relative Mortality
p2 <- ggplot(site_metrics, aes(x = rel_mort)) +
  geom_histogram(bins = 30, fill = "#3DBDAA", alpha = 0.7, colour = TEXT_COL, linewidth = 0.3) +
  geom_vline(aes(xintercept = median(rel_mort, na.rm = TRUE)),
             colour = "#E8257A", linewidth = 1, linetype = "dashed", label = "Median") +
  geom_vline(aes(xintercept = quantile(rel_mort, 0.33, na.rm = TRUE)),
             colour = "#F0A500", linewidth = 0.8, linetype = "dotted", label = "33rd percentile") +
  geom_vline(aes(xintercept = quantile(rel_mort, 0.67, na.rm = TRUE)),
             colour = "#F0A500", linewidth = 0.8, linetype = "dotted", label = "67th percentile") +
  labs(title = "Distribution of Relative Mortality (%)",
       subtitle = sprintf("n = %d sites", nrow(site_metrics)),
       x = "Relative Mortality (deadwood / forest × 100, %)", y = "Frequency") +
  dark_theme

# Plot 3: Relative Disturbance
p3 <- ggplot(site_metrics, aes(x = rel_dist)) +
  geom_histogram(bins = 30, fill = "#D4A017", alpha = 0.7, colour = TEXT_COL, linewidth = 0.3) +
  geom_vline(aes(xintercept = median(rel_dist, na.rm = TRUE)),
             colour = "#E8257A", linewidth = 1, linetype = "dashed", label = "Median") +
  geom_vline(aes(xintercept = quantile(rel_dist, 0.33, na.rm = TRUE)),
             colour = "#F0A500", linewidth = 0.8, linetype = "dotted", label = "33rd percentile") +
  geom_vline(aes(xintercept = quantile(rel_dist, 0.67, na.rm = TRUE)),
             colour = "#F0A500", linewidth = 0.8, linetype = "dotted", label = "67th percentile") +
  labs(title = "Distribution of Relative Disturbance (%)",
       subtitle = sprintf("n = %d sites", nrow(site_metrics)),
       x = "Relative Disturbance ((deadwood + loss) / (forest + loss) × 100, %)", y = "Frequency") +
  dark_theme

# Combine plots
fig_combined <- (p1 / p2 / p3) +
  plot_annotation(
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

stem <- file.path(OUT_DIR, "mortality_metrics_distributions")
ggsave(paste0(stem, ".png"), fig_combined,
       width = 220, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig_combined,
       width = 220, height = 240, units = "mm", bg = DARK_BG)

cat("\n=== Figure saved ===\n")
cat("PNG:", paste0(stem, ".png\n"))
cat("PDF:", paste0(stem, ".pdf\n"))

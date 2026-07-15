#!/usr/bin/env Rscript
# Master script to regenerate all plots for all categorization methods

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

# ── Configuration ─────────────────────────────────────────────────────────────
METHODS <- c("tertiles_method", "equal_width_method", "natural_breaks_method")
OUT_BASE <- "plots/disturbance_metric_test"

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

# ── Helper: Create dark theme ──────────────────────────────────────────────────
get_dark_theme <- function() {
  theme_bw(base_size = 9) +
    theme(
      plot.background  = element_rect(fill = DARK_BG,  colour = NA),
      panel.background = element_rect(fill = PANEL_BG, colour = NA),
      panel.border     = element_rect(colour = GRID_COL, fill = NA),
      panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
      panel.grid.minor = element_blank(),
      strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
      strip.text       = element_text(colour = TEXT_COL, size = 8, face = "bold"),
      axis.text        = element_text(colour = AXIS_COL, size = 7.5),
      axis.title       = element_text(colour = AXIS_COL, size = 8.5),
      plot.tag         = element_text(colour = TEXT_COL, face = "bold", size = 10),
      plot.title       = element_text(colour = TEXT_COL, size = 10, face = "bold"),
      plot.subtitle    = element_text(colour = AXIS_COL, size = 8)
    )
}

# ── Loop through all methods ──────────────────────────────────────────────────
for (method in METHODS) {
  cat("\n\n╔════════════════════════════════════════════════════════════╗\n")
  cat("║ PROCESSING METHOD:", method, "\n")
  cat("╚════════════════════════════════════════════════════════════╝\n\n")

  # Create output directory for this method
  out_dir <- file.path(OUT_BASE, method)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Load categorization data
  cat("Loading categorization data...\n")
  cat_data <- fread(paste0("derived_tables/disturbance_metric_test/", method, ".csv"))

  # Load main datasets
  cat("Loading main data and SHAP data...\n")
  main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

  # ─── PLOT TYPE 1: SHAP % by Mortality Metrics ──────────────────────────────
  cat("\nGenerating SHAP % plots (plot_16 style)...\n")

  shap <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv")
  shap_m04 <- shap[grepl("^M04_24m_", model)]
  shap_m04[, response := sub("M04_24m_", "", model)]

  shap_total <- shap_m04[, .(total_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]
  shap_dist  <- shap_m04[group == "Disturbance", .(dist_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]
  shap_pct <- merge(shap_total, shap_dist, by = c("SITE_ID", "response"))
  shap_pct[, dist_pct := dist_shap / total_shap * 100]
  shap_pct <- merge(shap_pct, cat_data[, .(SITE_ID, abs_mort_cat, rel_mort_cat, rel_dist_cat)], by = "SITE_ID")
  shap_pct[, response := factor(response, levels = EFP_ORDER)]

  # Color scheme based on category names
  cat_names <- unique(c(shap_pct$abs_mort_cat, shap_pct$rel_mort_cat, shap_pct$rel_dist_cat))
  tier_cols <- setNames(
    rep(c("#4DAECC", "#F0A500", "#E8257A"), length.out = length(cat_names)),
    sort(unique(cat_names))
  )

  make_shap_pct_plot <- function(tier_col, tier_name, x_label) {
    data <- copy(shap_pct)
    data[, tier := get(tier_col)]
    data[, tier := factor(tier)]

    p <- ggplot(data, aes(x = tier, y = dist_pct, fill = tier)) +
      geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4) +
      geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
      geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
      stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
      scale_fill_manual(values = tier_cols, guide = "none") +
      facet_wrap(~response, nrow = 1) +
      labs(title = paste0("Disturbance SHAP % by ", tier_name, " (M04, 24m)"),
           x = x_label, y = "Disturbance SHAP (%)") +
      get_dark_theme() +
      theme(axis.text.x = element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1))

    p
  }

  p1 <- make_shap_pct_plot("abs_mort_cat", "Absolute Mortality", "")
  p2 <- make_shap_pct_plot("rel_mort_cat", "Relative Mortality", "")
  p3 <- make_shap_pct_plot("rel_dist_cat", "Relative Disturbance", "")

  fig <- (p1 / p2 / p3) +
    plot_annotation(theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA))) &
    theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

  stem <- file.path(out_dir, "01_SHAP_percent_mortality_disturbance")
  ggsave(paste0(stem, ".png"), fig, width = 220, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
  cat("✓ Saved:", basename(stem), "\n")

  # ─── PLOT TYPE 2: Mean |SHAP| by Mortality Metrics ────────────────────────
  cat("Generating Mean |SHAP| plots (plot_31 style)...\n")

  shap_dist_mean <- shap_m04[group == "Disturbance", .(dist_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]
  shap_data_mean <- merge(shap_dist_mean, cat_data[, .(SITE_ID, abs_mort_cat, rel_mort_cat, rel_dist_cat)], by = "SITE_ID")
  shap_data_mean[, response := factor(response, levels = EFP_ORDER)]

  make_shap_mean_plot <- function(tier_col, tier_name, x_label) {
    data <- copy(shap_data_mean)
    data[, tier := get(tier_col)]
    data[, tier := factor(tier)]

    p <- ggplot(data, aes(x = tier, y = dist_shap, fill = tier)) +
      geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4) +
      geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
      geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
      stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
      scale_fill_manual(values = tier_cols, guide = "none") +
      facet_wrap(~response, nrow = 1, scales = "free_y") +
      labs(title = paste0("Mean |SHAP| Disturbance by ", tier_name, " (M04, 24m)"),
           x = x_label, y = "Mean |SHAP|") +
      get_dark_theme() +
      theme(axis.text.x = element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1))

    p
  }

  p1m <- make_shap_mean_plot("abs_mort_cat", "Absolute Mortality", "")
  p2m <- make_shap_mean_plot("rel_mort_cat", "Relative Mortality", "")
  p3m <- make_shap_mean_plot("rel_dist_cat", "Relative Disturbance", "")

  fig_mean <- (p1m / p2m / p3m) +
    plot_annotation(theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA))) &
    theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

  stem_mean <- file.path(out_dir, "02_SHAP_mean_mortality_disturbance")
  ggsave(paste0(stem_mean, ".png"), fig_mean, width = 220, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
  cat("✓ Saved:", basename(stem_mean), "\n")

  cat("\n✓ Method", method, "complete!\n")
}

cat("\n\n╔════════════════════════════════════════════════════════════╗\n")
cat("║ ALL METHODS PROCESSED                                     ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
cat("\nOutput structure:\n")
cat("plots/disturbance_metric_test/\n")
cat("├── tertiles_method/\n")
cat("│   ├── 01_SHAP_percent_mortality_disturbance.png\n")
cat("│   └── 02_SHAP_mean_mortality_disturbance.png\n")
cat("├── equal_width_method/\n")
cat("│   ├── 01_SHAP_percent_mortality_disturbance.png\n")
cat("│   └── 02_SHAP_mean_mortality_disturbance.png\n")
cat("└── natural_breaks_method/\n")
cat("    ├── 01_SHAP_percent_mortality_disturbance.png\n")
cat("    └── 02_SHAP_mean_mortality_disturbance.png\n")

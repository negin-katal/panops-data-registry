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

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

# ── 1) Load v3 harmonized dataset and calculate metrics per site ────────────────
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

site_metrics <- main_data[, .(
  abs_mort = mean(mortality_intensity_pct_500m, na.rm = TRUE),
  rel_mort = mean((mortality_intensity_pct_500m + loss_area_frac_500m * 100) /
                   (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100, na.rm = TRUE),
  rel_dist = mean((deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
                   (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100, na.rm = TRUE)
), by = SITE_ID]

# Create categorical tiers
site_metrics[, abs_mort_tier := fcase(
  abs_mort < 10,  "< 10%",
  abs_mort < 20,  "< 20%",
  default =       "> 20%"
)]

site_metrics[, rel_mort_tier := fcase(
  rel_mort < 40,  "< 40%",
  rel_mort < 60,  "< 60%",
  default =       "> 60%"
)]

site_metrics[, rel_dist_tier := fcase(
  rel_dist < 10,  "< 10",
  rel_dist < 20,  "< 20",
  default =       "> 20"
)]

# Factor levels
site_metrics[, abs_mort_tier := factor(abs_mort_tier, levels = c("< 10%", "< 20%", "> 20%"))]
site_metrics[, rel_mort_tier := factor(rel_mort_tier, levels = c("< 40%", "< 60%", "> 60%"))]
site_metrics[, rel_dist_tier := factor(rel_dist_tier, levels = c("< 10", "< 20", "> 20"))]

# ── 2) Load SHAP data (anomaly M04, 24m window) ────────────────────────────────
shap <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv")

# Keep M04 (C+T+D) models, 24m window
shap_m04 <- shap[grepl("^M04_24m_", model)]
shap_m04[, response := sub("M04_24m_", "", model)]

# Disturbance SHAP per site × response (absolute mean |SHAP|)
shap_dist <- shap_m04[group == "Disturbance",
  .(dist_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]

# Merge with site metrics
shap_data <- merge(shap_dist, site_metrics[, .(SITE_ID, abs_mort_tier, rel_mort_tier, rel_dist_tier)], by = "SITE_ID")
shap_data[, response := factor(response, levels = EFP_ORDER)]

# ── 3) Theme ──────────────────────────────────────────────────────────────────
dark_theme <- theme_bw(base_size = 9) +
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

# Color scheme
TIER_COLS <- c(
  "< 10%" = "#4DAECC", "< 20%" = "#F0A500", "> 20%" = "#E8257A",
  "< 40%" = "#4DAECC", "< 60%" = "#F0A500", "> 60%" = "#E8257A",
  "< 10" = "#4DAECC", "< 20" = "#F0A500", "> 20" = "#E8257A"
)

# ── 4) Create three metric plots ──────────────────────────────────────────────
make_shap_plot <- function(tier_col, tier_name, x_label) {
  data <- copy(shap_data)
  data[, tier := get(tier_col)]
  data[, tier := factor(tier)]

  p <- ggplot(data, aes(x = tier, y = dist_shap, fill = tier)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4) +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    scale_fill_manual(values = TIER_COLS, guide = "none") +
    facet_wrap(~response, nrow = 1) +
    labs(
      title = paste0("Mean |SHAP| of Disturbance group by ", tier_name, " (M04, 24m)"),
      subtitle = "C+T+D model | Mean absolute SHAP values for disturbance variables",
      x = x_label,
      y = "Mean |SHAP|"
    ) +
    dark_theme +
    theme(
      axis.text.x = element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1)
    )

  p
}

# Generate all three metric plots
p1 <- make_shap_plot("abs_mort_tier", "Absolute Mortality", "Absolute Mortality (%)")
p2 <- make_shap_plot("rel_mort_tier", "Relative Mortality", "Relative Mortality (%)")
p3 <- make_shap_plot("rel_dist_tier", "Relative Disturbance", "Relative Disturbance (%)")

# Combine into single figure
fig_combined <- (p1 / p2 / p3) +
  plot_annotation(
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

stem <- file.path(OUT_DIR, "fig_threshold_SHAP_mortality_disturbance_mean")
ggsave(paste0(stem, ".png"), fig_combined,
       width = 220, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig_combined,
       width = 220, height = 240, units = "mm", bg = DARK_BG)

cat("\n=== Figure saved ===\n")
cat("PNG:", paste0(stem, ".png\n"))
cat("PDF:", paste0(stem, ".pdf\n"))

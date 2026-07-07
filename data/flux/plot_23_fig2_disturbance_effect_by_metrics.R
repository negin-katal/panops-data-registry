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

COL_BASE <- "#6BA3C4"
COL_DIST <- "#E8257A"

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
EFP_UNITS <- c(
  GPPsat = expression(GPP[sat]~"("*mu*"mol m"^{-2}~"s"^{-1}*")"),
  NEPmax = expression(NEP[max]~"("*mu*"mol m"^{-2}~"s"^{-1}*")"),
  ETmax  = expression(ET[max]~"(mm d"^{-1}*")"),
  uWUE   = expression(uWUE~"(g C mm"^{-1}*")"),
  WUE    = expression(WUE~"(g C mm"^{-1}*")")
)

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

# ── 2) Load RMSE predictions from v3 anomaly ────────────────────────────────
pred_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv"
preds <- fread(pred_file)

preds[, model_key := sub("_(12m|24m)_.*", "", model)]
preds[, window    := regmatches(model, regexpr("(12m|24m)", model))]
preds[, response  := sub(".*_(12m|24m)_", "", model)]

# Keep M01 (C) and M02 (C+D) with 24m window
preds_sub <- preds[model_key %in% c("M01","M02") & window == "24m"]

site_rmse <- preds_sub[, .(
  rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))
), by = .(model_key, response, SITE_ID)]

# Pivot to get C and C+D side-by-side
site_rmse_wide <- dcast(site_rmse, SITE_ID + response ~ model_key, value.var = "rmse")

# Merge with site metrics
site_rmse_wide <- merge(site_rmse_wide, site_metrics, by = "SITE_ID")
site_rmse_wide[, response := factor(response, levels = EFP_ORDER)]

# ── 3) Theme ──────────────────────────────────────────────────────────────────
dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background   = element_rect(fill = DARK_BG,  colour = NA),
    panel.background  = element_rect(fill = PANEL_BG, colour = NA),
    panel.border      = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major  = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor  = element_blank(),
    strip.background  = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text        = element_text(colour = TEXT_COL, size = 8, face = "bold"),
    axis.text         = element_text(colour = AXIS_COL, size = 7.5),
    axis.title        = element_text(colour = AXIS_COL, size = 8.5),
    plot.tag          = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.title        = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle     = element_text(colour = AXIS_COL, size = 8),
    legend.background = element_rect(fill = NA),
    legend.key        = element_rect(fill = NA, colour = NA),
    legend.text       = element_text(colour = TEXT_COL, size = 9),
    legend.key.size   = unit(0.5, "cm")
  )

# ── 4) Create panel factory for each metric ──────────────────────────────────
make_metric_panel_fig2 <- function(metric_col, metric_name, metric_label, tag_letter) {
  data <- copy(site_rmse_wide)
  data[, metric := get(metric_col)]

  # Long format for plotting
  data_long <- melt(data,
    id.vars = c("SITE_ID", "response", "metric"),
    measure.vars = c("M01", "M02"),
    variable.name = "model_key",
    value.name = "site_rmse"
  )

  data_long[, model_type := ifelse(model_key == "M01", "Without D", "With D")]
  data_long[, model_type := factor(model_type, levels = c("Without D", "With D"))]
  data_long[, response := factor(response, levels = EFP_ORDER)]

  p <- ggplot(data_long, aes(x = metric, y = site_rmse, fill = model_type, group = interaction(metric, model_type))) +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85,
                position = position_dodge(width = 0.8)) +
    geom_boxplot(width = 0.12, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35,
                 position = position_dodge(width = 0.8)) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 0.9,
                 position = position_dodge(width = 0.8)) +
    scale_fill_manual(values = c("Without D" = COL_BASE, "With D" = COL_DIST), name = NULL) +
    facet_wrap(~response, nrow = 1, scales = "free_y") +
    labs(
      tag = tag_letter,
      x = metric_label,
      y = "RMSE"
    ) +
    dark_theme +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 7.5, angle = 12, hjust = 1))

  p
}

# Generate three metric panels
p_abs <- make_metric_panel_fig2("abs_mort_tier", "Absolute Mortality", "Absolute Mortality (%)", "a")
p_rel <- make_metric_panel_fig2("rel_mort_tier", "Relative Mortality", "Relative Mortality (%)", "b")
p_dist <- make_metric_panel_fig2("rel_dist_tier", "Relative Disturbance", "Relative Disturbance (%)", "c")

# ── 5) Combine into single figure ────────────────────────────────────────────
fig_combined <- (p_abs / p_rel / p_dist) +
  plot_annotation(
    title = "Effect of adding deadwood disturbance on RMSE by mortality/disturbance metrics",
    subtitle = "Stratified by Absolute Mortality, Relative Mortality, Relative Disturbance | Anomaly 24m window",
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

# ── 6) Save figure ──────────────────────────────────────────────────────────
stem <- file.path(OUT_DIR, "fig2_RF_RMSE_disturbance_effect_by_metrics")
ggsave(paste0(stem, ".png"), fig_combined,
       width = 220, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig_combined,
       width = 220, height = 240, units = "mm", bg = DARK_BG)

cat("\n=== Figure saved ===\n")
cat("PNG:", paste0(stem, ".png\n"))
cat("PDF:", paste0(stem, ".pdf\n"))

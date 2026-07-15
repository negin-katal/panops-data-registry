library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- "plots/manuscript_candidates/fig2_per_model"
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

# ── 2) Load RMSE data for all panels ──────────────────────────────────────────
load_site_rmse <- function(file, win, mem) {
  dt <- fread(file)
  dt[, model_key := sub("_(12m|24m)_.*", "", model)]
  dt[, window    := regmatches(model, regexpr("(12m|24m)", model))]
  dt[, response  := sub(".*_(12m|24m)_", "", model)]

  dt_sub <- dt[window == win & model_key %in% c("M01","M02","M03","M04")]
  dt_sub[, site_rmse := sqrt(mean((predicted - observed)^2, na.rm=TRUE)),
         by = .(model_key, response, SITE_ID)]
  dt_unique <- unique(dt_sub[, .(model_key, response, SITE_ID, site_rmse)])
  dt_unique[, panel := paste0(mem, " / ", win)]
  dt_unique
}

PANEL_DEFS <- list(
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv",
       win = "12m", mem = "Anomaly"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv",
       win = "24m", mem = "Anomaly"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_v3/RF_predictions_LOSO.csv",
       win = "12m", mem = "Raw-lag"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_v3/RF_predictions_LOSO.csv",
       win = "24m", mem = "Raw-lag")
)

all_rmse <- rbindlist(lapply(PANEL_DEFS, function(p)
  load_site_rmse(p$file, p$win, p$mem)))

# Merge with site metrics
all_rmse <- merge(all_rmse, site_metrics[, .(SITE_ID, abs_mort_tier, rel_mort_tier, rel_dist_tier)], by = "SITE_ID")

# Add "All sites" for reference
all_sites_copy <- copy(all_rmse)
all_sites_copy[, abs_mort_tier := "All sites"]
all_sites_copy[, rel_mort_tier := "All sites"]
all_sites_copy[, rel_dist_tier := "All sites"]

all_rmse <- rbindlist(list(all_rmse, all_sites_copy), fill = TRUE)

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

# ── 4) Plot factory for each metric ──────────────────────────────────────────
make_metric_plots <- function(metric_col, metric_name, metric_label) {
  # Filter data for this metric
  data <- copy(all_rmse)
  data[, metric := get(metric_col)]
  data[, response := factor(response, levels = EFP_ORDER)]
  data[, panel := factor(panel, levels = c("Anomaly / 12m", "Anomaly / 24m", "Raw-lag / 12m", "Raw-lag / 24m"))]

  # Create one plot per EFP
  plots <- lapply(EFP_ORDER, function(efp) {
    sub <- data[response == efp & model_key %in% c("M01","M02")]
    sub[, model_type := factor(
      ifelse(model_key == "M01", "Without D", "With D"),
      levels = c("Without D", "With D")
    )]

    p <- ggplot(sub, aes(x = metric, y = site_rmse, fill = model_type, group = interaction(metric, model_type))) +
      geom_violin(trim = TRUE, scale = "width", width = 0.7, colour = NA, alpha = 0.85,
                  position = position_dodge(width = 0.8)) +
      geom_boxplot(width = 0.12, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35,
                   position = position_dodge(width = 0.8)) +
      stat_summary(fun = median, geom = "point", colour = "white", size = 0.9,
                   position = position_dodge(width = 0.8)) +
      scale_fill_manual(values = c("Without D" = COL_BASE, "With D" = COL_DIST), name = NULL) +
      facet_wrap(~panel, nrow = 1) +
      labs(x = metric_label, y = EFP_UNITS[[efp]]) +
      dark_theme +
      theme(axis.text.x = element_text(colour = AXIS_COL, size = 7.5, angle = 12, hjust = 1))

    p
  })

  # Combine with patchwork
  fig <- wrap_plots(plots, nrow = 5) +
    plot_annotation(
      title = paste0("RMSE by ", metric_name),
      subtitle = "C (blue) vs C+D (red) | Anomaly & Raw-lag | 12m & 24m windows",
      theme = theme(
        plot.background = element_rect(fill = DARK_BG, colour = NA),
        plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
        plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
      )
    ) & theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

  stem <- file.path(OUT_DIR, paste0("fig_threshold_", metric_name))
  ggsave(paste0(stem, ".png"), fig, width = 220, height = 280, units = "mm", dpi = 300, bg = DARK_BG)
  ggsave(paste0(stem, ".pdf"), fig, width = 220, height = 280, units = "mm", bg = DARK_BG)

  cat("\n✓ Saved:", stem, "\n")
}

# Generate all three metric plots
make_metric_plots("abs_mort_tier", "Absolute_Mortality", "Absolute Mortality (%)")
make_metric_plots("rel_mort_tier", "Relative_Mortality", "Relative Mortality (%)")
make_metric_plots("rel_dist_tier", "Relative_Disturbance", "Relative Disturbance (%)")

cat("\n=== All metric plots saved to", OUT_DIR, "===\n")

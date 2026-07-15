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

# Calculate site-level metrics (averaged across years)
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

# ── 2) Per-site RMSE from predictions (anomaly 24mbench) ────────────────────────
pred_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv"
preds <- fread(pred_file)

preds[, model_key := sub("_(12m|24m)_.*", "", model)]
preds[, window    := regmatches(model, regexpr("(12m|24m)", model))]
preds[, response  := sub(".*_(12m|24m)_", "", model)]

# Keep M01, M02, M03, M04 with 24m window
preds_sub <- preds[model_key %in% c("M01","M02","M03","M04") & window == "24m"]

site_rmse <- preds_sub[, .(
  rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))
), by = .(model_key, response, SITE_ID)]

# ── 3) Calculate Delta RMSE for each comparison ───────────────────────────────
make_delta <- function(base_key, dist_key, label) {
  base <- site_rmse[model_key == base_key, .(SITE_ID, response, rmse_base = rmse)]
  dist <- site_rmse[model_key == dist_key, .(SITE_ID, response, rmse_dist = rmse)]
  merged <- merge(base, dist, by = c("SITE_ID", "response"))
  merged[, delta_rmse := rmse_dist - rmse_base]
  merged[, comparison := label]
  merged
}

delta_c_cd <- make_delta("M01", "M02", "C vs C+D")
delta_ct_ctd <- make_delta("M03", "M04", "C+T vs C+T+D")

# Merge with site metrics
delta_c_cd <- merge(delta_c_cd, site_metrics, by = "SITE_ID")
delta_ct_ctd <- merge(delta_ct_ctd, site_metrics, by = "SITE_ID")

delta_c_cd[, response := factor(response, levels = EFP_ORDER)]
delta_ct_ctd[, response := factor(response, levels = EFP_ORDER)]

# ── 4) Color schemes for each metric ──────────────────────────────────────────
abs_mort_cols <- c("< 10%" = "#4DAECC", "< 20%" = "#F0A500", "> 20%" = "#E8257A")
rel_mort_cols <- c("< 40%" = "#4DAECC", "< 60%" = "#F0A500", "> 60%" = "#E8257A")
rel_dist_cols <- c("< 10" = "#4DAECC", "< 20" = "#F0A500", "> 20" = "#E8257A")

# ── 5) Theme ──────────────────────────────────────────────────────────────────
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
    legend.position  = "none",
    plot.tag         = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.title       = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle    = element_text(colour = AXIS_COL, size = 8)
  )

# ── 6) Create panel factory ──────────────────────────────────────────────────
make_metric_panel <- function(data, metric_col, tier_col, tier_label, colors, tag_letter) {
  sub <- data[!is.na(data[[metric_col]]), ]

  p <- ggplot(sub, aes(x = .data[[tier_col]], y = delta_rmse, fill = .data[[tier_col]])) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    scale_fill_manual(values = colors) +
    facet_wrap(~response, nrow = 2, scales = "free_y",
               labeller = as_labeller(c(
                 GPPsat = "GPPsat", NEPmax = "NEPmax",
                 ETmax = "ETmax", uWUE = "uWUE", WUE = "WUE"
               ))) +
    labs(
      tag = tag_letter,
      x = tier_label,
      y = expression(Delta*"RMSE  (with D − without D)"),
      title = tier_label
    ) +
    dark_theme +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1))

  p
}

# ── 7) Create separate plots for each comparison ───────────────────────────────
# C vs C+D
p1_c_cd <- make_metric_panel(delta_c_cd, "abs_mort", "abs_mort_tier", "Absolute Mortality (%)", abs_mort_cols, "a")
p2_c_cd <- make_metric_panel(delta_c_cd, "rel_mort", "rel_mort_tier", "Relative Mortality (%)", rel_mort_cols, "b")
p3_c_cd <- make_metric_panel(delta_c_cd, "rel_dist", "rel_dist_tier", "Relative Disturbance (%)", rel_dist_cols, "c")

fig_c_cd <- (p1_c_cd / p2_c_cd / p3_c_cd) +
  plot_annotation(
    title = "Delta RMSE: Climate vs Climate+Disturbance (M01 vs M02)",
    subtitle = "Anomaly memory | 24m window | negative dRMSE = D improved prediction",
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

# C+T vs C+T+D
p1_ct_ctd <- make_metric_panel(delta_ct_ctd, "abs_mort", "abs_mort_tier", "Absolute Mortality (%)", abs_mort_cols, "a")
p2_ct_ctd <- make_metric_panel(delta_ct_ctd, "rel_mort", "rel_mort_tier", "Relative Mortality (%)", rel_mort_cols, "b")
p3_ct_ctd <- make_metric_panel(delta_ct_ctd, "rel_dist", "rel_dist_tier", "Relative Disturbance (%)", rel_dist_cols, "c")

fig_ct_ctd <- (p1_ct_ctd / p2_ct_ctd / p3_ct_ctd) +
  plot_annotation(
    title = "Delta RMSE: Climate+Traits vs Climate+Traits+Disturbance (M03 vs M04)",
    subtitle = "Anomaly memory | 24m window | negative dRMSE = D improved prediction",
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

# ── 8) Save figures ────────────────────────────────────────────────────────────
stem1 <- file.path(OUT_DIR, "fig_delta_RMSE_C_vs_CplusD")
ggsave(paste0(stem1, ".png"), fig_c_cd,
       width = 200, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem1, ".pdf"), fig_c_cd,
       width = 200, height = 240, units = "mm", bg = DARK_BG)

stem2 <- file.path(OUT_DIR, "fig_delta_RMSE_CT_vs_CTplusD")
ggsave(paste0(stem2, ".png"), fig_ct_ctd,
       width = 200, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem2, ".pdf"), fig_ct_ctd,
       width = 200, height = 240, units = "mm", bg = DARK_BG)

cat("\n=== Figures saved ===\n")
cat("1. PNG:", paste0(stem1, ".png\n"))
cat("   PDF:", paste0(stem1, ".pdf\n"))
cat("2. PNG:", paste0(stem2, ".png\n"))
cat("   PDF:", paste0(stem2, ".pdf\n"))

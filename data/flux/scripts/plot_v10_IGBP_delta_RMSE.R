#!/usr/bin/env Rscript
# ============================================================================
# V10: ΔRMSE by IGBP class (Panel A) + ΔRMSE vs tree cover (Panel B)
# One figure each, per delta-RMSE comparison unit. Style = fig_IGBP_treecover.
#   ΔRMSE = RMSE(with D) − RMSE(without D) per site (negative = D improved)
# ============================================================================

library(data.table)
library(ggplot2)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_IGBP_delta_RMSE.R <dataset_type>")
dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 IGBP ΔRMSE: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep = "")

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")
IGBP_COL <- c(ENF="#1F6B3A", EBF="#33A14A", DNF="#7BC87E", DBF="#B2DF8A",
              MF="#FDBF6F", CSH="#E5820B", OSH="#D4A017", WSA="#C4A85C",
              SAV="#E8D44D", WET="#4DAECC")
EFP_ORDER <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")

if (dataset_type == "filtered") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_predictions_LOSO.csv"
  out_igbp  <- "plots/V10/sites_with_high_Tcover/RMSE/IGBP"
  out_tc    <- "plots/V10/sites_with_high_Tcover/RMSE/treecover"
} else if (dataset_type == "all_sites") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_predictions_LOSO.csv"
  out_igbp  <- "plots/V10/all_sites/RMSE/IGBP"
  out_tc    <- "plots/V10/all_sites/RMSE/treecover"
} else stop("Invalid dataset_type")
## --- optional model-family override (XGBoost etc.); no-op when unset ---
source("scripts/v10_model_family.R"); v10_apply_override()
dir.create(out_igbp, showWarnings = FALSE, recursive = TRUE)
dir.create(out_tc, showWarnings = FALSE, recursive = TRUE)

dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background = element_rect(fill = DARK_BG, colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text = element_text(colour = TEXT_COL, size = 8, face = "bold"),
    axis.text = element_text(colour = AXIS_COL, size = 7.5),
    axis.title = element_text(colour = AXIS_COL, size = 8.5),
    plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
    plot.subtitle = element_text(colour = AXIS_COL, size = 8),
    legend.background = element_rect(fill = NA),
    legend.key = element_rect(fill = NA, colour = NA),
    legend.text = element_text(colour = AXIS_COL, size = 8),
    legend.title = element_text(colour = AXIS_COL, size = 8.5)
  )
EFP_LAB <- as_labeller(setNames(EFP_ORDER, EFP_ORDER))

# ── site metadata: IGBP + tree cover ─────────────────────────
main <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv",
              select = c("SITE_ID", "IGBP", "forest_mean_pct_500m"))
site_meta <- main[, .(tree_cover = mean(forest_mean_pct_500m, na.rm = TRUE)), by = .(SITE_ID, IGBP)]
site_meta <- site_meta[, .SD[1], by = SITE_ID]
site_meta[, IGBP := factor(IGBP, levels = IGBP_ORDER)]

# ── per-site RMSE ────────────────────────────────────────────
preds <- fread(pred_file)
preds <- preds[is.finite(observed) & is.finite(predicted)]
site_rmse <- preds[, .(rmse = sqrt(mean((observed - predicted)^2))),
                   by = .(model, response, SITE_ID)]

units <- list(
  list(id="M1vsM2_12m", wo="M1_12m", wd="M2_12m"),
  list(id="M1vsM2_24m", wo="M1_24m", wd="M2_24m"),
  list(id="M3vsM4_12m", wo="M3_12m", wd="M4_12m"),
  list(id="M3vsM4_24m", wo="M3_24m", wd="M4_24m"),
  list(id="M5vsM6_raw_12m", wo="M5_raw_12m", wd="M6_raw_12m"),
  list(id="M5vsM6_raw_24m", wo="M5_raw_24m", wd="M6_raw_24m"),
  list(id="M5vsM6_anom_12m", wo="M5_anom_12m", wd="M6_anom_12m"),
  list(id="M5vsM6_anom_24m", wo="M5_anom_24m", wd="M6_anom_24m"),
  list(id="M7vsM8_raw_12m", wo="M7_raw_12m", wd="M8_raw_12m"),
  list(id="M7vsM8_raw_24m", wo="M7_raw_24m", wd="M8_raw_24m"),
  list(id="M7vsM8_anom_12m", wo="M7_anom_12m", wd="M8_anom_12m"),
  list(id="M7vsM8_anom_24m", wo="M7_anom_24m", wd="M8_anom_24m")
)

cat("Generating figures:\n")
for (u in units) {
  wo <- site_rmse[model == u$wo, .(response, SITE_ID, r_wo = rmse)]
  wd <- site_rmse[model == u$wd, .(response, SITE_ID, r_wd = rmse)]
  if (nrow(wo) == 0 || nrow(wd) == 0) { cat("  skip:", u$id, "\n"); next }
  d <- merge(wo, wd, by = c("response", "SITE_ID"))
  d[, delta_rmse := r_wd - r_wo]
  d <- merge(d, site_meta, by = "SITE_ID")
  d <- d[response %in% EFP_ORDER & !is.na(IGBP)]
  d[, response := factor(response, levels = EFP_ORDER)]

  # Panel A: violin by IGBP
  pA <- ggplot(d, aes(x = IGBP, y = delta_rmse, fill = IGBP)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4, linetype = "dashed") +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.3) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    stat_summary(fun = mean, geom = "point", colour = "yellow", size = 1.2, shape = 18) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    facet_wrap(~response, nrow = 1, scales = "free_y", labeller = EFP_LAB) +
    labs(x = NULL, y = expression(Delta*"RMSE  (with D - without D)"),
         title = sprintf("Effect of adding disturbance on per-site RMSE by IGBP class — %s", u$id),
         subtitle = "White dot = median | Yellow diamond = mean | negative = D improved") +
    dark_theme +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 6.5, face = "bold", angle = 45, hjust = 1))
  ggsave(file.path(out_igbp, sprintf("IGBP_deltaRMSE_%s.png", u$id)), pA, width = 18, height = 5, dpi = 200, bg = DARK_BG)
  ggsave(file.path(out_igbp, sprintf("IGBP_deltaRMSE_%s.pdf", u$id)), pA, width = 18, height = 5, bg = DARK_BG)

  # Panel B: tree cover vs delta RMSE
  pB <- ggplot(d, aes(x = tree_cover, y = delta_rmse, colour = IGBP)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.35, linetype = "dashed") +
    geom_point(size = 1.4, alpha = 0.7) +
    geom_smooth(aes(group = 1), method = "loess", span = 0.9, colour = "white",
                fill = "#444444", linewidth = 0.7, se = TRUE) +
    scale_colour_manual(values = IGBP_COL, name = "IGBP") +
    guides(colour = guide_legend(override.aes = list(size = 2.5, alpha = 1), ncol = 1)) +
    facet_wrap(~response, nrow = 1, scales = "free_y", labeller = EFP_LAB) +
    labs(x = "Tree cover — forest_mean_pct_500m (%)",
         y = expression(Delta*"RMSE  (with D - without D)"),
         title = sprintf("Tree cover vs. disturbance benefit — %s", u$id),
         subtitle = "Each point = one site | Loess trend with 95% CI") +
    dark_theme + theme(legend.position = "right")
  ggsave(file.path(out_tc, sprintf("treecover_deltaRMSE_%s.png", u$id)), pB, width = 16, height = 4.5, dpi = 200, bg = DARK_BG)
  ggsave(file.path(out_tc, sprintf("treecover_deltaRMSE_%s.pdf", u$id)), pB, width = 16, height = 4.5, bg = DARK_BG)

  cat(sprintf("  ✓ %s\n", u$id))
}
cat("\n✅ V10 IGBP ΔRMSE COMPLETE\n")

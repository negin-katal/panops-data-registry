#!/usr/bin/env Rscript
# ============================================================================
# V10: IGBP "board" — 4 stacked panels per model set (like fig_IGBP_treecover
# plus an added SHAP-by-IGBP violin panel):
#   A) ΔRMSE by IGBP (violin)      B) Disturbance SHAP % by IGBP (violin)
#   C) ΔRMSE vs tree cover (scatter)  D) SHAP % vs tree cover (scatter)
# One board per with-D model: M4 (M3vsM4), M6 (M5vsM6), M8 (M7vsM8).
# ============================================================================

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_IGBP_board.R <dataset_type>")
dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 IGBP BOARDS: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep = "")

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")
IGBP_COL <- c(ENF="#1F6B3A", EBF="#33A14A", DNF="#7BC87E", DBF="#B2DF8A",
              MF="#FDBF6F", CSH="#E5820B", OSH="#D4A017", WSA="#C4A85C",
              SAV="#E8D44D", WET="#4DAECC")
EFP_ORDER <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")
EFP_LAB <- as_labeller(setNames(EFP_ORDER, EFP_ORDER))

if (dataset_type == "filtered") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_predictions_LOSO.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_site_shap_M04_M08.csv"
  out_dir   <- "plots/V10/sites_with_high_Tcover/IGBP_boards"
} else if (dataset_type == "all_sites") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_predictions_LOSO.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_site_shap_M04_M08.csv"
  out_dir   <- "plots/V10/all_sites/IGBP_boards"
} else stop("Invalid dataset_type")
## --- optional model-family override (XGBoost etc.); no-op when unset ---
source("scripts/v10_model_family.R"); v10_apply_override()
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background = element_rect(fill = DARK_BG, colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text = element_text(colour = TEXT_COL, size = 8, face = "bold"),
    axis.text = element_text(colour = AXIS_COL, size = 7),
    axis.title = element_text(colour = AXIS_COL, size = 8.5),
    plot.title = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle = element_text(colour = AXIS_COL, size = 7.5),
    plot.tag = element_text(colour = TEXT_COL, face = "bold", size = 11),
    legend.background = element_rect(fill = NA),
    legend.key = element_rect(fill = NA, colour = NA),
    legend.text = element_text(colour = AXIS_COL, size = 8),
    legend.title = element_text(colour = AXIS_COL, size = 8.5)
  )

# ── site metadata ────────────────────────────────────────────
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

# ── per-site disturbance SHAP % ──────────────────────────────
shap <- fread(shap_file)
shap[, is_dist := grepl("^(absolute_|relative_|new_mortality|disturbance_)", variable)]
shap_sum <- shap[, .(total = sum(mean_abs_shap, na.rm = TRUE),
                     dist = sum(mean_abs_shap[is_dist], na.rm = TRUE)),
                 by = .(model, response, test_site)]
shap_sum[, dist_pct := dist / total * 100]
shap_sum <- shap_sum[is.finite(dist_pct)]

# ── model sets (with-D model drives both) ────────────────────
sets <- list(
  list(wd="M4_12m",      wo="M3_12m",      label="M4 (C+T+D)",       win="12m"),
  list(wd="M4_24m",      wo="M3_24m",      label="M4 (C+T+D)",       win="24m"),
  list(wd="M6_raw_12m",  wo="M5_raw_12m",  label="M6 raw (C+D+Mem)", win="12m"),
  list(wd="M6_raw_24m",  wo="M5_raw_24m",  label="M6 raw (C+D+Mem)", win="24m"),
  list(wd="M6_anom_12m", wo="M5_anom_12m", label="M6 anom (C+D+Mem)",win="12m"),
  list(wd="M6_anom_24m", wo="M5_anom_24m", label="M6 anom (C+D+Mem)",win="24m"),
  list(wd="M8_raw_12m",  wo="M7_raw_12m",  label="M8 raw (C+T+D+Mem)", win="12m"),
  list(wd="M8_raw_24m",  wo="M7_raw_24m",  label="M8 raw (C+T+D+Mem)", win="24m"),
  list(wd="M8_anom_12m", wo="M7_anom_12m", label="M8 anom (C+T+D+Mem)",win="12m"),
  list(wd="M8_anom_24m", wo="M7_anom_24m", label="M8 anom (C+T+D+Mem)",win="24m")
)

violin_igbp <- function(d, yvar, ytitle, ptitle, subtitle, dashed0) {
  p <- ggplot(d, aes_string(x = "IGBP", y = yvar, fill = "IGBP"))
  if (dashed0) p <- p + geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4, linetype = "dashed")
  p +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.3) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.1) +
    stat_summary(fun = mean, geom = "point", colour = "yellow", size = 1.1, shape = 18) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    facet_wrap(~response, nrow = 1, scales = "free_y", labeller = EFP_LAB) +
    labs(x = NULL, y = ytitle, title = ptitle, subtitle = subtitle) +
    dark_theme +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 6, face = "bold", angle = 45, hjust = 1))
}

scatter_tc <- function(d, yvar, ytitle, ptitle, subtitle, dashed0, show_leg) {
  p <- ggplot(d, aes_string(x = "tree_cover", y = yvar, colour = "IGBP"))
  if (dashed0) p <- p + geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.35, linetype = "dashed")
  p <- p +
    geom_point(size = 1.3, alpha = 0.7) +
    geom_smooth(aes(group = 1), method = "loess", span = 0.9, colour = "white",
                fill = "#444444", linewidth = 0.7, se = TRUE) +
    scale_colour_manual(values = IGBP_COL, name = "IGBP") +
    facet_wrap(~response, nrow = 1, scales = "free_y", labeller = EFP_LAB) +
    labs(x = "Tree cover — forest_mean_pct_500m (%)", y = ytitle, title = ptitle, subtitle = subtitle) +
    dark_theme
  if (show_leg) p <- p + guides(colour = guide_legend(override.aes = list(size = 2.5, alpha = 1), nrow = 1)) +
    theme(legend.position = "bottom")
  else p <- p + scale_colour_manual(values = IGBP_COL, guide = "none")
  p
}

cat("Generating boards:\n")
for (s in sets) {
  # ΔRMSE per site
  wo <- site_rmse[model == s$wo, .(response, SITE_ID, r_wo = rmse)]
  wd <- site_rmse[model == s$wd, .(response, SITE_ID, r_wd = rmse)]
  dR <- merge(wo, wd, by = c("response", "SITE_ID"))
  dR[, delta_rmse := r_wd - r_wo]
  dR <- merge(dR, site_meta, by = "SITE_ID")
  dR <- dR[response %in% EFP_ORDER & !is.na(IGBP)]
  dR[, response := factor(response, levels = EFP_ORDER)]

  # SHAP % per site (with-D model)
  sh <- shap_sum[model == s$wd]
  sh <- merge(sh, site_meta, by.x = "test_site", by.y = "SITE_ID")
  sh <- sh[response %in% EFP_ORDER & !is.na(IGBP)]
  sh[, response := factor(response, levels = EFP_ORDER)]

  if (nrow(dR) == 0 || nrow(sh) == 0) { cat("  skip:", s$wd, "\n"); next }

  pA <- violin_igbp(dR, "delta_rmse", expression(Delta*"RMSE (with D - without D)"),
                    "A · ΔRMSE by IGBP class",
                    "White dot = median | Yellow diamond = mean | negative = D improved", TRUE)
  pB <- violin_igbp(sh, "dist_pct", "Disturbance SHAP (%)",
                    "B · Disturbance SHAP % by IGBP class",
                    "% of per-site SHAP from disturbance variables", FALSE)
  pC <- scatter_tc(dR, "delta_rmse", expression(Delta*"RMSE (with D - without D)"),
                   "C · Tree cover vs. disturbance benefit",
                   "Each point = one site | Loess trend with 95% CI", TRUE, FALSE)
  pD <- scatter_tc(sh, "dist_pct", "Disturbance SHAP (%)",
                   "D · Tree cover vs. disturbance SHAP importance",
                   "Each point = one site | Loess trend with 95% CI", FALSE, TRUE)

  board <- (pA / pB / pC / pD) +
    plot_annotation(
      title = sprintf("IGBP board — %s | %s window  (%s dataset)", s$label, s$win, dataset_type),
      theme = theme(plot.title = element_text(colour = TEXT_COL, size = 14, face = "bold"),
                    plot.background = element_rect(fill = DARK_BG, colour = NA))
    ) & theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

  stem <- file.path(out_dir, sprintf("board_IGBP_%s", s$wd))
  ggsave(paste0(stem, ".png"), board, width = 17, height = 20, dpi = 190, bg = DARK_BG, limitsize = FALSE)
  ggsave(paste0(stem, ".pdf"), board, width = 17, height = 20, bg = DARK_BG, limitsize = FALSE)
  cat(sprintf("  ✓ %s\n", basename(stem)))
}
cat("\n✅ V10 IGBP BOARDS COMPLETE\n")
cat("   Output:", out_dir, "\n")

#!/usr/bin/env Rscript
# ============================================================================
# V10: IGBP "board" — 4 stacked panels per model set (like fig_IGBP_treecover
# plus an added SHAP-by-IGBP violin panel):
#   A) ΔRMSE by IGBP (violin)      B) NET SIGNED disturbance SHAP by IGBP (violin)
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

DARK_BG <- "white"; PANEL_BG <- "white"; GRID_COL <- "#D9D9D9"
TEXT_COL <- "#111111"; AXIS_COL <- "#444444"
IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")
IGBP_COL <- c(ENF="#1F6B3A", EBF="#33A14A", DNF="#7BC87E", DBF="#B2DF8A",
              MF="#FDBF6F", CSH="#E5820B", OSH="#D4A017", WSA="#C4A85C",
              SAV="#E8D44D", WET="#4DAECC")
EFP_ORDER <- c("GPPsat","NEPmax","ETmax","WUE")   # DRAFT: uWUE dropped
# lines below already filter on response %in% EFP_ORDER, so no empty facet appears
EFP_LAB <- as_labeller(setNames(EFP_ORDER, EFP_ORDER))

if (dataset_type == "filtered") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_predictions_LOSO.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_site_shap_M04_M08.csv"
  harm_file <- "derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
  out_dir   <- "plots/V10/sites_with_high_Tcover/IGBP_boards"
} else if (dataset_type == "tc50") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_tc50/RF_predictions_LOSO.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10_tc50/RF_site_shap_M04_M08.csv"
  harm_file <- "derived_tables/outputs_afterEGU_results/v10_tc50/v10_tc50_B1_GPPsat_harmonized.csv"
  out_dir   <- "plots/V10/sites_tc50/IGBP_boards"
} else if (dataset_type == "all_sites") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_predictions_LOSO.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_site_shap_M04_M08.csv"
  harm_file <- "derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_GPPsat_harmonized.csv"
  out_dir   <- "plots/V10/all_sites/IGBP_boards"
} else stop("Invalid dataset_type")
## --- optional model-family override (XGBoost etc.); no-op when unset ---
source("scripts/v10_model_family.R"); v10_apply_override()
# DRAFT SAFETY: stage output away from the report's own figure tree
if (nzchar(Sys.getenv("V10_DRAFT_OUT"))) out_dir <- Sys.getenv("V10_DRAFT_OUT")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background = element_rect(fill = DARK_BG, colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#EFEFEF", colour = GRID_COL),
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

# relative_disturbance (500m) is only in the harmonized dataset, not in `main`
# above. Per-site value = max across years, same convention as Fig 3 / the
# mortality world map (site_dist aggregation).
na_inf <- function(x) { x[!is.finite(x)] <- NA; x }
harm_dist <- fread(harm_file, select = c("SITE_ID", "relative_disturbance_500m"))
dist_meta <- harm_dist[, .(rel_disturbance = na_inf(max(relative_disturbance_500m, na.rm = TRUE))), by = SITE_ID]
site_meta <- merge(site_meta, dist_meta, by = "SITE_ID", all.x = TRUE)

# ── per-site RMSE ────────────────────────────────────────────
preds <- fread(pred_file)
preds <- preds[is.finite(observed) & is.finite(predicted)]
site_rmse <- preds[, .(rmse = sqrt(mean((observed - predicted)^2))),
                   by = .(model, response, SITE_ID)]

# ── per-site disturbance SHAP % ──────────────────────────────
shap <- fread(shap_file)
# DRAFT: panels B and D switch from the |SHAP| share to the NET SIGNED contribution of the
# disturbance block, matching Figure 4. The sign is not recoverable from shap_file, so read
# the separately computed signed table.
signed_file <- sub("_site_shap_M04_M08\\.csv$", "_site_signed_shap_M4.csv", shap_file)
signed <- if (file.exists(signed_file)) {
  fread(signed_file)[group == "Disturbance",
     .(test_site, model, response, dist_signed = mean_signed_shap)]
} else { message("signed SHAP not found: ", signed_file); NULL }
shap[, is_dist := grepl("^(absolute_|relative_|new_mortality|disturbance_)", variable)]
shap_sum <- shap[, .(total = sum(mean_abs_shap, na.rm = TRUE),
                     dist = sum(mean_abs_shap[is_dist], na.rm = TRUE)),
                 by = .(model, response, test_site)]
shap_sum[, dist_pct := dist / total * 100]
shap_sum <- shap_sum[is.finite(dist_pct)]
if (!is.null(signed))
  shap_sum <- merge(shap_sum, signed, by = c("test_site","model","response"), all.x = TRUE)

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
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "#222222", fill = NA, linewidth = 0.3) +
    stat_summary(fun = median, geom = "point", colour = "#222222", size = 1.1) +
    stat_summary(fun = mean, geom = "point", colour = "yellow", size = 1.1, shape = 18) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    facet_wrap(~response, nrow = 1, scales = "free_y", labeller = EFP_LAB) +
    labs(x = NULL, y = ytitle, title = ptitle, subtitle = subtitle) +
    dark_theme +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 6, face = "bold", angle = 45, hjust = 1))
}

# Spearman correlation (xvar vs y), one test per EFP panel. Returns NA
# rho/p rather than erroring when a facet has too little data (e.g. all-NA
# dist_signed for a response, or a constant x within a subset).
cor_stats <- function(d, xvar, yvar) {
  d[, {
    ok <- is.finite(get(xvar)) & is.finite(get(yvar))
    if (sum(ok) < 4) list(rho = NA_real_, p = NA_real_, n = sum(ok))
    else {
      ct <- tryCatch(cor.test(get(xvar)[ok], get(yvar)[ok], method = "spearman", exact = FALSE),
                     error = function(e) NULL)
      if (is.null(ct)) list(rho = NA_real_, p = NA_real_, n = sum(ok))
      else list(rho = unname(ct$estimate), p = ct$p.value, n = sum(ok))
    }
  }, by = response]
}
stars <- function(q) fifelse(is.na(q), "",
                    fifelse(q < 0.001, "***",
                    fifelse(q < 0.01,  "**",
                    fifelse(q < 0.05,  "*", " ns"))))

scatter_tc <- function(d, xvar, xlabel, yvar, ytitle, ptitle, subtitle, dashed0, show_leg, stat_lab) {
  p <- ggplot(d, aes_string(x = xvar, y = yvar, colour = "IGBP"))
  if (dashed0) p <- p + geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.35, linetype = "dashed")
  p <- p +
    geom_point(size = 1.3, alpha = 0.7) +
    geom_smooth(aes(group = 1), method = "lm", formula = y ~ x, colour = "#222222",
                fill = "#444444", linewidth = 0.7, se = TRUE) +
    geom_text(data = stat_lab, aes(x = -Inf, y = Inf, label = lab), inherit.aes = FALSE,
              hjust = -0.05, vjust = 1.4, size = 2.6, colour = TEXT_COL, fontface = "bold") +
    scale_colour_manual(values = IGBP_COL, name = "IGBP") +
    facet_wrap(~response, nrow = 1, scales = "free_y", labeller = EFP_LAB) +
    labs(x = xlabel, y = ytitle, title = ptitle, subtitle = subtitle) +
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
  # DRAFT: signed SHAP was only computed for M4, so skip any other spec rather than
  # failing inside geom_violin on an all-NA column.
  if (!"dist_signed" %in% names(sh) || all(is.na(sh$dist_signed))) {
    cat(sprintf("  skip %s - no signed SHAP\n", s$wd)); next
  }
  sh[, response := factor(response, levels = EFP_ORDER)]

  if (nrow(dR) == 0 || nrow(sh) == 0) { cat("  skip:", s$wd, "\n"); next }

  pA <- violin_igbp(dR, "delta_rmse", expression(Delta*"RMSE (with D - without D)"),
                    "A · ΔRMSE by IGBP class",
                    "White dot = median | Yellow diamond = mean | negative = D improved", TRUE)
  pB <- violin_igbp(sh, "dist_signed", "Net signed disturbance SHAP\n(effect on PREDICTED value)",
                    "B · Direction of the disturbance effect by IGBP class",
                    "Net signed SHAP of the disturbance block | below zero = model predicts a LOWER EFP value (not worse accuracy)", TRUE)
  # Spearman correlation, one test per EFP panel; BH-FDR across all 12 tests
  # in this board (4 EFPs x panels C+D+E), same convention as the other
  # figures' significance tests. E is D repeated with relative_disturbance
  # (500m, max across years) on the x axis instead of tree cover.
  statC <- cor_stats(dR, "tree_cover",      "delta_rmse")[,  panel := "C"]
  statD <- cor_stats(sh, "tree_cover",      "dist_signed")[, panel := "D"]
  statE <- cor_stats(sh, "rel_disturbance", "dist_signed")[, panel := "E"]
  stat_all <- rbindlist(list(statC, statD, statE))
  stat_all[, q := p.adjust(p, method = "BH")]
  stat_all[, lab := ifelse(is.na(rho), "",
                           sprintf("rho=%.2f%s\nn=%d", rho, stars(q), n))]
  stat_all[, response := factor(response, levels = EFP_ORDER)]
  labC <- stat_all[panel == "C"]; labD <- stat_all[panel == "D"]; labE <- stat_all[panel == "E"]

  pC <- scatter_tc(dR, "tree_cover", "Tree cover — forest_mean_pct_500m (%)",
                   "delta_rmse", expression(Delta*"RMSE (with D - without D)"),
                   "C · Tree cover vs. disturbance benefit",
                   "Each point = one site | Linear fit with 95% CI | Spearman rho, BH-FDR within this board (*** q<0.001, ** q<0.01, * q<0.05)",
                   TRUE, FALSE, labC)
  pD <- scatter_tc(sh, "tree_cover", "Tree cover — forest_mean_pct_500m (%)",
                   "dist_signed", "Net signed disturbance SHAP\n(effect on PREDICTED value)",
                   "D · Tree cover vs. direction of the disturbance effect",
                   "Each point = one site | Linear fit with 95% CI | below zero = model predicts a LOWER EFP value",
                   TRUE, TRUE, labD)
  pE <- scatter_tc(sh, "rel_disturbance", "Relative disturbance (500m, %, max across years)",
                   "dist_signed", "Net signed disturbance SHAP\n(effect on PREDICTED value)",
                   "E · Relative disturbance vs. direction of the disturbance effect",
                   "Each point = one site | Linear fit with 95% CI | below zero = model predicts a LOWER EFP value",
                   TRUE, TRUE, labE)

  board <- (pA / pB / pC / pD / pE) +
    plot_annotation(
      title = sprintf("IGBP board — %s | %s window  (%s dataset)", s$label, s$win, dataset_type),
      theme = theme(plot.title = element_text(colour = TEXT_COL, size = 14, face = "bold"),
                    plot.background = element_rect(fill = DARK_BG, colour = NA))
    ) & theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

  stem <- file.path(out_dir, sprintf("board_IGBP_%s", s$wd))
  ggsave(paste0(stem, ".png"), board, width = 14, height = 25, dpi = 190, bg = DARK_BG, limitsize = FALSE)
  ggsave(paste0(stem, ".pdf"), board, width = 14, height = 25, bg = DARK_BG, limitsize = FALSE)
  cat(sprintf("  ✓ %s\n", basename(stem)))
}
cat("\n✅ V10 IGBP BOARDS COMPLETE\n")
cat("   Output:", out_dir, "\n")

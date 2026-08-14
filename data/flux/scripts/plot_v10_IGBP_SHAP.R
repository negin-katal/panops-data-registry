#!/usr/bin/env Rscript
# ============================================================================
# V10: Disturbance SHAP % by IGBP class (Panel A) + SHAP % vs tree cover (Panel C)
# One figure each, per SHAP model (M4, M6_raw/anom, M8_raw/anom x 12m/24m).
# Style = fig_IGBP_treecover. dist_pct = % of per-site SHAP from disturbance vars.
# ============================================================================

library(data.table)
library(ggplot2)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_IGBP_SHAP.R <dataset_type>")
dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 IGBP SHAP: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep = "")

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")
IGBP_COL <- c(ENF="#1F6B3A", EBF="#33A14A", DNF="#7BC87E", DBF="#B2DF8A",
              MF="#FDBF6F", CSH="#E5820B", OSH="#D4A017", WSA="#C4A85C",
              SAV="#E8D44D", WET="#4DAECC")
EFP_ORDER <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")

if (dataset_type == "filtered") {
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_site_shap_M04_M08.csv"
  out_igbp  <- "plots/V10/sites_with_high_Tcover/SHAP_percent/IGBP"
  out_tc    <- "plots/V10/sites_with_high_Tcover/SHAP_percent/treecover"
} else if (dataset_type == "tc50") {
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10_tc50/RF_site_shap_M04_M08.csv"
  out_igbp  <- "plots/V10/sites_tc50/SHAP_percent/IGBP"
  out_tc    <- "plots/V10/sites_tc50/SHAP_percent/treecover"
} else if (dataset_type == "all_sites") {
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_site_shap_M04_M08.csv"
  out_igbp  <- "plots/V10/all_sites/SHAP_percent/IGBP"
  out_tc    <- "plots/V10/all_sites/SHAP_percent/treecover"
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

# ── site metadata ────────────────────────────────────────────
main <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv",
              select = c("SITE_ID", "IGBP", "forest_mean_pct_500m"))
site_meta <- main[, .(tree_cover = mean(forest_mean_pct_500m, na.rm = TRUE)), by = .(SITE_ID, IGBP)]
site_meta <- site_meta[, .SD[1], by = SITE_ID]
site_meta[, IGBP := factor(IGBP, levels = IGBP_ORDER)]

# ── per-site disturbance SHAP % ──────────────────────────────
shap <- fread(shap_file)
shap[, is_dist := grepl("^(absolute_|relative_|new_mortality|disturbance_)", variable)]
shap_sum <- shap[, .(total = sum(mean_abs_shap, na.rm = TRUE),
                     dist = sum(mean_abs_shap[is_dist], na.rm = TRUE)),
                 by = .(model, response, test_site)]
shap_sum[, dist_pct := dist / total * 100]
shap_sum <- shap_sum[is.finite(dist_pct)]

models <- c("M4_12m","M4_24m","M6_raw_12m","M6_raw_24m","M6_anom_12m","M6_anom_24m",
            "M8_raw_12m","M8_raw_24m","M8_anom_12m","M8_anom_24m")
MODEL_LAB <- c(M4="M4 (C+T+D)", M6_raw="M6 raw (C+D+Mem)", M6_anom="M6 anom (C+D+Mem)",
               M8_raw="M8 raw (C+T+D+Mem)", M8_anom="M8 anom (C+T+D+Mem)")

cat("Generating figures:\n")
for (mod in models) {
  d <- shap_sum[model == mod]
  if (nrow(d) == 0) { cat("  skip:", mod, "\n"); next }
  d <- merge(d, site_meta, by.x = "test_site", by.y = "SITE_ID")
  d <- d[response %in% EFP_ORDER & !is.na(IGBP)]
  d[, response := factor(response, levels = EFP_ORDER)]
  base <- sub("_(12m|24m)$", "", mod); win <- regmatches(mod, regexpr("(12m|24m)", mod))
  lab <- sprintf("%s | %s", MODEL_LAB[[base]], win)

  # Panel A: violin SHAP% by IGBP
  pA <- ggplot(d, aes(x = IGBP, y = dist_pct, fill = IGBP)) +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.3) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    stat_summary(fun = mean, geom = "point", colour = "yellow", size = 1.2, shape = 18) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    facet_wrap(~response, nrow = 1, labeller = EFP_LAB) +
    labs(x = NULL, y = "Disturbance SHAP (%)",
         title = sprintf("Disturbance SHAP %% by IGBP class — %s", lab),
         subtitle = "White dot = median | Yellow diamond = mean | % of per-site SHAP from disturbance variables") +
    dark_theme +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 6.5, face = "bold", angle = 45, hjust = 1))
  ggsave(file.path(out_igbp, sprintf("IGBP_SHAP_%s.png", mod)), pA, width = 18, height = 5, dpi = 200, bg = DARK_BG)
  ggsave(file.path(out_igbp, sprintf("IGBP_SHAP_%s.pdf", mod)), pA, width = 18, height = 5, bg = DARK_BG)

  # Panel C: tree cover vs SHAP%
  pC <- ggplot(d, aes(x = tree_cover, y = dist_pct, colour = IGBP)) +
    geom_point(size = 1.4, alpha = 0.7) +
    geom_smooth(aes(group = 1), method = "loess", span = 0.9, colour = "white",
                fill = "#444444", linewidth = 0.7, se = TRUE) +
    scale_colour_manual(values = IGBP_COL, name = "IGBP") +
    guides(colour = guide_legend(override.aes = list(size = 2.5, alpha = 1), ncol = 1)) +
    facet_wrap(~response, nrow = 1, labeller = EFP_LAB) +
    labs(x = "Tree cover — forest_mean_pct_500m (%)", y = "Disturbance SHAP (%)",
         title = sprintf("Tree cover vs. disturbance SHAP importance — %s", lab),
         subtitle = "Each point = one site | Loess trend with 95% CI") +
    dark_theme + theme(legend.position = "right")
  ggsave(file.path(out_tc, sprintf("treecover_SHAP_%s.png", mod)), pC, width = 16, height = 4.5, dpi = 200, bg = DARK_BG)
  ggsave(file.path(out_tc, sprintf("treecover_SHAP_%s.pdf", mod)), pC, width = 16, height = 4.5, bg = DARK_BG)

  cat(sprintf("  ✓ %s\n", mod))
}
cat("\n✅ V10 IGBP SHAP COMPLETE\n")

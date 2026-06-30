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

IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")
IGBP_COL <- c(
  ENF = "#1F6B3A", EBF = "#33A14A", DNF = "#7BC87E", DBF = "#B2DF8A",
  MF  = "#FDBF6F", CSH = "#E5820B", OSH = "#D4A017", WSA = "#C4A85C",
  SAV = "#E8D44D", WET = "#4DAECC"
)

# Forest = closed canopy; Open = shrubland/savanna; Wet = wetland
IGBP_GROUP <- c(
  ENF = "Forest", EBF = "Forest", DNF = "Forest", DBF = "Forest", MF = "Forest",
  CSH = "Open",   OSH = "Open",   WSA = "Open",   SAV = "Open",
  WET = "Wetland"
)

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
    plot.subtitle    = element_text(colour = AXIS_COL, size = 8),
    legend.background = element_rect(fill = NA),
    legend.key        = element_rect(fill = NA, colour = NA),
    legend.text       = element_text(colour = AXIS_COL, size = 8),
    legend.title      = element_text(colour = AXIS_COL, size = 8.5)
  )

# ── 1) Load site metadata ──────────────────────────────────────────────────────
main <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv")

site_meta <- main[, .(
  dw_mean     = mean(deadwood_mean_pct_500m,  na.rm = TRUE),
  tree_cover  = mean(forest_mean_pct_500m,     na.rm = TRUE)
), by = .(SITE_ID, IGBP)]
# Keep one row per site (IGBP should be constant)
site_meta <- site_meta[, .SD[1], by = SITE_ID]
site_meta[, IGBP := factor(IGBP, levels = IGBP_ORDER)]
site_meta[, igbp_group := IGBP_GROUP[as.character(IGBP)]]

# ── 2) Per-site delta RMSE (C+T vs C+T+D, 24m anomaly) ───────────────────────
preds <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_predictions_LOSO.csv")
preds[, model_key := sub("_(12m|24m)_.*", "", model)]
preds[, window    := regmatches(model, regexpr("(12m|24m)", model))]
preds[, response  := sub(".*_(12m|24m)_", "", model)]

site_rmse <- preds[model_key %in% c("M03","M04") & window == "24m",
  .(rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))),
  by = .(model_key, response, SITE_ID)]

base_dt <- site_rmse[model_key == "M03", .(SITE_ID, response, rmse_base = rmse)]
dist_dt <- site_rmse[model_key == "M04", .(SITE_ID, response, rmse_dist = rmse)]
delta    <- merge(base_dt, dist_dt, by = c("SITE_ID","response"))
delta[, delta_rmse := rmse_dist - rmse_base]
delta    <- merge(delta, site_meta, by = "SITE_ID")

# ── 3) SHAP disturbance % per site (M04, 24m, GPPsat) ────────────────────────
shap <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_site_shap_M04_M08.csv")
shap_m04 <- shap[grepl("^M04_24m_", model)]
shap_m04[, response := sub("M04_24m_", "", model)]

shap_total <- shap_m04[, .(total_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]
shap_dist  <- shap_m04[group == "Disturbance",
  .(dist_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]
shap_pct   <- merge(shap_total, shap_dist, by = c("SITE_ID","response"))
shap_pct[, dist_pct := dist_shap / total_shap * 100]
shap_pct   <- merge(shap_pct, site_meta, by = "SITE_ID")
shap_pct[, IGBP := factor(IGBP, levels = IGBP_ORDER)]

# ── 4) Fig A: delta RMSE by IGBP — all 4 EFPs ────────────────────────────────
# Fix IGBP order by mean delta of GPPsat (consistent across panels)
igbp_order_gpp <- delta[response == "GPPsat",
  .(mean_d = mean(delta_rmse, na.rm = TRUE)), by = IGBP][order(-mean_d), as.character(IGBP)]
delta[, IGBP_ord := factor(IGBP, levels = igbp_order_gpp)]

EFP_LABELLER <- as_labeller(c(
  GPPsat = "GPPsat",
  NEPmax = "NEPmax",
  ETmax  = "ETmax",
  uWUE   = "uWUE",
  WUE    = "WUE"
))

delta[, response := factor(response, levels = c("GPPsat","NEPmax","ETmax","uWUE","WUE"))]

p_igbp <- ggplot(delta, aes(x = IGBP_ord, y = delta_rmse, fill = IGBP_ord)) +
  geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4, linetype = "dashed") +
  geom_violin(trim = TRUE, scale = "width", width = 0.75,
              colour = NA, alpha = 0.85) +
  geom_boxplot(width = 0.18, outlier.shape = NA,
               colour = "white", fill = NA, linewidth = 0.3) +
  stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
  stat_summary(fun = mean,   geom = "point", colour = "yellow", size = 1.2, shape = 18) +
  scale_fill_manual(values = IGBP_COL, guide = "none") +
  facet_wrap(~response, nrow = 2, scales = "free_y",
             labeller = EFP_LABELLER) +
  labs(
    x        = NULL,
    y        = expression(Delta*"RMSE  (with D - without D)"),
    title    = "Effect of adding disturbance (D) on per-site RMSE by IGBP class",
    subtitle = "White dot = median | Yellow diamond = mean | Anomaly memory, 24m window | negative = D improved"
  ) +
  dark_theme +
  theme(axis.text.x = element_text(colour = AXIS_COL, size = 8, face = "bold"))

# ── 5) Fig B: tree cover vs delta RMSE — all 4 EFPs ──────────────────────────
p_tc_delta <- ggplot(delta, aes(x = tree_cover, y = delta_rmse, colour = IGBP)) +
  geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.35, linetype = "dashed") +
  geom_point(size = 1.4, alpha = 0.7) +
  geom_smooth(aes(group = 1), method = "loess", span = 0.9,
              colour = "white", fill = "#444444", linewidth = 0.7, se = TRUE) +
  scale_colour_manual(values = IGBP_COL, name = "IGBP") +
  guides(colour = guide_legend(override.aes = list(size = 2.5, alpha = 1), ncol = 1)) +
  facet_wrap(~response, nrow = 1, scales = "free_y",
             labeller = EFP_LABELLER) +
  labs(
    x        = "Tree cover — forest_mean_pct_500m (%)",
    y        = expression(Delta*"RMSE  (with D - without D)"),
    title    = "Tree cover vs. disturbance benefit — all EFPs",
    subtitle = "Each point = one site | Loess trend with 95% CI"
  ) +
  dark_theme +
  theme(legend.position = "right")

# ── 6) Fig C: tree cover vs SHAP disturbance % — all 4 EFPs ──────────────────
shap_pct[, response := factor(response, levels = c("GPPsat","NEPmax","ETmax","uWUE","WUE"))]

p_tc_shap <- ggplot(shap_pct, aes(x = tree_cover, y = dist_pct, colour = IGBP)) +
  geom_point(size = 1.4, alpha = 0.7) +
  geom_smooth(aes(group = 1), method = "loess", span = 0.9,
              colour = "white", fill = "#444444", linewidth = 0.7, se = TRUE) +
  scale_colour_manual(values = IGBP_COL, name = "IGBP", guide = "none") +
  facet_wrap(~response, nrow = 1, labeller = EFP_LABELLER) +
  labs(
    x        = "Tree cover — forest_mean_pct_500m (%)",
    y        = "Disturbance SHAP (%)",
    title    = "Tree cover vs. disturbance SHAP importance — all EFPs",
    subtitle = "M04 (C+T+D), 24m | % of per-site SHAP from disturbance variables"
  ) +
  dark_theme

# ── 7) Compose and save ───────────────────────────────────────────────────────
fig <- (p_igbp / p_tc_delta / p_tc_shap) +
  plot_layout(heights = c(2, 1, 1)) +
  plot_annotation(
    theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA))
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

stem <- file.path(OUT_DIR, "fig_IGBP_treecover")
ggsave(paste0(stem, ".png"), fig,
       width = 220, height = 280, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig,
       width = 220, height = 280, units = "mm", bg = DARK_BG)
cat("\n=== Saved:", stem, "===\n")

# ── 8) Print correlations for all EFPs ────────────────────────────────────────
cat("\nCorrelation: tree_cover vs delta_rmse by EFP:\n")
for (resp in c("GPPsat","NEPmax","ETmax","uWUE","WUE")) {
  sub <- delta[response == resp]
  r <- cor(sub$tree_cover, sub$delta_rmse, use = "complete.obs")
  cat(sprintf("  %-8s  r = %+.3f\n", resp, r))
}

cat("\nCorrelation: tree_cover vs dist_pct SHAP by EFP:\n")
for (resp in c("GPPsat","NEPmax","ETmax","uWUE","WUE")) {
  sub <- shap_pct[response == resp]
  if (nrow(sub) < 3) { cat(sprintf("  %-8s  no SHAP data\n", resp)); next }
  r <- cor(sub$tree_cover, sub$dist_pct, use = "complete.obs")
  cat(sprintf("  %-8s  r = %+.3f\n", resp, r))
}

cat("\nMean tree cover by IGBP group:\n")
print(site_meta[, .(mean_tc = round(mean(tree_cover, na.rm=TRUE),1), n = .N),
                by = igbp_group][order(-mean_tc)])

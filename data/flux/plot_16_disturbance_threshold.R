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

TIER_COLS <- c(
  "Low (<5%)"    = "#4DAECC",
  "Medium (5-12%)" = "#F0A500",
  "High (>12%)"  = "#E8257A"
)

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
EFP_LABELS <- c(
  GPPsat = expression(GPP[sat]),
  NEPmax = expression(NEP[max]),
  ETmax  = expression(ET[max]),
  uWUE   = "uWUE",
  WUE    = "WUE"
)

# ── 1) Site disturbance tier ───────────────────────────────────────────────────
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv")

site_dw <- main_data[, .(dw_mean = mean(deadwood_mean_pct_500m, na.rm = TRUE)),
                     by = SITE_ID]
site_dw[, tier := fcase(
  dw_mean <  5,  "Low (<5%)",
  dw_mean < 12,  "Medium (5-12%)",
  default =      "High (>12%)"
)]
site_dw[, tier := factor(tier, levels = c("Low (<5%)", "Medium (5-12%)", "High (>12%)"))]

cat("Tier distribution:\n")
print(site_dw[, .N, by = tier][order(tier)])

# ── 2) Per-site RMSE from predictions (anomaly 24mbench only) ─────────────────
pred_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_predictions_LOSO.csv"
preds <- fread(pred_file)

# Extract model_key, window, response from model column (format: M0N_WWm_RESPONSE)
preds[, model_key := sub("_(12m|24m)_.*", "", model)]
preds[, window    := regmatches(model, regexpr("(12m|24m)", model))]
preds[, response  := sub(".*_(12m|24m)_", "", model)]

# Keep only the 4 models of interest and 24m window
preds_sub <- preds[model_key %in% c("M01","M02","M03","M04") & window == "24m"]

site_rmse <- preds_sub[, .(
  rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))
), by = .(model_key, response, SITE_ID)]

# ── 3) Delta RMSE: negative = D helped (with D - without D) ────────────────────────────────────────
# Comparison A: M01 (C) vs M02 (C+D)
# Comparison B: M03 (C+T) vs M04 (C+T+D)

make_delta <- function(base_key, dist_key, label) {
  base <- site_rmse[model_key == base_key, .(SITE_ID, response, rmse_base = rmse)]
  dist <- site_rmse[model_key == dist_key, .(SITE_ID, response, rmse_dist = rmse)]
  merged <- merge(base, dist, by = c("SITE_ID", "response"))
  merged[, delta_rmse := rmse_dist - rmse_base]  # negative = improvement
  merged[, comparison := label]
  merged
}

delta <- rbindlist(list(
  make_delta("M01", "M02", "C vs C+D"),
  make_delta("M03", "M04", "C+T vs C+T+D")
))

delta <- merge(delta, site_dw[, .(SITE_ID, tier, dw_mean)], by = "SITE_ID")
delta[, response := factor(response, levels = EFP_ORDER)]

cat("\nDelta RMSE summary by tier and comparison (GPPsat):\n")
print(delta[response == "GPPsat",
  .(mean_delta = round(mean(delta_rmse, na.rm=TRUE), 4),
    n = .N),
  by = .(comparison, tier)][order(comparison, tier)])

# ── 4) Plot: delta RMSE by tier ────────────────────────────────────────────────
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

make_tier_panel <- function(comp_label, tag, show_x = FALSE) {
  sub <- delta[comparison == comp_label]

  p <- ggplot(sub, aes(x = tier, y = delta_rmse, fill = tier)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
    geom_violin(trim = TRUE, scale = "width", width = 0.75,
                colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA,
                 colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point",
                 colour = "white", size = 1.2) +
    scale_fill_manual(values = TIER_COLS) +
    facet_wrap(~response, nrow = 1, scales = "free_y",
               labeller = as_labeller(c(
                 GPPsat = "GPPsat", NEPmax = "NEPmax",
                 ETmax = "ETmax", uWUE = "uWUE", WUE = "WUE"
               ))) +
    labs(
      tag   = tag,
      x     = if (show_x) "Deadwood tier (deadwood_mean_pct_500m)" else NULL,
      y     = expression(Delta*"RMSE  (with D − without D)"),
      title = comp_label
    ) +
    dark_theme

  if (!show_x) {
    p <- p + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
  } else {
    p <- p + theme(axis.text.x = element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1))
  }
  p
}

p_a <- make_tier_panel("C vs C+D",     "a", show_x = FALSE)
p_b <- make_tier_panel("C+T vs C+T+D", "b", show_x = TRUE)

fig_delta <- (p_a / p_b) +
  plot_annotation(
    title    = "Does D benefit more sites with higher accumulated deadwood?",
    subtitle = "Anomaly memory | 24m window | negative dRMSE = D improved prediction",
    theme    = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title    = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

stem <- file.path(OUT_DIR, "fig_threshold_delta_RMSE")
ggsave(paste0(stem, ".png"), fig_delta,
       width = 220, height = 160, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig_delta,
       width = 220, height = 160, units = "mm", bg = DARK_BG)
cat("\nDelta RMSE figure saved:", stem, "\n")

# ── 5) SHAP disturbance contribution by tier ───────────────────────────────────
shap <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_site_shap_M04_M08.csv")

# Keep M04 (C+T+D) models, 24m window
shap_m04 <- shap[grepl("^M04_24m_", model)]
shap_m04[, response := sub("M04_24m_", "", model)]

# Total SHAP per site × response
shap_total <- shap_m04[, .(total_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]
shap_dist  <- shap_m04[group == "Disturbance",
  .(dist_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]

shap_pct <- merge(shap_total, shap_dist, by = c("SITE_ID", "response"))
shap_pct[, dist_pct := dist_shap / total_shap * 100]
shap_pct <- merge(shap_pct, site_dw[, .(SITE_ID, tier)], by = "SITE_ID")
shap_pct[, response := factor(response, levels = EFP_ORDER)]

cat("\nSHAP disturbance % by tier and response:\n")
print(shap_pct[, .(mean_dist_pct = round(mean(dist_pct, na.rm=TRUE), 1), n = .N),
               by = .(response, tier)][order(response, tier)])

p_shap <- ggplot(shap_pct, aes(x = tier, y = dist_pct, fill = tier)) +
  geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4) +
  geom_violin(trim = TRUE, scale = "width", width = 0.75,
              colour = NA, alpha = 0.85) +
  geom_boxplot(width = 0.18, outlier.shape = NA,
               colour = "white", fill = NA, linewidth = 0.35) +
  stat_summary(fun = median, geom = "point",
               colour = "white", size = 1.2) +
  scale_fill_manual(values = TIER_COLS) +
  facet_wrap(~response, nrow = 1) +
  labs(
    title    = "SHAP contribution of Disturbance group by deadwood tier  (M04, 24m)",
    subtitle = "C+T+D model | % of total per-site SHAP explained by disturbance variables",
    x        = "Deadwood tier (deadwood_mean_pct_500m)",
    y        = "Disturbance SHAP (%)"
  ) +
  dark_theme +
  theme(
    axis.text.x  = element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1),
    plot.title   = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle = element_text(colour = AXIS_COL, size = 8)
  )

stem2 <- file.path(OUT_DIR, "fig_threshold_SHAP")
ggsave(paste0(stem2, ".png"), p_shap,
       width = 220, height = 90, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem2, ".pdf"), p_shap,
       width = 220, height = 90, units = "mm", bg = DARK_BG)
cat("SHAP figure saved:", stem2, "\n")

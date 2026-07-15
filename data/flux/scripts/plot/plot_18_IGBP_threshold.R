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

TIER_COLS <- c(
  "Low (<5%)"      = "#4DAECC",
  "Medium (5-12%)" = "#F0A500",
  "High (>12%)"    = "#E8257A"
)
TIER_LEVELS <- c("Low (<5%)", "Medium (5-12%)", "High (>12%)")

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background   = element_rect(fill = DARK_BG,  colour = NA),
    panel.background  = element_rect(fill = PANEL_BG, colour = NA),
    panel.border      = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major  = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor  = element_blank(),
    strip.background  = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text        = element_text(colour = TEXT_COL, size = 8.5, face = "bold"),
    axis.text         = element_text(colour = AXIS_COL, size = 7.5),
    axis.title        = element_text(colour = AXIS_COL, size = 8.5),
    plot.tag          = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.title        = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle     = element_text(colour = AXIS_COL, size = 8),
    legend.background = element_rect(fill = NA),
    legend.key        = element_rect(fill = NA, colour = NA),
    legend.text       = element_text(colour = AXIS_COL, size = 8),
    legend.title      = element_text(colour = AXIS_COL, size = 8.5, face = "bold")
  )

# ── 1) Site metadata ───────────────────────────────────────────────────────────
main <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv")

site_meta <- main[, .(
  dw_mean    = mean(deadwood_mean_pct_500m, na.rm = TRUE),
  tree_cover = mean(forest_mean_pct_500m,   na.rm = TRUE)
), by = .(SITE_ID, IGBP)]
site_meta <- site_meta[, .SD[1], by = SITE_ID]
site_meta[, IGBP := factor(IGBP, levels = IGBP_ORDER)]
site_meta[, tier := factor(fcase(
  dw_mean <  5,  "Low (<5%)",
  dw_mean < 12,  "Medium (5-12%)",
  default =      "High (>12%)"
), levels = TIER_LEVELS)]

# ── 2) Per-site delta RMSE (C+T vs C+T+D, 24m anomaly) ───────────────────────
preds <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_predictions_LOSO.csv")
preds[, model_key := sub("_(12m|24m)_.*", "", model)]
preds[, window    := regmatches(model, regexpr("(12m|24m)", model))]
preds[, response  := sub(".*_(12m|24m)_", "", model)]

site_rmse <- preds[model_key %in% c("M03","M04") & window == "24m",
  .(rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))),
  by = .(model_key, response, SITE_ID)]

delta <- merge(
  site_rmse[model_key == "M03", .(SITE_ID, response, rmse_base = rmse)],
  site_rmse[model_key == "M04", .(SITE_ID, response, rmse_dist = rmse)],
  by = c("SITE_ID","response")
)
delta[, delta_rmse := rmse_dist - rmse_base]
delta <- merge(delta, site_meta, by = "SITE_ID")
delta[, response := factor(response, levels = EFP_ORDER)]

# ── 3) Summary stats: mean ± SE by IGBP × tier × EFP ─────────────────────────
summary_dt <- delta[, .(
  mean_delta = mean(delta_rmse, na.rm = TRUE),
  se_delta   = sd(delta_rmse, na.rm = TRUE) / sqrt(.N),
  n          = .N
), by = .(response, IGBP, tier)]

# Order IGBP by GPPsat mean delta (High tier drives ordering)
igbp_ord <- delta[response == "GPPsat",
  .(mean_d = mean(delta_rmse, na.rm = TRUE)), by = IGBP][order(-mean_d), as.character(IGBP)]
delta[,      IGBP_ord := factor(IGBP, levels = igbp_ord)]
summary_dt[, IGBP_ord := factor(IGBP, levels = igbp_ord)]

# ── 4) Plot factory: one panel per EFP ────────────────────────────────────────
make_efp_panel <- function(resp, tag, show_legend = FALSE, show_x = TRUE) {
  raw <- delta[response == resp]
  sum <- summary_dt[response == resp]

  p <- ggplot() +
    geom_hline(yintercept = 0, colour = "#666666", linewidth = 0.45, linetype = "dashed") +
    # Raw site points (jittered, semi-transparent)
    geom_point(data = raw,
               aes(x = IGBP_ord, y = delta_rmse, colour = tier),
               position = position_dodge(width = 0.7),
               size = 0.9, alpha = 0.35, show.legend = FALSE) +
    # Mean ± SE
    geom_errorbar(data = sum,
                  aes(x = IGBP_ord, ymin = mean_delta - se_delta,
                      ymax = mean_delta + se_delta, colour = tier),
                  position = position_dodge(width = 0.7),
                  width = 0.25, linewidth = 0.6) +
    geom_point(data = sum,
               aes(x = IGBP_ord, y = mean_delta, colour = tier, shape = tier),
               position = position_dodge(width = 0.7),
               size = 2.4, stroke = 0.5) +
    # n label below x axis ticks (for High tier only, to avoid clutter)
    geom_text(data = sum[tier == "High (>12%)"],
              aes(x = IGBP_ord, y = -Inf, label = paste0("n=",n)),
              colour = "#E8257A", size = 2.0, vjust = 2.2,
              position = position_dodge(width = 0.7)) +
    scale_colour_manual(values = TIER_COLS, name = "Deadwood tier",
                        guide = if (show_legend) "legend" else "none") +
    scale_shape_manual(values = c("Low (<5%)" = 16, "Medium (5-12%)" = 17, "High (>12%)" = 18),
                       name = "Deadwood tier",
                       guide = if (show_legend) "legend" else "none") +
    labs(
      tag = tag,
      x   = if (show_x) "IGBP class" else NULL,
      y   = expression(Delta*"RMSE  (with D - without D)"),
      title = resp
    ) +
    dark_theme +
    theme(
      plot.title   = element_text(colour = "#AAAAAA", size = 9, face = "bold"),
      axis.text.x  = if (show_x)
        element_text(colour = AXIS_COL, size = 8, face = "bold")
      else
        element_blank(),
      axis.ticks.x = if (show_x) element_line() else element_blank(),
      plot.margin  = margin(4, 6, if (show_x) 14 else 4, 6)
    )

  if (show_legend) {
    p <- p + theme(
      legend.position  = "bottom",
      legend.direction = "horizontal"
    ) + guides(
      colour = guide_legend(override.aes = list(size = 3, alpha = 1)),
      shape  = guide_legend(override.aes = list(size = 3))
    )
  }
  p
}

p1 <- make_efp_panel("GPPsat", "a", show_legend = FALSE, show_x = FALSE)
p2 <- make_efp_panel("NEPmax", "b", show_legend = FALSE, show_x = FALSE)
p3 <- make_efp_panel("ETmax",  "c", show_legend = FALSE, show_x = FALSE)
p4 <- make_efp_panel("uWUE",  "d", show_legend = FALSE, show_x = FALSE)
p5 <- make_efp_panel("WUE",   "e", show_legend = TRUE,  show_x = TRUE)

# ── 5) Compose ────────────────────────────────────────────────────────────────
fig <- (p1 / p2 / p3 / p4 / p5) +
  plot_layout(heights = c(1, 1, 1, 1, 1.25)) +
  plot_annotation(
    title    = "Disturbance benefit by IGBP class and deadwood level  (C+T vs C+T+D)",
    subtitle = "Points = mean dRMSE (with D - without D) | bars = +/-1 SE | negative = D improved | pink n = sites in High tier",
    theme    = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title      = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle   = element_text(colour = AXIS_COL, size = 8)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

stem <- file.path(OUT_DIR, "fig_IGBP_threshold")
ggsave(paste0(stem, ".png"), fig,
       width = 200, height = 260, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig,
       width = 200, height = 260, units = "mm", bg = DARK_BG)
cat("\n=== Saved:", stem, "===\n")

# Quick summary table
cat("\nMean delta RMSE by IGBP × tier (GPPsat):\n")
print(summary_dt[response == "GPPsat",
  .(IGBP, tier, n, mean = round(mean_delta, 3))][order(IGBP, tier)])

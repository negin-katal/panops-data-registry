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

# One colour per comparison pair (model complexity increases left→right)
PAIR_COLS <- c(
  "C vs C+D"         = "#22D4EB",
  "C+T vs C+T+D"     = "#3BA0FF",
  "C+M vs C+D+M"     = "#F0A500",
  "C+T+M vs C+T+D+M" = "#E8257A"
)
PAIR_SHAPES <- c(
  "C vs C+D"         = 16,
  "C+T vs C+T+D"     = 17,
  "C+M vs C+D+M"     = 15,
  "C+T+M vs C+T+D+M" = 18
)

TIER_LEVELS <- c("Low (<5%)", "Medium (5-12%)", "High (>12%)")
EFP_ORDER   <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
EFP_UNITS   <- c(
  GPPsat = "GPPsat  (umol/m2/s)",
  NEPmax = "NEPmax  (umol/m2/s)",
  ETmax  = "ETmax   (mm/d)",
  uWUE  = "uWUE   (gC/mm)",
  WUE   = "WUE    (gC/mm)"
)

PAIRS <- list(
  list(base = "M01", dist = "M02", label = "C vs C+D"),
  list(base = "M03", dist = "M04", label = "C+T vs C+T+D"),
  list(base = "M05", dist = "M06", label = "C+M vs C+D+M"),
  list(base = "M07", dist = "M08", label = "C+T+M vs C+T+D+M")
)

PANEL_DEFS <- list(
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_predictions_LOSO.csv",
       win = "24m", mem = "Anomaly"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_v2/RF_predictions_LOSO.csv",
       win = "24m", mem = "Raw-lag")
)

# ── 1) Site deadwood tier ──────────────────────────────────────────────────────
main <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv")
site_tier <- main[, .(dw_mean = mean(deadwood_mean_pct_500m, na.rm = TRUE)), by = SITE_ID]
site_tier[, tier := factor(fcase(
  dw_mean <  5,  "Low (<5%)",
  dw_mean < 12,  "Medium (5-12%)",
  default =      "High (>12%)"
), levels = TIER_LEVELS)]

# ── 2) Per-site delta RMSE for all 4 pairs × 2 configs ────────────────────────
load_delta <- function(pred_file, win_label, mem_label) {
  dt <- fread(pred_file)
  dt <- dt[grepl(paste0("_", win_label, "_"), model)]
  dt[, model_key := sub(paste0("_(", win_label, ")_.*"), "", model)]
  dt[, response  := sub(paste0(".*_", win_label, "_"), "", model)]

  site_rmse <- dt[, .(
    rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))
  ), by = .(model_key, response, SITE_ID)]

  rbindlist(lapply(PAIRS, function(pr) {
    base_r <- site_rmse[model_key == pr$base, .(SITE_ID, response, rmse_base = rmse)]
    dist_r <- site_rmse[model_key == pr$dist, .(SITE_ID, response, rmse_dist = rmse)]
    merged <- merge(base_r, dist_r, by = c("SITE_ID", "response"))
    merged[, delta   := rmse_dist - rmse_base]
    merged[, pair    := pr$label]
    merged[, memory  := mem_label]
    merged
  }))
}

all_delta <- rbindlist(lapply(PANEL_DEFS, function(p)
  load_delta(p$file, p$win, p$mem)))

all_delta <- merge(all_delta, site_tier, by = "SITE_ID")
all_delta[, response := factor(response, levels = EFP_ORDER)]
all_delta[, pair     := factor(pair, levels = names(PAIR_COLS))]
all_delta[, memory   := factor(memory, levels = c("Anomaly", "Raw-lag"))]

# ── 3) Summary: mean ± SE per tier × pair × response × memory ─────────────────
sum_dt <- all_delta[, .(
  mean_d = mean(delta, na.rm = TRUE),
  se_d   = sd(delta,   na.rm = TRUE) / sqrt(.N),
  n      = .N
), by = .(response, memory, pair, tier)]

# ── 4) Theme ──────────────────────────────────────────────────────────────────
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
    legend.background = element_rect(fill = NA),
    legend.key        = element_rect(fill = NA, colour = NA),
    legend.text       = element_text(colour = AXIS_COL, size = 7.5),
    legend.title      = element_text(colour = AXIS_COL, size = 8, face = "bold"),
    plot.tag          = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.title        = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle     = element_text(colour = AXIS_COL, size = 8)
  )

# ── 5) Panel factory: one EFP row, columns = Anomaly | Raw-lag ────────────────
make_row <- function(resp, tag, show_legend = FALSE, show_x = TRUE) {

  raw <- all_delta[response == resp]
  sum <- sum_dt[response == resp]

  p <- ggplot() +
    geom_hline(yintercept = 0, colour = "#555555", linewidth = 0.4, linetype = "dashed") +
    # Raw site jitter (thin, behind)
    geom_point(data = raw,
               aes(x = tier, y = delta, colour = pair),
               position = position_jitterdodge(jitter.width = 0.15, dodge.width = 0.7),
               size = 0.6, alpha = 0.25, show.legend = FALSE) +
    # Boxplot summaries (no outlier dots — raw points already shown)
    geom_boxplot(data = raw,
                 aes(x = tier, y = delta, colour = pair),
                 position  = position_dodge(width = 0.7),
                 width = 0.14, fill = NA, outlier.shape = NA,
                 linewidth = 0.5, show.legend = FALSE) +
    # Mean point
    geom_point(data = sum,
               aes(x = tier, y = mean_d, colour = pair, shape = pair),
               position = position_dodge(width = 0.7),
               size = 2.8, stroke = 0.4) +
    # SE error bar
    geom_errorbar(data = sum,
                  aes(x = tier, ymin = mean_d - se_d, ymax = mean_d + se_d, colour = pair),
                  position = position_dodge(width = 0.7),
                  width = 0.18, linewidth = 0.6, show.legend = FALSE) +
    scale_colour_manual(values = PAIR_COLS, name = "Comparison") +
    scale_shape_manual(values  = PAIR_SHAPES, name = "Comparison") +
    facet_wrap(~memory, nrow = 1) +
    labs(
      tag   = tag,
      x     = if (show_x) "Deadwood tier  (deadwood_mean_pct_500m)" else NULL,
      y     = EFP_UNITS[[resp]],
      title = resp
    ) +
    dark_theme +
    theme(
      plot.title   = element_text(colour = "#AAAAAA", size = 8.5, face = "bold"),
      axis.text.x  = if (show_x)
                       element_text(colour = AXIS_COL, size = 7.5, angle = 12, hjust = 1)
                     else element_blank(),
      axis.ticks.x = if (show_x) element_line() else element_blank()
    )

  if (show_legend) {
    p <- p + theme(legend.position = "bottom", legend.direction = "horizontal") +
      guides(
        colour = guide_legend(override.aes = list(size = 3, alpha = 1), nrow = 2),
        shape  = guide_legend(nrow = 2)
      )
  } else {
    p <- p + theme(legend.position = "none")
  }
  p
}

p1 <- make_row("GPPsat", "a", show_x = FALSE)
p2 <- make_row("NEPmax", "b", show_x = FALSE)
p3 <- make_row("ETmax",  "c", show_x = FALSE)
p4 <- make_row("uWUE",  "d", show_x = FALSE)
p5 <- make_row("WUE",   "e", show_legend = TRUE, show_x = TRUE)

# ── 6) Compose ────────────────────────────────────────────────────────────────
fig <- (p1 / p2 / p3 / p4 / p5) +
  plot_layout(heights = c(1, 1, 1, 1, 1.4)) +
  plot_annotation(
    title    = "Effect of adding disturbance (D) on per-site RMSE by deadwood tier",
    subtitle = "dRMSE = RMSE(with D) - RMSE(without D) | negative = D improved | 24m window | mean +/- SE + boxplot",
    theme    = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title      = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle   = element_text(colour = AXIS_COL, size = 8)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

stem <- file.path(OUT_DIR, "fig2b_RMSE_threshold")
ggsave(paste0(stem, ".png"), fig,
       width = 180, height = 260, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig,
       width = 180, height = 260, units = "mm", bg = DARK_BG)
cat("\n=== Saved:", stem, "===\n")

# Summary for inspection
cat("\nMean dRMSE by tier × pair (GPPsat, Anomaly 24m):\n")
print(sum_dt[response == "GPPsat" & memory == "Anomaly",
  .(pair, tier, n, mean = round(mean_d, 3))][order(pair, tier)])

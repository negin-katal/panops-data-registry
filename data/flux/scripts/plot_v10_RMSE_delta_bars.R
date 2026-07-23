#!/usr/bin/env Rscript
# ============================================================================
# V10: Per-site delta RMSE diverging bars — effect of adding Disturbance (D)
# dRMSE = RMSE(with D) - RMSE(without D), matched per site.
#   green = improved (dRMSE < 0), red = worse (dRMSE > 0)
# One figure per EFP; facets = comparison (4 rows) x memtype/window (4 cols).
# Bars sorted by dRMSE within each panel. % of sites improved annotated.
# ============================================================================

library(data.table)
library(ggplot2)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_RMSE_delta_bars.R <dataset_type>")
dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 DELTA RMSE BARS: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep = "")

if (dataset_type == "filtered") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_predictions_LOSO.csv"
  harm_file <- "derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
  out_dir   <- "plots/V10/sites_with_high_Tcover/RMSE"
} else if (dataset_type == "all_sites") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_predictions_LOSO.csv"
  harm_file <- "derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_GPPsat_harmonized.csv"
  out_dir   <- "plots/V10/all_sites/RMSE"
} else stop("Invalid dataset_type")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
# Relative Disturbance natural-break tier colours
COL_LOW  <- "#4A90D9"   # blue  = Low
COL_MID  <- "#9AA0A6"   # grey  = Mid
COL_HIGH <- "#E74C3C"   # red   = High
TIER_COLS <- c(Low = COL_LOW, Mid = COL_MID, High = COL_HIGH)

EFP_ORDER  <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
EFP_LABELS <- c(
  GPPsat = "GPPsat  (µmol m⁻² s⁻¹)", NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
  ETmax = "ETmax  (mm d⁻¹)", uWUE = "uWUE  (g C mm⁻¹)", WUE = "WUE  (g C mm⁻¹)"
)

# per-site RMSE per model
preds <- fread(pred_file)
preds <- preds[is.finite(observed) & is.finite(predicted)]
site_rmse <- preds[, .(rmse = sqrt(mean((observed - predicted)^2))),
                   by = .(model, response, SITE_ID)]

# ── per-site Relative Disturbance tier (natural breaks, 500m, peak) ──
harm <- fread(harm_file, select = c("SITE_ID", "YEAR", "relative_disturbance_500m"))
na_inf <- function(x) { x[!is.finite(x)] <- NA; x }
site_rd <- harm[, .(rd = na_inf(max(relative_disturbance_500m, na.rm = TRUE))), by = SITE_ID]
rd_lo <- mean(site_rd$rd, na.rm = TRUE) - 0.5 * sd(site_rd$rd, na.rm = TRUE)
rd_hi <- mean(site_rd$rd, na.rm = TRUE) + 0.5 * sd(site_rd$rd, na.rm = TRUE)
site_rd[, tier := cut(rd, breaks = c(-Inf, rd_lo, rd_hi, Inf),
                      labels = c("Low", "Mid", "High"))]
cat(sprintf("Relative Disturbance natural breaks: Low<=%.1f  Mid  High>%.1f\n", rd_lo, rd_hi))

PAIR_LEVELS <- c("C vs C+D", "C+T vs C+T+D", "C+M vs C+M+D", "C+T+M vs C+T+D+M")
COL_LEVELS  <- c("Anomaly / 12m", "Anomaly / 24m", "Raw-lag / 12m", "Raw-lag / 24m")

mid <- function(base, memtype, win) {
  if (base %in% c("M1", "M2", "M3", "M4")) return(sprintf("%s_%s", base, win))
  sprintf("%s_%s_%s", base, memtype, win)
}
pairs_def <- list(
  list(pair = "C vs C+D",         wo = "M1", wd = "M2"),
  list(pair = "C+T vs C+T+D",     wo = "M3", wd = "M4"),
  list(pair = "C+M vs C+M+D",     wo = "M5", wd = "M6"),
  list(pair = "C+T+M vs C+T+D+M", wo = "M7", wd = "M8")
)
cols_def <- list(
  list(col = "Anomaly / 12m", mem = "anom", win = "12m"),
  list(col = "Anomaly / 24m", mem = "anom", win = "24m"),
  list(col = "Raw-lag / 12m", mem = "raw",  win = "12m"),
  list(col = "Raw-lag / 24m", mem = "raw",  win = "24m")
)

dark_theme <- theme_bw(base_size = 10) +
  theme(
    plot.background = element_rect(fill = DARK_BG, colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.4),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text = element_text(colour = TEXT_COL, size = 8.5, face = "bold"),
    axis.text.x = element_blank(), axis.ticks.x = element_blank(),
    axis.text.y = element_text(colour = AXIS_COL, size = 7.5),
    axis.title = element_text(colour = AXIS_COL, size = 9, face = "bold"),
    legend.position = "bottom", legend.title = element_blank(),
    legend.background = element_rect(fill = NA, colour = NA),
    legend.key = element_rect(fill = NA, colour = NA),
    legend.text = element_text(colour = TEXT_COL, size = 10),
    plot.title = element_text(colour = TEXT_COL, size = 13, face = "bold"),
    plot.subtitle = element_text(colour = AXIS_COL, size = 9)
  )

n_sites <- uniqueN(preds$SITE_ID)

for (resp in EFP_ORDER) {
  bar_rows <- list(); lab_rows <- list(); bk <- 1; lk <- 1
  for (cd in cols_def) {
    for (pd in pairs_def) {
      m_wo <- mid(pd$wo, cd$mem, cd$win)
      m_wd <- mid(pd$wd, cd$mem, cd$win)
      d_wo <- site_rmse[model == m_wo & response == resp, .(SITE_ID, rmse_wo = rmse)]
      d_wd <- site_rmse[model == m_wd & response == resp, .(SITE_ID, rmse_wd = rmse)]
      if (nrow(d_wo) == 0 || nrow(d_wd) == 0) next
      m <- merge(d_wo, d_wd, by = "SITE_ID")
      m <- merge(m, site_rd[, .(SITE_ID, tier)], by = "SITE_ID", all.x = TRUE)
      m[, dRMSE := rmse_wd - rmse_wo]          # <0 = improved
      setorder(m, dRMSE)
      m[, rank := .I]
      m[, improved := dRMSE < 0]
      m[, `:=`(response = resp, col = cd$col, pair = pd$pair)]
      bar_rows[[bk]] <- m; bk <- bk + 1

      pct_imp <- round(100 * mean(m$improved), 0)
      lab_rows[[lk]] <- data.table(response = resp, col = cd$col, pair = pd$pair,
                                   x = 1, y = Inf,
                                   label = sprintf("%d%% improved", pct_imp)); lk <- lk + 1
    }
  }
  bars <- rbindlist(bar_rows); labs <- rbindlist(lab_rows)
  bars[, col := factor(col, levels = COL_LEVELS)]
  bars[, pair := factor(pair, levels = PAIR_LEVELS)]
  bars[, tier := factor(tier, levels = c("Low", "Mid", "High"))]
  labs[, col := factor(col, levels = COL_LEVELS)]
  labs[, pair := factor(pair, levels = PAIR_LEVELS)]

  p <- ggplot(bars, aes(x = rank, y = dRMSE, fill = tier)) +
    geom_col(width = 1) +
    geom_hline(yintercept = 0, colour = "#BBBBBB", linewidth = 0.3) +
    geom_text(data = labs, aes(x = x, y = y, label = label), inherit.aes = FALSE,
              hjust = 0, vjust = 1.4, size = 2.5, colour = TEXT_COL) +
    scale_fill_manual(values = TIER_COLS, breaks = c("High", "Mid", "Low"),
                      na.value = "grey30", name = "Relative Disturbance (natural breaks)") +
    facet_grid(pair ~ col, scales = "free_y") +
    labs(x = "Sites (sorted by ΔRMSE)", y = "ΔRMSE  =  RMSE(with D) − RMSE(without D)",
         title = sprintf("Per-site ΔRMSE from adding disturbance — %s", EFP_LABELS[resp]),
         subtitle = sprintf("Below 0 = D reduces per-site RMSE | bars coloured by Relative Disturbance tier (blue=Low, grey=Mid, red=High) | LOSO CV | %d sites", n_sites)) +
    dark_theme

  stem <- file.path(out_dir, sprintf("delta_RMSE_bars_%s", resp))
  ggsave(paste0(stem, ".png"), p, width = 14, height = 12, dpi = 200, bg = DARK_BG)
  ggsave(paste0(stem, ".pdf"), p, width = 14, height = 12, bg = DARK_BG)
  cat(sprintf("  ✓ %s\n", basename(stem)))
}

cat("\n✅ V10 DELTA RMSE BARS COMPLETE\n")
cat("   Output:", out_dir, "\n")

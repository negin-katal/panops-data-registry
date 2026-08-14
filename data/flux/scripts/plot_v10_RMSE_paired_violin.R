#!/usr/bin/env Rscript
# ============================================================================
# V10: Per-site RMSE paired violins — effect of adding Disturbance (D)
# Comparisons: M1 vs M2 (C vs C+D), M3 vs M4 (C+T vs C+T+D),
#              M5 vs M6 (C+M vs C+M+D), M7 vs M8 (C+T+M vs C+T+D+M)
# Layout: 5 EFP rows x 4 cols (Anomaly/Raw x 12m/24m). Style = fig2 reference.
# % label above each pair = RMSE reduction from adding D
#   (green = improved, grey = ~no change, red = worse)
# ============================================================================

library(data.table)
library(ggplot2)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_RMSE_paired_violin.R <dataset_type>")
dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 RMSE PAIRED VIOLIN: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep = "")

if (dataset_type == "filtered") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_predictions_LOSO.csv"
  out_dir   <- "plots/V10/sites_with_high_Tcover/RMSE"
} else if (dataset_type == "tc50") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_tc50/RF_predictions_LOSO.csv"
  out_dir   <- "plots/V10/sites_tc50/RMSE"
} else if (dataset_type == "all_sites") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_predictions_LOSO.csv"
  out_dir   <- "plots/V10/all_sites/RMSE"
} else stop("Invalid dataset_type")
## --- optional model-family override (XGBoost etc.); no-op when unset ---
source("scripts/v10_model_family.R"); v10_apply_override()
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# theme / colours (match fig2)
DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
COL_WO <- "#22C4E0"   # cyan  = without D
COL_W  <- "#E8257A"   # pink  = with D
COL_UP <- "#2ECC71"   # green = improved
COL_NC <- "#9AA0A6"   # grey  = no change
COL_DN <- "#E74C3C"   # red   = worse

EFP_ORDER  <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
EFP_LABELS <- c(
  GPPsat = "GPPsat  (µmol m⁻² s⁻¹)", NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
  ETmax = "ETmax  (mm d⁻¹)", uWUE = "uWUE  (g C mm⁻¹)", WUE = "WUE  (g C mm⁻¹)"
)

# ── per-site RMSE per model ──────────────────────────────────
preds <- fread(pred_file)
preds <- preds[is.finite(observed) & is.finite(predicted)]
site_rmse <- preds[, .(rmse = sqrt(mean((observed - predicted)^2))),
                   by = .(model, response, SITE_ID)]

# ── comparison definitions ───────────────────────────────────
PAIR_LEVELS <- c("C vs C+D", "C+T vs C+T+D", "C+M vs C+M+D", "C+T+M vs C+T+D+M")
COL_LEVELS  <- c("Anomaly / 12m", "Anomaly / 24m", "Raw-lag / 12m", "Raw-lag / 24m")

# model id builder given memtype & window
mid <- function(base, memtype, win) {
  if (base %in% c("M1", "M2", "M3", "M4")) return(sprintf("%s_%s", base, win))
  sprintf("%s_%s_%s", base, memtype, win)   # M5..M8 carry memory type
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

# ── assemble long plotting table + % labels ──────────────────
plot_rows <- list(); lab_rows <- list(); k <- 1; lk <- 1
for (cd in cols_def) {
  for (pd in pairs_def) {
    m_wo <- mid(pd$wo, cd$mem, cd$win)
    m_wd <- mid(pd$wd, cd$mem, cd$win)
    for (resp in EFP_ORDER) {
      # pair explicitly on SITE_ID - relying on row order would silently
      # misalign the pairs if a site were missing from one of the two models
      pw <- merge(site_rmse[model == m_wo & response == resp, .(SITE_ID, wo = rmse)],
                  site_rmse[model == m_wd & response == resp, .(SITE_ID, wd = rmse)],
                  by = "SITE_ID")
      pw <- pw[is.finite(wo) & is.finite(wd)]
      if (nrow(pw) == 0) next
      r_wo <- pw$wo; r_wd <- pw$wd
      plot_rows[[k]] <- data.table(response = resp, col = cd$col, pair = pd$pair,
                                   model_type = "Without D", rmse = r_wo); k <- k + 1
      plot_rows[[k]] <- data.table(response = resp, col = cd$col, pair = pd$pair,
                                   model_type = "With D", rmse = r_wd); k <- k + 1
      # signed % change in RMSE (median-based): negative = LESS error = improvement
      med_wo <- median(r_wo, na.rm = TRUE); med_wd <- median(r_wd, na.rm = TRUE)
      # Effect size = MEDIAN OF THE PAIRED PER-SITE % CHANGES, not the difference
      # of the two medians. The design is paired (same sites, same folds, only D
      # differs), so the effect size must be too - and it is what the signed-rank
      # test below actually assesses. Difference-of-medians compares two marginal
      # distributions, ignores the pairing, and disagreed in SIGN with the paired
      # statistic in 10 of 20 spot-checked comparisons (e.g. NEPmax M1->M2 read
      # +5.0% by that measure but -13.9% paired, with 63% of sites improving).
      delta_pct <- median((r_wd - r_wo) / r_wo * 100, na.rm = TRUE)
      # ONE-SIDED paired Wilcoxon signed-rank: H1 = adding D REDUCES per-site RMSE.
      # Non-parametric because per-site RMSE is right-skewed. Paired on SITE_ID, so
      # both models saw identical training data for each held-out site.
      pval <- tryCatch(
        wilcox.test(r_wd, r_wo, paired = TRUE, alternative = "less", exact = FALSE)$p.value,
        error = function(e) NA_real_)
      n_pair  <- length(r_wo)
      pct_imp <- 100 * mean(r_wd < r_wo, na.rm = TRUE)
      # colour tracks improvement: green when error drops, red when it rises
      lcol <- if (delta_pct < -1) COL_UP else if (delta_pct > 1) COL_DN else COL_NC
      lab_rows[[lk]] <- data.table(response = resp, col = cd$col, pair = pd$pair,
                                   imp = delta_pct, p = pval, n = n_pair, pct_imp = pct_imp,
                                   med_wo = med_wo, med_wd = med_wd,
                                   label = sprintf("%+.1f%%", delta_pct),
                                   lcol = lcol); lk <- lk + 1
    }
  }
}
dt <- rbindlist(plot_rows)
labs <- rbindlist(lab_rows)

# ── significance: Benjamini-Hochberg FDR across all tests in THIS figure ──────
# Scope = one learner variant x one dataset (80 tests), so each figure is
# internally valid and figures stay comparable with one another.
labs[, q := p.adjust(p, method = "BH")]
stars <- function(q) fifelse(is.na(q), "",
                    fifelse(q < 0.001, "***",
                    fifelse(q < 0.01,  "**",
                    fifelse(q < 0.05,  "*", " ns"))))
labs[, sig := stars(q)]
# Show the effect size with the significance marker - a star on its own invites
# comparing significance across groups that differ in sample size and power.
labs[, label := sprintf("%+.1f%%%s\n%.0f%%\u2193", imp, sig, pct_imp)]

res_csv <- file.path(out_dir, "RMSE_disturbance_significance.csv")
fwrite(labs[order(response, col, pair),
            .(response, window_memory = col, pair, n_sites = n,
              median_RMSE_withoutD = round(med_wo, 4), median_RMSE_withD = round(med_wd, 4),
              delta_pct = round(imp, 2), pct_sites_improved = round(pct_imp, 1),
              p_onesided_wilcoxon = signif(p, 4), q_BH = signif(q, 4), sig)],
       res_csv)
cat(sprintf("  significance CSV: %s (%d tests, %d with q<0.05)\n",
            res_csv, nrow(labs), labs[q < 0.05, .N]))

dt[, response := factor(response, levels = EFP_ORDER)]
dt[, col := factor(col, levels = COL_LEVELS)]
dt[, pair := factor(pair, levels = PAIR_LEVELS)]
dt[, model_type := factor(model_type, levels = c("Without D", "With D"))]
labs[, response := factor(response, levels = EFP_ORDER)]
labs[, col := factor(col, levels = COL_LEVELS)]
labs[, pair := factor(pair, levels = PAIR_LEVELS)]

# y position for labels = per-response max (shared y within a row via free_y)
ymax <- dt[, .(ytop = quantile(rmse, 0.99, na.rm = TRUE)), by = response]
labs <- merge(labs, ymax, by = "response")
labs[, ylab := ytop * 1.02]

n_sites <- uniqueN(preds$SITE_ID)
cat(sprintf("Sites: %d | plotting rows: %d\n", n_sites, nrow(dt)))

# ── theme ────────────────────────────────────────────────────
dark_theme <- theme_bw(base_size = 10) +
  theme(
    plot.background = element_rect(fill = DARK_BG, colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.4),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text = element_text(colour = TEXT_COL, size = 9, face = "bold"),
    axis.text.x = element_text(colour = AXIS_COL, size = 6.5, angle = 20, hjust = 1),
    axis.text.y = element_text(colour = AXIS_COL, size = 8),
    axis.title = element_text(colour = AXIS_COL, size = 9, face = "bold"),
    legend.background = element_rect(fill = NA, colour = NA),
    legend.key = element_rect(fill = NA, colour = NA),
    legend.text = element_text(colour = TEXT_COL, size = 10),
    legend.title = element_blank(),
    legend.position = "bottom",
    plot.title = element_text(colour = TEXT_COL, size = 13, face = "bold"),
    plot.subtitle = element_text(colour = AXIS_COL, size = 9)
  )

# strip.text.y uses response labels with units
resp_labeller <- labeller(response = EFP_LABELS)

p <- ggplot(dt, aes(x = pair, y = rmse, fill = model_type)) +
  geom_violin(position = position_dodge(width = 0.8), colour = NA,
              width = 0.75, alpha = 0.75, trim = TRUE) +
  geom_boxplot(aes(group = interaction(pair, model_type)),
               position = position_dodge(width = 0.8), width = 0.16,
               outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.28) +
  geom_text(data = labs, aes(x = pair, y = ylab, label = label, colour = lcol),
            inherit.aes = FALSE, size = 2.3, fontface = "bold") +
  scale_fill_manual(values = c("Without D" = COL_WO, "With D" = COL_W)) +
  scale_colour_identity() +
  facet_grid(response ~ col, scales = "free_y", labeller = resp_labeller, switch = "y") +
  labs(x = NULL, y = NULL,
       title = "Effect of adding deadwood disturbance on per-site RMSE",
       subtitle = sprintf("Paired violin: cyan = without D, pink = with D | LOSO CV | %d sites | %% = MEDIAN PAIRED change in per-site RMSE (negative = less error, green)\nstars = one-sided paired Wilcoxon, H1: adding D reduces RMSE, BH-FDR within figure (*** q<0.001, ** q<0.01, * q<0.05, ns) | %%\u2193 = share of sites whose RMSE improved", n_sites)) +
  dark_theme +
  theme(strip.placement = "outside")

# guide: only show fill legend for model_type (colour is identity)
p <- p + guides(colour = "none",
                fill = guide_legend(override.aes = list(alpha = 0.9)))

ggsave(file.path(out_dir, "RMSE_disturbance_effect_paired_violin.png"),
       p, width = 15, height = 13, dpi = 200, bg = DARK_BG)
ggsave(file.path(out_dir, "RMSE_disturbance_effect_paired_violin.pdf"),
       p, width = 15, height = 13, bg = DARK_BG)

cat("✓ Saved paired-violin RMSE plot\n")
cat("  Output:", out_dir, "\n")

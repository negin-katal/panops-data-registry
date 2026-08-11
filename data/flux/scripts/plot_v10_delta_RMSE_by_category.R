#!/usr/bin/env Rscript
# ============================================================================
# V10: Per-site ΔRMSE by disturbance category (SHAP-percent style)
# ΔRMSE = RMSE(with D) − RMSE(without D) per site (0 = no change, <0 improved)
# Comparisons: M1vsM2, M3vsM4, M5vsM6, M7vsM8 (each memtype/window)
# Layout: 3 rows (Abs Mort / Rel Mort / Rel Disturbance) × 5 EFP cols.
# Methods: tertiles / equal_width / natural_breaks.  arg2="merge" => Low+Mid vs High
# ============================================================================

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_delta_RMSE_by_category.R <dataset_type> [merge]")
dataset_type <- args[1]
MERGE <- length(args) >= 2 && args[2] == "merge"

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 ΔRMSE BY CATEGORY: %s%s\n", toupper(dataset_type),
            if (MERGE) " [MERGED LOW+MID]" else ""))
cat(strrep("=", 80), "\n\n", sep = "")

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"

if (MERGE) {
  LEVELS <- c("Low+Mid", "High")
  FILL_MAP <- setNames(c("#4DAECC", "#E8257A"), LEVELS)
} else {
  LEVELS <- c("Low", "Mid", "High")
  FILL_MAP <- setNames(c("#4DAECC", "#F0A500", "#E8257A"), LEVELS)
}

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

if (dataset_type == "filtered") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_predictions_LOSO.csv"
  harm_file <- "derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
  base_out  <- "plots/V10/sites_with_high_Tcover/RMSE/delta_RMSE_category"
} else if (dataset_type == "all_sites") {
  pred_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_predictions_LOSO.csv"
  harm_file <- "derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_GPPsat_harmonized.csv"
  base_out  <- "plots/V10/all_sites/RMSE/delta_RMSE_category"
} else stop("Invalid dataset_type")
out_dir <- if (MERGE) file.path(base_out, "merged_low_disturbance") else base_out
## --- optional model-family override (XGBoost etc.); no-op when unset ---
source("scripts/v10_model_family.R"); v10_apply_override()
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── per-site RMSE per model ──────────────────────────────────
preds <- fread(pred_file)
preds <- preds[is.finite(observed) & is.finite(predicted)]
site_rmse <- preds[, .(rmse = sqrt(mean((observed - predicted)^2))),
                   by = .(model, response, SITE_ID)]

# ── per-site disturbance categories (peak, 3 methods) ────────
harm <- fread(harm_file, select = c("SITE_ID", "YEAR", "absolute_mortality_500m",
                                     "relative_mortality_500m", "relative_disturbance_500m"))
na_inf <- function(x) { x[!is.finite(x)] <- NA; x }
sm <- harm[, .(am = na_inf(max(absolute_mortality_500m, na.rm = TRUE)),
               rm = na_inf(max(relative_mortality_500m, na.rm = TRUE)),
               rd = na_inf(max(relative_disturbance_500m, na.rm = TRUE))), by = SITE_ID]

cut3 <- function(x, b1, b2) cut(x, c(-Inf, b1, b2, Inf), c("Low", "Mid", "High"))
tert <- function(x) quantile(x, c(1/3, 2/3), na.rm = TRUE)
eqw  <- function(x) { w <- (max(x, na.rm = TRUE) - min(x, na.rm = TRUE)) / 3
                      min(x, na.rm = TRUE) + c(w, 2 * w) }
natb <- function(x) mean(x, na.rm = TRUE) + c(-0.5, 0.5) * sd(x, na.rm = TRUE)

mk_cat <- function(x, method) {
  b <- switch(method, tertiles = tert(x), equal_width = eqw(x), natural_breaks = natb(x))
  cut3(x, b[1], b[2])
}

build_cats <- function(method) {
  d <- data.table(SITE_ID = sm$SITE_ID,
                  am = mk_cat(sm$am, method),
                  rm = mk_cat(sm$rm, method),
                  rd = mk_cat(sm$rd, method))
  if (MERGE) {
    for (cc in c("am", "rm", "rd")) {
      v <- as.character(d[[cc]]); v[v %in% c("Low", "Mid")] <- "Low+Mid"
      d[[cc]] <- factor(v, levels = LEVELS)
    }
  } else {
    for (cc in c("am", "rm", "rd")) d[[cc]] <- factor(d[[cc]], levels = LEVELS)
  }
  d
}

# ── comparison units ─────────────────────────────────────────
units <- list(
  list(id = "M1vsM2_12m",      wo = "M1_12m",      wd = "M2_12m"),
  list(id = "M1vsM2_24m",      wo = "M1_24m",      wd = "M2_24m"),
  list(id = "M3vsM4_12m",      wo = "M3_12m",      wd = "M4_12m"),
  list(id = "M3vsM4_24m",      wo = "M3_24m",      wd = "M4_24m"),
  list(id = "M5vsM6_raw_12m",  wo = "M5_raw_12m",  wd = "M6_raw_12m"),
  list(id = "M5vsM6_raw_24m",  wo = "M5_raw_24m",  wd = "M6_raw_24m"),
  list(id = "M5vsM6_anom_12m", wo = "M5_anom_12m", wd = "M6_anom_12m"),
  list(id = "M5vsM6_anom_24m", wo = "M5_anom_24m", wd = "M6_anom_24m"),
  list(id = "M7vsM8_raw_12m",  wo = "M7_raw_12m",  wd = "M8_raw_12m"),
  list(id = "M7vsM8_raw_24m",  wo = "M7_raw_24m",  wd = "M8_raw_24m"),
  list(id = "M7vsM8_anom_12m", wo = "M7_anom_12m", wd = "M8_anom_12m"),
  list(id = "M7vsM8_anom_24m", wo = "M7_anom_24m", wd = "M8_anom_24m")
)
methods <- c("tertiles", "equal_width", "natural_breaks")
metrics <- list(list(col = "am", name = "Absolute Mortality"),
                list(col = "rm", name = "Relative Mortality"),
                list(col = "rd", name = "Relative Disturbance"))

# per-site ΔRMSE for a unit, all EFPs
delta_for_unit <- function(u) {
  wo <- site_rmse[model == u$wo, .(response, SITE_ID, r_wo = rmse)]
  wd <- site_rmse[model == u$wd, .(response, SITE_ID, r_wd = rmse)]
  if (nrow(wo) == 0 || nrow(wd) == 0) return(NULL)
  m <- merge(wo, wd, by = c("response", "SITE_ID"))
  m[, dRMSE := r_wd - r_wo]
  m <- m[response %in% EFP_ORDER]
  m[, response := factor(response, levels = EFP_ORDER)]
  m
}

# ── one-sided significance within each category ──────────────
# dRMSE is already the paired per-site difference (with D - without D), so this
# is a ONE-SAMPLE one-sided Wilcoxon signed-rank, H1: median dRMSE < 0, i.e.
# adding disturbance REDUCES per-site RMSE. Non-parametric: dRMSE is skewed.
cat_stats <- function(dt, cat_col) {
  d2 <- copy(dt)
  d2[, cat := factor(get(cat_col), levels = LEVELS)]
  d2 <- d2[!is.na(cat) & is.finite(dRMSE)]
  d2[, .(n = .N,
         med = median(dRMSE),
         pct_imp = 100 * mean(dRMSE < 0),
         p = if (.N >= 6) tryCatch(wilcox.test(dRMSE, mu = 0, alternative = "less",
                                               exact = FALSE)$p.value,
                                   error = function(e) NA_real_) else NA_real_),
     by = .(response, cat)]
}
stars <- function(q) fifelse(is.na(q), "",
                    fifelse(q < 0.001, "***",
                    fifelse(q < 0.01,  "**",
                    fifelse(q < 0.05,  "*", "ns"))))

make_row <- function(dt, cat_col, metric_name, show_x, st = NULL) {
  dt2 <- copy(dt)
  dt2[, cat := factor(get(cat_col), levels = LEVELS)]
  dt2 <- dt2[!is.na(cat)]
  ann <- NULL
  if (!is.null(st)) {
    ytop <- dt2[, .(ymax = quantile(dRMSE, 0.98, na.rm = TRUE)), by = response]
    ann <- merge(st, ytop, by = "response")
    ann[, `:=`(response = factor(response, levels = EFP_ORDER),
               cat = factor(cat, levels = LEVELS),
               ylab = ymax * 1.10)]
    # Significance alone is misleading here: the High category has ~26 sites vs
    # ~86 for Low+Mid, so it clears fewer FDR thresholds DESPITE a larger effect.
    # Always show the effect size next to the star.
    ann[, lab2 := sprintf("%s\n%.0f%%\u2193  n=%d", sig, pct_imp, n)]
  }
  ggplot(dt2, aes(x = cat, y = dRMSE, fill = cat)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4) +
    geom_violin(trim = TRUE, scale = "width", width = 0.8, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.1) +
    scale_fill_manual(values = FILL_MAP, guide = "none") +
    { if (!is.null(ann)) geom_text(data = ann, aes(x = cat, y = ylab, label = lab2),
                                   inherit.aes = FALSE, colour = "#FFFFFF", size = 2.4,
                                   lineheight = 0.95, fontface = "bold") } +
    facet_wrap(~response, nrow = 1, scales = "free_y") +
    labs(title = metric_name, x = NULL, y = "ΔRMSE (with D − without D)") +
    theme_bw(base_size = 9) +
    theme(
      plot.title = element_text(colour = TEXT_COL, size = 10, face = "bold"),
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      panel.background = element_rect(fill = PANEL_BG, colour = NA),
      panel.border = element_rect(colour = GRID_COL, fill = NA),
      panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
      panel.grid.minor = element_blank(),
      strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
      strip.text = element_text(colour = TEXT_COL, size = 8, face = "bold"),
      axis.text.x = if (show_x) element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1) else element_blank(),
      axis.text.y = element_text(colour = AXIS_COL, size = 7),
      axis.title.y = element_text(colour = AXIS_COL, size = 8)
    )
}

cat("Generating figures:\n")
sig_rows <- list()
for (u in units) {
  du <- delta_for_unit(u)
  if (is.null(du)) { cat("  skip (no data):", u$id, "\n"); next }
  for (method in methods) {
    cats <- build_cats(method)
    dm <- merge(du, cats, by = "SITE_ID", all.x = TRUE)

    # stats for every metric x response x category in THIS figure, then BH-FDR
    # across all of them (per-figure scope, matching the paired-violin figures)
    st_all <- rbindlist(lapply(seq_along(metrics), function(i) {
      cat_stats(dm, metrics[[i]]$col)[, metric := metrics[[i]]$name][]
    }), fill = TRUE)
    st_all[, q := p.adjust(p, method = "BH")]
    st_all[, sig := stars(q)]
    sig_rows[[length(sig_rows) + 1]] <-
      st_all[, .(unit = u$id, method = method, metric, response, category = cat,
                 n, median_dRMSE = round(med, 5), pct_sites_improved = round(pct_imp, 1),
                 p_onesided_wilcoxon = signif(p, 4), q_BH = signif(q, 4), sig)]

    rows <- lapply(seq_along(metrics), function(i) {
      make_row(dm, metrics[[i]]$col, metrics[[i]]$name, show_x = (i == length(metrics)),
               st = st_all[metric == metrics[[i]]$name])
    })
    combined <- (rows[[1]] / rows[[2]] / rows[[3]]) +
      plot_annotation(
        title = sprintf("ΔRMSE by disturbance category — %s | %s\nstars = one-sided Wilcoxon, H1: adding D reduces RMSE (BH-FDR within figure): *** q<0.001, ** q<0.01, * q<0.05, ns | %%\u2193 = share of sites whose RMSE improved (read this with the star: High has ~26 sites vs ~86 for Low+Mid, so it has less power despite a larger effect)", u$id, method),
        theme = theme(plot.title = element_text(colour = TEXT_COL, size = 13, face = "bold", hjust = 0.5),
                      plot.background = element_rect(fill = DARK_BG, colour = NA))
      ) & theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

    stem <- file.path(out_dir, sprintf("delta_RMSE_%s_%s", u$id, method))
    ggsave(paste0(stem, ".png"), combined, width = 16, height = 9, dpi = 200, bg = DARK_BG)
    ggsave(paste0(stem, ".pdf"), combined, width = 16, height = 9, bg = DARK_BG)
    cat(sprintf("  ✓ %s\n", basename(stem)))
  }
}

if (length(sig_rows) > 0) {
  sig_dt <- rbindlist(sig_rows, fill = TRUE)
  sig_csv <- file.path(out_dir, "delta_RMSE_category_significance.csv")
  fwrite(sig_dt, sig_csv)
  cat(sprintf("\n  significance CSV: %s (%d tests, %d with q<0.05)\n",
              sig_csv, nrow(sig_dt), sig_dt[q_BH < 0.05, .N]))
}

cat("\n✅ V10 ΔRMSE BY CATEGORY COMPLETE\n")
cat("   Output:", out_dir, "\n")

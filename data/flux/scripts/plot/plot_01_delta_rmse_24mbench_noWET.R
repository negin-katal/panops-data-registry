library(data.table)
library(ggplot2)

# ============================================================
# PLOT 01 (noWET): Site-level ΔRMSE — with vs. without disturbance
# 24m unified benchmark, WET sites excluded post-hoc (no retraining).
# Compares M01 (C) vs M02 (C+D)  and  M03 (C+T) vs M04 (C+T+D)
# for both 12m and 24m windows, both memory types' M01-M04 share
# the same RF run (memory-free models), so we use the anomaly
# source for M01-M04 in both panels.
# Sites colored by disturbance class: High (brown) / Low (green)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

COL_HIGH <- "#A0522D"
COL_LOW  <- "#3A9E5C"

out_dir    <- "plots/disturbance_effects/24mbench_noWET"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pred_file  <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_predictions_LOSO.csv"
model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

# ============================================================
# 1) IGBP lookup -> identify WET sites to drop
# ============================================================

site_igbp <- unique(fread(model_file, select = c("SITE_ID", "IGBP")))
wet_sites <- site_igbp[IGBP == "WET", SITE_ID]
cat("WET sites to exclude:", length(wet_sites), "\n")

# ============================================================
# 2) Load predictions, drop WET sites
# ============================================================

cat("Loading predictions...\n")
preds <- fread(pred_file, select = c("model", "response", "SITE_ID", "YEAR",
                                     "observed", "predicted"))
preds <- preds[!SITE_ID %in% wet_sites]
cat(nrow(preds), "prediction rows after WET exclusion\n")

preds[, tier   := sub("_.*", "", model)]
preds[, window := sub("^[^_]+_([^_]+)_.*", "\\1", model)]

# ============================================================
# 3) Site-level disturbance intensity -> high / low class
# ============================================================

dt_dist <- fread(model_file, select = c("SITE_ID", "YEAR", "mortality_intensity_pct_500m"))
dt_dist <- dt_dist[!SITE_ID %in% wet_sites]

site_dist <- dt_dist[, .(
  mean_mort = mean(mortality_intensity_pct_500m, na.rm = TRUE),
  peak_mort = max( mortality_intensity_pct_500m, na.rm = TRUE)
), by = SITE_ID]

thresh <- median(site_dist$peak_mort, na.rm = TRUE)
cat(sprintf("Disturbance threshold (median peak): %.1f%%\n", thresh))
site_dist[, dist_class := fifelse(peak_mort >= thresh,
                                  "High disturbance", "Low disturbance")]

efp_units <- c(
  GPPsat = "GPPsat  (μmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (μmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)"
)

# ============================================================
# 4) Plot helper
# ============================================================

make_delta_plot <- function(dt_in, delta_col, xlab_str) {
  dt_in <- dt_in[!is.na(get(delta_col))]
  dt_in <- dt_in[order(get(delta_col))]
  dt_in[, SITE_ID := factor(SITE_ID, levels = SITE_ID)]

  xr  <- range(dt_in[[delta_col]], na.rm = TRUE)
  pad <- diff(xr) * 0.12
  ann_y <- nrow(dt_in) + 0.5

  ggplot(dt_in, aes_string(x = delta_col, y = "SITE_ID", fill = "dist_class")) +
    geom_col(width = 0.75) +
    geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.45, colour = "grey40") +
    annotate("text",
             x = xr[1] - pad * 0.4,  y = ann_y,
             label = "← improvement", hjust = 1, size = 3.2, colour = "grey40") +
    annotate("text",
             x = xr[2] + pad * 0.4,  y = ann_y,
             label = "degradation →", hjust = 0, size = 3.2, colour = "grey40") +
    scale_fill_manual(
      values = c("High disturbance" = COL_HIGH, "Low disturbance" = COL_LOW),
      name   = NULL
    ) +
    scale_x_continuous(expand = expansion(mult = c(0.12, 0.12))) +
    labs(x = xlab_str, y = NULL) +
    theme_bw(base_size = 10) +
    theme(
      axis.text.y        = element_text(size = 7),
      legend.position    = "bottom",
      legend.key.size    = unit(0.55, "cm"),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank()
    )
}

# ============================================================
# 5) Loop over windows, compute per-site RMSE, generate plots
# ============================================================

for (win in c("12m", "24m")) {

  cat("\n--- Window:", win, "---\n")

  site_rmse <- preds[!is.na(observed) & !is.na(predicted) &
                     window == win & tier %in% c("M01","M02","M03","M04"),
                     .(rmse = sqrt(mean((observed - predicted)^2)),
                       n    = .N),
                     by = .(tier, response, SITE_ID)]

  rmse_wide <- dcast(site_rmse, SITE_ID + response ~ tier, value.var = "rmse")
  setnames(rmse_wide,
           c("M01","M02","M03","M04"),
           c("rmse_M01","rmse_M02","rmse_M03","rmse_M04"),
           skip_absent = TRUE)

  rmse_wide[, delta_raw    := rmse_M02 - rmse_M01]
  rmse_wide[, delta_traits := rmse_M04 - rmse_M03]

  plot_dt <- merge(rmse_wide, site_dist, by = "SITE_ID", all.x = TRUE)
  plot_dt[is.na(dist_class), dist_class := "Low disturbance"]

  cat("Generating delta RMSE plots (M02 vs M01,", win, ")...\n")
  for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
    dt_resp <- plot_dt[response == resp]
    if (nrow(dt_resp) == 0) next

    p <- make_delta_plot(dt_resp, "delta_raw",
           sprintf("ΔRMSE  (C+Disturbance − Climate baseline)  [%s, no WET]", win)) +
      ggtitle(efp_units[resp]) +
      theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

    h <- max(5, nrow(dt_resp[!is.na(delta_raw)]) * 0.19 + 1.8)
    out_stem <- file.path(out_dir, paste0(resp, "_delta_rmse_M02vM01_", win, "_noWET"))
    ggsave(paste0(out_stem, ".png"), p, width = 5.5, height = h,
           dpi = 180, limitsize = FALSE)
    ggsave(paste0(out_stem, ".pdf"), p, width = 5.5, height = h,
           limitsize = FALSE)
    cat("  Saved:", resp, win, "(M02 vs M01)\n")
  }

  cat("Generating delta RMSE plots (M04 vs M03,", win, ")...\n")
  for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
    dt_resp <- plot_dt[response == resp]
    if (nrow(dt_resp) == 0) next

    p <- make_delta_plot(dt_resp, "delta_traits",
           sprintf("ΔRMSE  (C+Traits+Disturbance − C+Traits baseline)  [%s, no WET]", win)) +
      ggtitle(efp_units[resp]) +
      theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

    h <- max(5, nrow(dt_resp[!is.na(delta_traits)]) * 0.19 + 1.8)
    out_stem <- file.path(out_dir, paste0(resp, "_delta_rmse_M04vM03_", win, "_noWET"))
    ggsave(paste0(out_stem, ".png"), p, width = 5.5, height = h,
           dpi = 180, limitsize = FALSE)
    ggsave(paste0(out_stem, ".pdf"), p, width = 5.5, height = h,
           limitsize = FALSE)
    cat("  Saved:", resp, win, "(M04 vs M03)\n")
  }
}

cat("\n=== plot_01_noWET DONE ===\n")
cat("Outputs in:", out_dir, "\n")

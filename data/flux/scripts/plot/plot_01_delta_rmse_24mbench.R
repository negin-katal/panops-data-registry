library(data.table)
library(ggplot2)

# ============================================================
# PLOT 01: Site-level ΔRMSE — with vs. without disturbance
# 24m unified benchmark, WET sites INCLUDED (166 sites).
#
# Comparisons:
#   M02 vs M01  (C+D vs C)              — common to both memory types
#   M04 vs M03  (C+T+D vs C+T)          — common to both memory types
#   M10 vs M09  (M+D vs M)              — differs per memory type (anomaly/raw-lag)
#
# Sites colored by disturbance class: High (brown) / Low (green)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

COL_HIGH <- "#A0522D"
COL_LOW  <- "#3A9E5C"

out_dir    <- "plots/disturbance_effects/24mbench"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

pred_sources <- list(
  anomaly = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_predictions_LOSO.csv",
  rawlag  = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench/RF_predictions_LOSO.csv"
)

# ============================================================
# 1) Site-level disturbance intensity -> high / low class
# ============================================================

dt_dist <- fread(model_file, select = c("SITE_ID", "YEAR", "mortality_intensity_pct_500m"))

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
# 2) Plot helper
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

save_delta <- function(dt_resp, delta_col, xlab_str, resp, fname_stem) {
  p <- make_delta_plot(dt_resp, delta_col, xlab_str) +
    ggtitle(efp_units[resp]) +
    theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

  h <- max(5, nrow(dt_resp[!is.na(get(delta_col))]) * 0.19 + 1.8)
  out_stem <- file.path(out_dir, fname_stem)
  ggsave(paste0(out_stem, ".png"), p, width = 5.5, height = h,
         dpi = 180, limitsize = FALSE)
  ggsave(paste0(out_stem, ".pdf"), p, width = 5.5, height = h,
         limitsize = FALSE)
}

# ============================================================
# 3) M01-M04 comparisons (memory-free, common to both sources)
# ============================================================

preds_anom <- fread(pred_sources$anomaly, select = c("model", "response", "SITE_ID", "YEAR",
                                                      "observed", "predicted"))
preds_anom[, tier   := sub("_.*", "", model)]
preds_anom[, window := sub("^[^_]+_([^_]+)_.*", "\\1", model)]

for (win in c("12m", "24m")) {

  cat("\n--- Window:", win, "(M01-M04) ---\n")

  site_rmse <- preds_anom[!is.na(observed) & !is.na(predicted) &
                          window == win & tier %in% c("M01","M02","M03","M04"),
                          .(rmse = sqrt(mean((observed - predicted)^2))),
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

  for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
    dt_resp <- plot_dt[response == resp]
    if (nrow(dt_resp) == 0) next

    save_delta(dt_resp, "delta_raw",
               sprintf("ΔRMSE  (C+Disturbance − Climate baseline)  [%s]", win),
               resp, paste0(resp, "_delta_rmse_M02vM01_", win))
    cat("  Saved:", resp, win, "(M02 vs M01)\n")

    save_delta(dt_resp, "delta_traits",
               sprintf("ΔRMSE  (C+Traits+Disturbance − C+Traits baseline)  [%s]", win),
               resp, paste0(resp, "_delta_rmse_M04vM03_", win))
    cat("  Saved:", resp, win, "(M04 vs M03)\n")
  }
}

# ============================================================
# 4) M10 vs M09 comparison (Memory+Disturbance vs Memory alone)
#    Differs per memory type -> loop over both sources
# ============================================================

for (mem_type in names(pred_sources)) {

  preds <- fread(pred_sources[[mem_type]], select = c("model", "response", "SITE_ID", "YEAR",
                                                       "observed", "predicted"))
  preds[, tier   := sub("_.*", "", model)]
  preds[, window := sub("^[^_]+_([^_]+)_.*", "\\1", model)]

  for (win in c("12m", "24m")) {

    cat("\n--- Window:", win, "(M09/M10,", mem_type, ") ---\n")

    site_rmse <- preds[!is.na(observed) & !is.na(predicted) &
                       window == win & tier %in% c("M09","M10"),
                       .(rmse = sqrt(mean((observed - predicted)^2))),
                       by = .(tier, response, SITE_ID)]

    if (nrow(site_rmse) == 0) { cat("  No M09/M10 data found, skipping\n"); next }

    rmse_wide <- dcast(site_rmse, SITE_ID + response ~ tier, value.var = "rmse")
    setnames(rmse_wide, c("M09","M10"), c("rmse_M09","rmse_M10"), skip_absent = TRUE)
    rmse_wide[, delta_mem := rmse_M10 - rmse_M09]

    plot_dt <- merge(rmse_wide, site_dist, by = "SITE_ID", all.x = TRUE)
    plot_dt[is.na(dist_class), dist_class := "Low disturbance"]

    for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
      dt_resp <- plot_dt[response == resp]
      if (nrow(dt_resp) == 0) next

      save_delta(dt_resp, "delta_mem",
                 sprintf("ΔRMSE  (Memory+Disturbance − Memory alone)  [%s, %s]", win, mem_type),
                 resp, paste0(resp, "_delta_rmse_M10vM09_", win, "_", mem_type))
      cat("  Saved:", resp, win, mem_type, "(M10 vs M09)\n")
    }
  }
}

cat("\n=== plot_01 (24mbench) DONE ===\n")
cat("Outputs in:", out_dir, "\n")

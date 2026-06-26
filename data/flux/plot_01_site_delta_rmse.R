library(data.table)
library(ggplot2)

# ============================================================
# PLOT 01: Site-level ΔRMSE — with vs. without disturbance
# Compares M01 (C) vs M02 (C+D)  and  M03 (C+T) vs M04 (C+T+D)
# Sites colored by disturbance class: High (brown) / Low (green)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

COL_HIGH <- "#A0522D"   # sienna brown  — high disturbance
COL_LOW  <- "#3A9E5C"   # forest green  — low disturbance

out_dir    <- "plots/disturbance_effects"
pred_file  <- "derived_tables/outputs_afterEGU_results/RF_outputs_fixed/RF_predictions_LOSO.csv"
model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# ============================================================
# 1) Load predictions → per-site RMSE
# ============================================================

cat("Loading predictions...\n")
preds <- fread(pred_file, select = c("model", "response", "SITE_ID", "YEAR",
                                     "observed", "predicted"))
cat(nrow(preds), "prediction rows loaded\n")

# Split model string into tier / window
preds[, tier   := sub("_.*", "", model)]                        # M01, M02, …
preds[, window := sub("^[^_]+_([^_]+)_.*", "\\1", model)]      # 12m / 24m

site_rmse <- preds[!is.na(observed) & !is.na(predicted) &
                   window == "12m" & tier %in% c("M01","M02","M03","M04"),
                   .(rmse = sqrt(mean((observed - predicted)^2)),
                     n    = .N),
                   by = .(tier, response, SITE_ID)]

# Pivot to one row per site × response
rmse_wide <- dcast(site_rmse, SITE_ID + response ~ tier, value.var = "rmse")
setnames(rmse_wide,
         c("M01","M02","M03","M04"),
         c("rmse_M01","rmse_M02","rmse_M03","rmse_M04"),
         skip_absent = TRUE)

rmse_wide[, delta_raw    := rmse_M02 - rmse_M01]   # adding D to C
rmse_wide[, delta_traits := rmse_M04 - rmse_M03]   # adding D to C+T

cat("Site × response combinations:", nrow(rmse_wide), "\n")

# ============================================================
# 2) Site-level disturbance intensity → high / low class
# ============================================================

cat("Computing site disturbance intensity...\n")
dt_dist <- fread(model_file,
                 select = c("SITE_ID", "YEAR", "mortality_intensity_pct_500m"))
dt_dist <- dt_dist[!SITE_ID %in% EXCLUDE_SITES]

site_dist <- dt_dist[, .(
  mean_mort = mean(mortality_intensity_pct_500m, na.rm = TRUE),
  peak_mort = max( mortality_intensity_pct_500m, na.rm = TRUE)
), by = SITE_ID]

# Binary classification: above median = High
thresh <- median(site_dist$peak_mort, na.rm = TRUE)
cat(sprintf("Disturbance threshold (median peak): %.1f%%\n", thresh))
site_dist[, dist_class := fifelse(peak_mort >= thresh,
                                  "High disturbance", "Low disturbance")]

# ============================================================
# 3) Merge and tidy
# ============================================================

plot_dt <- merge(rmse_wide, site_dist, by = "SITE_ID", all.x = TRUE)
plot_dt[is.na(dist_class), dist_class := "Low disturbance"]

# ============================================================
# 4) Plot helper
# ============================================================

efp_units <- c(
  GPPsat = "GPPsat  (μmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (μmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)"
)

make_delta_plot <- function(dt_in, delta_col, xlab_str) {
  dt_in <- dt_in[!is.na(get(delta_col))]
  dt_in <- dt_in[order(get(delta_col))]
  dt_in[, SITE_ID := factor(SITE_ID, levels = SITE_ID)]

  xr  <- range(dt_in[[delta_col]], na.rm = TRUE)
  pad <- diff(xr) * 0.12
  # annotation y position (fraction of n sites)
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
# 5) Generate plots — M02 vs M01 (pure disturbance effect)
# ============================================================

cat("Generating delta RMSE plots (M02 vs M01)...\n")
for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
  dt_resp <- plot_dt[response == resp]
  if (nrow(dt_resp) == 0) next

  p <- make_delta_plot(dt_resp, "delta_raw",
         "ΔRMSE  (C+Disturbance  −  Climate baseline)") +
    ggtitle(efp_units[resp]) +
    theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

  h <- max(5, nrow(dt_resp[!is.na(delta_raw)]) * 0.19 + 1.8)
  out_stem <- file.path(out_dir, paste0(resp, "_delta_rmse_M02vM01"))
  ggsave(paste0(out_stem, ".png"), p, width = 5.5, height = h,
         dpi = 180, limitsize = FALSE)
  ggsave(paste0(out_stem, ".pdf"), p, width = 5.5, height = h,
         limitsize = FALSE)
  cat("  Saved:", resp, "(M02 vs M01)\n")
}

# ============================================================
# 6) Generate plots — M04 vs M03 (disturbance on top of traits)
# ============================================================

cat("Generating delta RMSE plots (M04 vs M03)...\n")
for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
  dt_resp <- plot_dt[response == resp]
  if (nrow(dt_resp) == 0) next

  p <- make_delta_plot(dt_resp, "delta_traits",
         "ΔRMSE  (C+Traits+Disturbance  −  C+Traits baseline)") +
    ggtitle(efp_units[resp]) +
    theme(plot.title = element_text(face = "bold", size = 12, hjust = 0.5))

  h <- max(5, nrow(dt_resp[!is.na(delta_traits)]) * 0.19 + 1.8)
  out_stem <- file.path(out_dir, paste0(resp, "_delta_rmse_M04vM03"))
  ggsave(paste0(out_stem, ".png"), p, width = 5.5, height = h,
         dpi = 180, limitsize = FALSE)
  ggsave(paste0(out_stem, ".pdf"), p, width = 5.5, height = h,
         limitsize = FALSE)
  cat("  Saved:", resp, "(M04 vs M03)\n")
}

cat("\n=== plot_01 DONE ===\n")
cat("Outputs in:", out_dir, "\n")

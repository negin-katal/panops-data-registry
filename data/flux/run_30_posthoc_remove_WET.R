library(data.table)

# ============================================================
# RUN 30: Post-hoc removal of WET (wetland) sites from the
#         already-completed 24mbench RF results.
#
# No retraining — simply drop WET sites from the saved
# per-observation predictions and per-site SHAP values, then
# recompute R2 / RMSE / SHAP group shares on the remainder.
#
# Inputs (already on disk):
#   RF_outputs_anomaly_24mbench/{RF_predictions_LOSO,RF_site_shap_M04_M08}.csv
#   RF_outputs_rawmem_24mbench/{RF_predictions_LOSO,RF_site_shap_M04_M08}.csv
#
# Output: RF_outputs_24mbench_noWET_posthoc/
#   metrics_anomaly_noWET.csv, metrics_rawmem_noWET.csv
#   shap_group_share_anomaly_noWET.csv, shap_group_share_rawmem_noWET.csv
#   comparison_summary.csv  (with-WET vs without-WET side by side)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/RF_outputs_24mbench_noWET_posthoc"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

sources <- list(
  anomaly = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench",
  rawlag  = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench"
)

# ============================================================
# 1) Site -> IGBP lookup, identify WET sites
# ============================================================

site_igbp <- unique(fread(model_file, select = c("SITE_ID", "IGBP")))
wet_sites <- site_igbp[IGBP == "WET", SITE_ID]
cat("WET sites present in full dataset:", length(wet_sites), "\n")

# ============================================================
# 2) Recompute metrics from filtered predictions
# ============================================================

recompute_metrics <- function(pred_dt) {
  pred_dt <- merge(pred_dt, site_igbp, by = "SITE_ID", all.x = TRUE)
  n_wet_in_preds <- uniqueN(pred_dt[IGBP == "WET", SITE_ID])
  cat("  WET sites found in predictions:", n_wet_in_preds, "\n")

  pred_noWET <- pred_dt[IGBP != "WET" | is.na(IGBP)]

  pred_noWET[, `:=`(
    has_obs_pred = !is.na(observed) & !is.na(predicted)
  )]

  metrics <- pred_noWET[has_obs_pred == TRUE, .(
    n_pairs = .N,
    n_sites = uniqueN(SITE_ID),
    RMSE    = sqrt(mean((observed - predicted)^2)),
    R2      = if (.N >= 2) cor(observed, predicted)^2 else NA_real_
  ), by = .(model, response)]

  setorder(metrics, response, model)
  metrics
}

all_metrics_noWET <- list()
all_metrics_withWET <- list()

for (mem_type in names(sources)) {
  cat("\n===", mem_type, "===\n")
  pred_path <- file.path(sources[[mem_type]], "RF_predictions_LOSO.csv")
  pred_dt   <- fread(pred_path)

  metrics_noWET <- recompute_metrics(pred_dt)
  metrics_noWET[, mem_type := mem_type]
  all_metrics_noWET[[mem_type]] <- metrics_noWET

  metrics_path <- file.path(sources[[mem_type]], "RF_metrics_LOSO.csv")
  metrics_with <- fread(metrics_path)[, .(model, response, n_pairs, n_sites, RMSE, R2)]
  metrics_with[, mem_type := mem_type]
  all_metrics_withWET[[mem_type]] <- metrics_with

  fwrite(metrics_noWET, file.path(out_dir, sprintf("metrics_%s_noWET.csv", mem_type)))
  cat(sprintf("  Saved metrics_%s_noWET.csv (%d rows)\n", mem_type, nrow(metrics_noWET)))
}

metrics_noWET_all <- rbindlist(all_metrics_noWET)
metrics_withWET_all <- rbindlist(all_metrics_withWET)

# ============================================================
# 3) Recompute SHAP group shares with WET sites excluded
# ============================================================

GROUP_LEVELS <- c("Climate", "Traits", "Disturbance", "Memory")

recompute_shap_share <- function(shap_dt) {
  shap_dt <- merge(shap_dt, site_igbp, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)
  n_wet_in_shap <- uniqueN(shap_dt[IGBP == "WET", test_site])
  cat("  WET sites found in SHAP:", n_wet_in_shap, "\n")

  shap_noWET <- shap_dt[IGBP != "WET" | is.na(IGBP)]
  shap_noWET <- shap_noWET[group %in% GROUP_LEVELS]

  grp <- shap_noWET[, .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                    by = .(model, response, test_site, group)]
  totals <- grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
  grp <- merge(grp, totals, by = c("model", "response", "test_site"))
  grp[, rel_shap := grp_shap / total]

  grp[, .(mean_rel_shap = mean(rel_shap, na.rm = TRUE),
          n_sites       = uniqueN(test_site)),
      by = .(model, response, group)]
}

all_shap_noWET <- list()
all_shap_withWET <- list()

for (mem_type in names(sources)) {
  cat("\n===", mem_type, "SHAP ===\n")
  shap_path <- file.path(sources[[mem_type]], "RF_site_shap_M04_M08.csv")
  shap_dt   <- fread(shap_path)

  shap_share_noWET <- recompute_shap_share(shap_dt)
  shap_share_noWET[, mem_type := mem_type]
  all_shap_noWET[[mem_type]] <- shap_share_noWET

  # withWET version: no IGBP filter
  grp_all <- shap_dt[group %in% GROUP_LEVELS,
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]
  totals_all <- grp_all[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
  grp_all <- merge(grp_all, totals_all, by = c("model", "response", "test_site"))
  grp_all[, rel_shap := grp_shap / total]
  shap_share_withWET <- grp_all[, .(mean_rel_shap = mean(rel_shap, na.rm = TRUE),
                                    n_sites = uniqueN(test_site)),
                                by = .(model, response, group)]
  shap_share_withWET[, mem_type := mem_type]
  all_shap_withWET[[mem_type]] <- shap_share_withWET

  fwrite(shap_share_noWET, file.path(out_dir, sprintf("shap_group_share_%s_noWET.csv", mem_type)))
  cat(sprintf("  Saved shap_group_share_%s_noWET.csv (%d rows)\n", mem_type, nrow(shap_share_noWET)))
}

shap_noWET_all   <- rbindlist(all_shap_noWET)
shap_withWET_all <- rbindlist(all_shap_withWET)

# ============================================================
# 4) Comparison summaries
# ============================================================

cmp_metrics <- merge(
  metrics_withWET_all[, .(model, response, mem_type, R2_withWET = R2, RMSE_withWET = RMSE, n_sites_withWET = n_sites)],
  metrics_noWET_all[, .(model, response, mem_type, R2_noWET = R2, RMSE_noWET = RMSE, n_sites_noWET = n_sites)],
  by = c("model", "response", "mem_type")
)
cmp_metrics[, `:=`(
  delta_R2   = round(R2_noWET - R2_withWET, 4),
  delta_RMSE = round(RMSE_noWET - RMSE_withWET, 4)
)]
setorder(cmp_metrics, mem_type, response, model)
fwrite(cmp_metrics, file.path(out_dir, "comparison_metrics_with_vs_without_WET.csv"))

cmp_shap <- merge(
  shap_withWET_all[, .(model, response, group, mem_type, mean_rel_shap_withWET = mean_rel_shap)],
  shap_noWET_all[, .(model, response, group, mem_type, mean_rel_shap_noWET = mean_rel_shap)],
  by = c("model", "response", "group", "mem_type")
)
cmp_shap[, delta_rel_shap := round(mean_rel_shap_noWET - mean_rel_shap_withWET, 4)]
setorder(cmp_shap, mem_type, response, model, group)
fwrite(cmp_shap, file.path(out_dir, "comparison_shap_with_vs_without_WET.csv"))

cat("\n============================================================\n")
cat("WET sites excluded from this benchmark:\n")
print(wet_sites)

cat("\n--- R2 / RMSE: M04 & M08, with vs without WET ---\n")
print(cmp_metrics[grepl("M04|M08", model)][order(mem_type, response, model)])

cat("\n--- SHAP group share: M04 & M08 'Disturbance' group, with vs without WET ---\n")
print(cmp_shap[group == "Disturbance" & grepl("M04|M08", model)][order(mem_type, response, model)])

cat("\nSaved all outputs to:", out_dir, "\n")

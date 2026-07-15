# v3 — 2026-07-07: Train RF model for M06 (C+D+M) 24m window for SHAP
library(data.table)
library(ranger)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv"
cgs_file   <- "derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
N_TREES       <- 500
SEED          <- 42

EXCLUDE_SITES <- c("CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA")

dt  <- fread(model_file)
cgs <- fread(cgs_file)

if ("year" %in% names(cgs) && !"YEAR" %in% names(cgs)) setnames(cgs, "year", "YEAR")
cgs_keep <- c("SITE_ID", "YEAR", "CGS_weighted_doy", "CGS_midpoint_doy",
              "GS_start_doy", "GS_end_doy", "GS_length_days")
cgs_keep <- cgs_keep[cgs_keep %in% names(cgs)]
dt <- merge(dt, cgs[, ..cgs_keep], by = c("SITE_ID", "YEAR"), all.x = TRUE)
dt <- dt[!SITE_ID %in% EXCLUDE_SITES]
cat("Dataset:", nrow(dt), "rows |", uniqueN(dt$SITE_ID), "sites\n")

dt_rf <- copy(dt)

cgs_month_vec <- as.integer(ceiling(dt_rf$CGS_weighted_doy / (365.25 / 12)))
cgs_month_vec <- pmin(pmax(cgs_month_vec, 1L), 12L)
cgs_month_vec[is.na(cgs_month_vec)] <- 12L

climate_prefixes <- c("TA_mean", "TA_p05", "TA_p95", "VPD_mean", "VPD_p05", "VPD_p95",
  "P_mean", "P_sum", "P_p05", "P_p95", "SW_IN_mean", "SW_IN_p05", "SW_IN_p95")

agg_months <- function(vals, is_sum) {
  if (all(is.na(vals))) return(NA_real_)
  if (is_sum) sum(vals, na.rm = TRUE) else mean(vals, na.rm = TRUE)
}

get_month_mat <- function(prefix, lag_suffix) {
  mat <- matrix(NA_real_, nrow = nrow(dt_rf), ncol = 12)
  for (j in 1:12) {
    col <- sprintf("%s_M%02d%s", prefix, j, lag_suffix)
    if (col %in% names(dt_rf)) mat[, j] <- dt_rf[[col]]
  }
  mat
}

for (prefix in climate_prefixes) {
  is_sum_var <- grepl("_sum$", prefix)
  mat_cur  <- get_month_mat(prefix, "")
  mat_lag1 <- get_month_mat(prefix, "_lag1")
  mat_lag2 <- get_month_mat(prefix, "_lag2")
  dt_rf[[sprintf("%s_anom_lag1", prefix)]] <- apply(cbind(mat_cur[, -1], mat_lag1[, -12]), 1, agg_months, is_sum_var)
  dt_rf[[sprintf("%s_anom_lag2", prefix)]] <- apply(cbind(mat_cur[, -c(1,2)], mat_lag2[, -c(11,12)]), 1, agg_months, is_sum_var)
}

dist_cols <- c("mortality_intensity_pct_100m", "mortality_intensity_pct_500m",
               "deadwood_mean_pct_100m", "deadwood_mean_pct_500m",
               "forest_mean_pct_100m", "forest_mean_pct_500m",
               "loss_area_frac_100m", "loss_area_frac_500m")

meteo_cols <- c("tmin", "tmax", "prec", "vpd", "wind", "srad", "elev")

cat("Sample data prepared\n")

for (resp in RESPONSE_VARS) {
  cat("\n========== M06_24m_", resp, " ==========\n", sep = "")
  dt_train <- dt_rf[!is.na(dt_rf[[resp]]), ]
  cat("Training samples:", nrow(dt_train), "\n")

  climate_cols <- grep("_anom_lag", names(dt_train), value = TRUE)
  feature_cols <- c(climate_cols, dist_cols, meteo_cols)
  feature_cols <- feature_cols[feature_cols %in% names(dt_train)]
  cat("Features:", length(feature_cols), "\n")

  X <- as.matrix(dt_train[, ..feature_cols])
  X[is.na(X)] <- 0
  y <- dt_train[[resp]]

  set.seed(SEED)
  rf_model <- ranger(x = X, y = y, num.trees = N_TREES, num.threads = 32, seed = SEED, verbose = TRUE)
  cat("OOB R²:", rf_model$r.squared, "\n")

  model_path <- sprintf("%s/RF_model_M06_24m_%s.rds", out_dir, resp)
  saveRDS(rf_model, model_path)
  cat("Saved:", model_path, "\n")
}

cat("\n✓ M06 training complete\n")

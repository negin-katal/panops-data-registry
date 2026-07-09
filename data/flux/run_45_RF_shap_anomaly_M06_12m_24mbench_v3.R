# v3 — 2026-07-08: SHAP computation for M06 (C+D+M) 12m window
library(data.table)
library(ranger)
library(treeshap)

# ============================================================
# TreeSHAP for M06 x 12m — ANOMALY MEMORY
# Model: M06_12m (C + D + M)
# All 5 EFPs: GPPsat, NEPmax, ETmax, uWUE, WUE
# Output: RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06_12m.csv
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv"
cgs_file   <- "derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
N_TREES       <- 500
SEED          <- 42

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# ============================================================
# 1) Load and prepare
# ============================================================

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

climate_prefixes <- c(
  "TA_mean", "TA_p05", "TA_p95",
  "VPD_mean", "VPD_p05", "VPD_p95",
  "P_mean", "P_sum", "P_p05", "P_p95",
  "SW_IN_mean", "SW_IN_p05", "SW_IN_p95"
)

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

  dt_rf[[sprintf("%s_anom_lag1", prefix)]] <- apply(cbind(mat_cur[, -1], mat_lag1[, -12]), 1, agg_months, is_sum_var)
}

# Trait variables
trait_cols <- c("Vcmax25", "Jmax25", "Narea", "Pmass", "leaf_C", "leaf_N",
                "SRL", "root_d", "root_d_max", "root_d_min", "rootN_pct",
                "K_plant", "P_leaf", "P_wood", "WD")

# Disturbance variables
dist_cols <- c("mortality_intensity_pct_100m", "mortality_intensity_pct_500m",
               "deadwood_mean_pct_100m", "deadwood_mean_pct_500m",
               "forest_mean_pct_100m", "forest_mean_pct_500m",
               "loss_area_frac_100m", "loss_area_frac_500m")

# Meteo variables
meteo_cols <- c("tmin", "tmax", "prec", "vpd", "wind", "srad", "elev")

cat("Sample data prepared\n")

# ============================================================
# 2) Compute SHAP for each EFP — M06 (C+D+M) 12m
# ============================================================

shap_results <- list()

for (resp in RESPONSE_VARS) {
  cat("\n========== M06_12m_", resp, " ==========\n", sep = "")

  # Load trained RF model for M06 12m
  model_path <- sprintf("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_model_M06_12m_%s.rds", resp)
  if (!file.exists(model_path)) {
    cat("ERROR: Model file not found:", model_path, "\n")
    cat("Need to train M06 12m models first\n")
    next
  }

  rf_model <- readRDS(model_path)
  cat("Loaded model with", rf_model$num.trees, "trees\n")

  # Prepare features for M06: climate + disturbance + meteo (no traits)
  climate_cols <- grep("_anom_lag", names(dt_rf), value = TRUE)

  feature_cols <- c(climate_cols, dist_cols, meteo_cols)
  feature_cols <- feature_cols[feature_cols %in% names(dt_rf)]

  cat("Features:", length(feature_cols), "\n")

  X <- as.matrix(dt_rf[, ..feature_cols])
  X[is.na(X)] <- 0

  # TreeSHAP
  cat("Computing TreeSHAP...\n")
  unified_model <- ranger.unify(rf_model, X)
  shap_values <- treeshap(unified_model, X, verbose = TRUE)

  # Process SHAP results
  shap_mat <- as.matrix(shap_values$shaps)
  shap_long <- data.table(
    variable = rep(colnames(shap_mat), each = nrow(X)),
    mean_abs_shap = as.numeric(abs(shap_mat)),
    model = sprintf("M06_12m_%s", resp),
    response = resp,
    test_site = rep(dt_rf$SITE_ID, ncol(shap_mat)),
    group = "Predictors"
  )

  # Assign SHAP to groups
  shap_long[, group := fcase(
    variable %in% climate_cols, "Climate",
    variable %in% dist_cols, "Disturbance",
    variable %in% meteo_cols, "Meteo",
    default = "Other"
  )]

  shap_results[[resp]] <- shap_long
  cat("Done:", nrow(shap_long), "rows\n")
}

# Combine all SHAP
shap_all <- rbindlist(shap_results)

# Write output
out_file <- file.path(out_dir, "RF_site_shap_M06_12m.csv")
fwrite(shap_all, out_file)
cat("\n✓ Saved:", out_file, "\n")
cat("Total rows:", nrow(shap_all), "\n")

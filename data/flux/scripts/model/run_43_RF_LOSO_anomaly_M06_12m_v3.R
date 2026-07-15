# Train M06 (C+D+M) 12m window — v3 harmonized data
library(data.table)
library(ranger)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

# Load data
cat("Loading data...\n")
dt <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")
cgs <- fread("derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv")

if ("year" %in% names(cgs) && !"YEAR" %in% names(cgs)) setnames(cgs, "year", "YEAR")
cgs_keep <- c("SITE_ID", "YEAR", "CGS_weighted_doy")
cgs_keep <- cgs_keep[cgs_keep %in% names(cgs)]
dt <- merge(dt, cgs[, ..cgs_keep], by = c("SITE_ID", "YEAR"), all.x = TRUE)

# Exclude sites
exclude_sites <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)
dt <- dt[!SITE_ID %in% exclude_sites]

# Prepare anomaly features
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
  mat <- matrix(NA_real_, nrow = nrow(dt), ncol = 12)
  for (j in 1:12) {
    col <- sprintf("%s_M%02d%s", prefix, j, lag_suffix)
    if (col %in% names(dt)) mat[, j] <- dt[[col]]
  }
  mat
}

for (prefix in climate_prefixes) {
  is_sum_var <- grepl("_sum$", prefix)
  mat_cur  <- get_month_mat(prefix, "")
  mat_lag1 <- get_month_mat(prefix, "_lag1")

  dt[[sprintf("%s_anom_lag1", prefix)]] <- apply(cbind(mat_cur[, -1], mat_lag1[, -12]), 1, agg_months, is_sum_var)
}

# Feature sets
climate_cols <- grep("_anom_lag", names(dt), value = TRUE)
dist_cols <- c("mortality_intensity_pct_100m", "mortality_intensity_pct_500m",
               "deadwood_mean_pct_100m", "deadwood_mean_pct_500m",
               "forest_mean_pct_100m", "forest_mean_pct_500m",
               "loss_area_frac_100m", "loss_area_frac_500m")
meteo_cols <- c("tmin", "tmax", "prec", "vpd", "wind", "srad", "elev")

m06_12m_cols <- c(climate_cols, dist_cols, meteo_cols)
m06_12m_cols <- m06_12m_cols[m06_12m_cols %in% names(dt)]

# Response variables
response_vars <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

# Output directory
out_dir <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("Training M06 12m models using LOSO-CV...\n")
cat("Features:", length(m06_12m_cols), "\n")

# Training loop
for (resp in response_vars) {
  cat("\n===== M06_12m_", resp, " =====\n", sep = "")

  # Remove rows with missing response
  data <- dt[!is.na(dt[[resp]])]

  # Prepare features
  X <- as.matrix(data[, ..m06_12m_cols])
  X[is.na(X)] <- 0
  y <- data[[resp]]

  sites <- unique(data$SITE_ID)
  n_sites <- length(sites)

  cat("Sites:", n_sites, "| Samples:", nrow(data), "\n")

  # Train on full data (OOB will give RMSE estimate)
  rf_model <- ranger(
    x = X,
    y = y,
    num.trees = 500,
    mtry = max(1, ncol(X) %/% 3),
    importance = "permutation",
    seed = 42,
    num.threads = 7
  )

  cat("OOB R²:", round(1 - rf_model$prediction.error / var(y), 3), "\n")

  # Save model
  model_file <- file.path(out_dir, sprintf("RF_model_M06_12m_%s.rds", resp))
  saveRDS(rf_model, model_file)
  cat("✓ Saved:", model_file, "\n")
}

cat("\n=== All M06_12m models trained ===\n")

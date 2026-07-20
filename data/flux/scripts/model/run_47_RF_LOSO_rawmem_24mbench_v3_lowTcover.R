# FILTERED: Remove sites with < 10% tree cover
# Based on run_40_RF_LOSO_rawmem_24mbench_v3.R (July 3, 2026)
# Adapted for low tree cover filtering

library(data.table)
library(ranger)

# =========================================================
# LEAVE-ONE-SITE-OUT RF — RAW-LAG EFP MEMORY
# FILTERED: Sites with >= 10% mean tree cover only (157 sites)
# =========================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/V3_outputs/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_filtered_10pct.csv"
cgs_file   <- "derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/V3_outputs/RF_outputs_lowTcover_rawmem_24mbench"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE")
N_TREES       <- 500
SEED          <- 42

# Exclude sites from original script PLUS sites with < 10% tree cover
EXCLUDE_SITES <- c(
  # Original exclude list
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA",
  # Sites with < 10% tree cover (25 sites)
  "CN-HeM", "CN-Sdq", "CN-Zha", "ES-FtD", "ES-TzM", "RU-Ch2", "US-CMW", "US-CRK",
  "US-EDN", "US-ICh", "US-ICs", "US-ICt", "US-Jo1", "US-Rws", "US-Ses", "US-Vcm",
  "US-Wjs", "US-xGR", "US-xJR", "US-xMB", "US-xSR", "US-xTL", "US-YK2", "ZA-BfK",
  "ZA-BfS"
)

# Remove duplicates
EXCLUDE_SITES <- unique(EXCLUDE_SITES)

# =========================================================
# 1) Load, merge CGS, exclude bug sites
# =========================================================

dt  <- fread(model_file)
cgs <- fread(cgs_file)

if ("year" %in% names(cgs) && !"YEAR" %in% names(cgs)) setnames(cgs, "year", "YEAR")

cgs_keep <- c("SITE_ID", "YEAR", "CGS_weighted_doy", "CGS_midpoint_doy",
              "GS_start_doy", "GS_end_doy", "GS_length_days")
cgs_keep <- cgs_keep[cgs_keep %in% names(cgs)]
dt <- merge(dt, cgs[, ..cgs_keep], by = c("SITE_ID", "YEAR"), all.x = TRUE)

n_before <- uniqueN(dt$SITE_ID)
dt <- dt[!SITE_ID %in% EXCLUDE_SITES]
n_after  <- uniqueN(dt$SITE_ID)
cat(sprintf("Excluded %d bug sites (%d -> %d sites)\n",
            n_before - n_after, n_before, n_after))

cat("Dataset:", nrow(dt), "rows x", ncol(dt), "cols\n")
cat("Sites  :", uniqueN(dt$SITE_ID), "\n")
cat("Years  :", min(dt$YEAR), "-", max(dt$YEAR), "\n")
cat("CGS available:", sum(!is.na(dt$CGS_weighted_doy)), "/", nrow(dt), "rows\n")

# =========================================================
# 2) Compute pre-CGS climate summaries for each year tier
# =========================================================

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

precgs_cols_created <- character(0)

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

  new_12m <- paste0(prefix, "_CGS12m")
  dt_rf[[new_12m]] <- vapply(seq_len(nrow(dt_rf)), function(i) {
    m         <- cgs_month_vec[i]
    cur_vals  <- mat_cur[i,  1:m,          drop = TRUE]
    lag1_vals <- if (m < 12) mat_lag1[i, (m+1):12, drop = TRUE] else numeric(0)
    agg_months(c(lag1_vals, cur_vals), is_sum_var)
  }, NA_real_)
  precgs_cols_created <- c(precgs_cols_created, new_12m)

  new_24m <- paste0(prefix, "_CGS24m")
  dt_rf[[new_24m]] <- vapply(seq_len(nrow(dt_rf)), function(i) {
    m         <- cgs_month_vec[i]
    cur_vals  <- mat_cur[i, 1:m,                    drop = TRUE]
    lag1_vals <- if (m < 12) mat_lag1[i, (m+1):12, drop = TRUE] else numeric(0)
    lag2_vals <- mat_lag2[i,  1:m,                  drop = TRUE]
    agg_months(c(lag2_vals, lag1_vals, cur_vals), is_sum_var)
  }, NA_real_)
  precgs_cols_created <- c(precgs_cols_created, new_24m)
}

# =========================================================
# 3) Prepare feature sets: 12m & 24m windows
# =========================================================

all_trait_cols <- grep("^(leaf_|root_|hydraulic_|ns_)", names(dt_rf), value = TRUE)
all_dist_cols  <- grep("^(new_mortality|deadwood|forest_loss).*_\\d{3}m$", names(dt_rf), value = TRUE)
all_meteo_cols <- grep("^(TA|VPD|P|SW_IN)_(mean|p05|p95|sum)_M", names(dt_rf), value = TRUE)

# EFP memory RAW LAG (not anomalies)
efp_lag_12m <- grep("^(GPPsat|NEPmax|ETmax|uWUE|WUE)_lag1$", names(dt_rf), value = TRUE)
efp_lag_24m <- c(grep("^(GPPsat|NEPmax|ETmax|uWUE|WUE)_lag1$", names(dt_rf), value = TRUE),
                 grep("^(GPPsat|NEPmax|ETmax|uWUE|WUE)_lag2$", names(dt_rf), value = TRUE))

# Climate summaries
climate_12m <- precgs_cols_created[grepl("CGS12m", precgs_cols_created)]
climate_24m <- precgs_cols_created[grepl("CGS24m", precgs_cols_created)]

cat("\n=== Feature set sizes ===\n")
cat("Traits:", length(all_trait_cols), "\n")
cat("Dist 12m:", length(all_dist_cols), "\n")
cat("Dist 24m:", length(all_dist_cols), "\n")
cat("Meteo 12m (pre-CGS):", length(climate_12m), "\n")
cat("Meteo 24m (pre-CGS):", length(climate_24m), "\n")
cat("EFP lag 12m:", length(efp_lag_12m), "\n")
cat("EFP lag 24m:", length(efp_lag_24m), "\n")

# =========================================================
# 4) M01–M08: 12m and 24m windows, raw-lag memory
# =========================================================

results_all <- list()

for (resp_var in RESPONSE_VARS) {
  cat("\n", resp_var, ":\n", sep = "")

  for (window in c("12m", "24m")) {

    climate_cols <- if (window == "12m") climate_12m else climate_24m
    efp_mem_cols <- if (window == "12m") efp_lag_12m else efp_lag_24m

    model_configs <- list(
      M01 = c(climate_cols),
      M02 = c(climate_cols, all_dist_cols),
      M03 = c(climate_cols, all_trait_cols),
      M04 = c(climate_cols, all_trait_cols, all_dist_cols),
      M05 = c(climate_cols, efp_mem_cols),
      M06 = c(climate_cols, all_dist_cols, efp_mem_cols),
      M07 = c(climate_cols, all_trait_cols, efp_mem_cols),
      M08 = c(climate_cols, all_trait_cols, all_dist_cols, efp_mem_cols)
    )

    for (model_name in names(model_configs)) {
      features <- model_configs[[model_name]]

      # LOSO CV
      sites    <- unique(dt_rf$SITE_ID)
      n_sites  <- length(sites)
      preds    <- data.table(SITE_ID = character(), YEAR = integer(),
                            observed = numeric(), predicted = numeric())

      for (i in seq_along(sites)) {
        test_site  <- sites[i]
        train_idx  <- dt_rf$SITE_ID != test_site
        test_idx   <- dt_rf$SITE_ID == test_site

        train_subset <- dt_rf[train_idx]
        test_subset  <- dt_rf[test_idx]

        # Remove NAs
        keep_train <- complete.cases(train_subset[, ..features]) & !is.na(train_subset[[resp_var]])
        keep_test  <- complete.cases(test_subset[, ..features]) & !is.na(test_subset[[resp_var]])

        if (sum(keep_train) < 10 || sum(keep_test) == 0) next

        train_cc <- train_subset[keep_train]
        test_cc  <- test_subset[keep_test]

        # Train RF
        rf <- ranger(x = train_cc[, ..features],
                    y = train_cc[[resp_var]],
                    num.trees = N_TREES,
                    seed = SEED, num.threads = 4)

        # Predict
        pred <- predict(rf, test_cc[, ..features])$predictions

        preds <- rbind(preds,
          data.table(SITE_ID = test_cc$SITE_ID,
                    YEAR = test_cc$YEAR,
                    observed = test_cc[[resp_var]],
                    predicted = pred))

        if (i %% 20 == 0) cat(sprintf("  %s %s: %d/%d sites\n",
                              model_name, window, i, n_sites))
      }

      if (nrow(preds) > 0) {
        rmse <- sqrt(mean((preds$observed - preds$predicted)^2))
        r2   <- 1 - (sum((preds$observed - preds$predicted)^2) /
                    sum((preds$observed - mean(preds$observed))^2))

        results_all[[sprintf("%s_%s_%s", model_name, window, resp_var)]] <-
          list(rmse = rmse, r2 = r2, preds = preds, n_pred = nrow(preds),
               n_sites = uniqueN(preds$SITE_ID))

        cat(sprintf("    %s: RMSE=%.2f, R²=%.3f, n=%d\n",
                   model_name, rmse, r2, nrow(preds)))
      }
    }
  }
}

# =========================================================
# 5) Save results
# =========================================================

# Compile metrics table
metrics_list <- lapply(names(results_all), function(key) {
  res <- results_all[[key]]
  parts <- strsplit(key, "_")[[1]]
  data.table(model = parts[1], window = parts[2], response = parts[3],
            n_predictors = NA_integer_,
            n_rows = res$n_pred, n_sites = res$n_sites,
            n_pairs = res$n_pred, RMSE = res$rmse, R2 = res$r2)
})
metrics_table <- rbindlist(metrics_list)

# Save metrics
fwrite(metrics_table, file.path(out_dir, "RF_metrics_LOSO.csv"))
cat("\nMetrics saved to:", file.path(out_dir, "RF_metrics_LOSO.csv"), "\n")

# Compile all predictions
all_preds <- rbindlist(lapply(results_all, function(x) x$preds))
all_preds[, model := rep(names(results_all), sapply(results_all, function(x) nrow(x$preds)))]

fwrite(all_preds, file.path(out_dir, "RF_predictions_LOSO.csv"))
cat("Predictions saved to:", file.path(out_dir, "RF_predictions_LOSO.csv"), "\n")

cat("\n✅ LOW TREE COVER FILTERING (RAW-LAG): Complete!\n")
cat("Sites analyzed:", uniqueN(all_preds$SITE_ID), "\n")
cat("Output directory:", out_dir, "\n")

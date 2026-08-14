#!/usr/bin/env Rscript
# ============================================================================
# V10 LightGBM Training (CV-TUNED) - LOSO
# Mirror of run_v10_RF_ranger.R / run_v10_XGB.R: SAME datasets, SAME predictor
# blocks, SAME 24 model specs, SAME LOSO evaluation. ONLY the learner differs.
# Outputs go to LGB_v10{_all_sites}/ so RF and XGBoost results are never touched.
# ============================================================================

library(data.table)
library(lightgbm)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript run_v10_LGB.R <dataset_type> [smoke]")

dataset_type <- args[1]
SMOKE <- length(args) >= 2 && args[2] == "smoke"

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/LGB_v10_tuned'
  datadir <- 'derived_tables/outputs_afterEGU_results/v10'; prefix <- 'v10'
} else if (dataset_type == "tc50") {
  output_base <- 'derived_tables/outputs_afterEGU_results/LGB_v10_tc50_tuned'
  datadir <- 'derived_tables/outputs_afterEGU_results/v10_tc50'; prefix <- 'v10_tc50'
} else if (dataset_type == "all_sites") {
  output_base <- 'derived_tables/outputs_afterEGU_results/LGB_v10_all_sites_tuned'
  datadir <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'; prefix <- 'v10_all'
} else stop("Invalid dataset_type")

dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 LIGHTGBM TUNED TRAINING (LOSO): %s%s\n", toupper(dataset_type),
            if (SMOKE) "  [SMOKE TEST]" else ""))
cat(strrep("=", 80), "\n\n", sep="")

# ============================================================================
# Config
# ============================================================================

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
SEED    <- 42
N_CORES <- as.integer(Sys.getenv("V10_LGB_CORES", "60"))

# --- LightGBM hyperparameters (untuned) -------------------------------------
# Deliberately matched to the XGBoost run wherever a direct analogue exists, so
# the comparison isolates the ALGORITHM (leaf-wise boosting + histogram binning)
# rather than differing library defaults:
#   nrounds 500            = XGB nrounds / RF num.trees
#   learning_rate 0.05     = XGB learning_rate
#   feature_fraction 0.8   = XGB colsample_bytree
#   bagging_fraction 0.8   = XGB subsample  (bagging_freq=1 to actually apply it)
#   num_leaves 31          LightGBM default; XGB grows depth-wise to max_depth 6
#   min_data_in_leaf 5     LightGBM's default of 20 is very restrictive at
#                          n ~ 400 site-years; 5 matches ranger's min.node.size
# The genuine difference that remains: LightGBM grows LEAF-WISE (best-first),
# XGBoost grows DEPTH-WISE (level-wise).
NROUNDS <- 500

# --- per-response complexity, selected by GROUPED 5-FOLD CV (site groups) ------
# scripts/lgb_tune_regularisation.R -> regularisation_sweep_ext.csv
# Selection used only grouped CV, never the reported LOSO, so no leakage.
SWEEP <- "plots/V10/LightGBM/regularisation_sweep_ext.csv"
TUNED <- local({
  R <- fread(SWEEP)
  R[, rk := frank(-cv_r2), by = .(response, model)]
  best <- R[, .(mr = mean(rk)), by = .(response, min_data_in_leaf, num_leaves)][
             , .SD[which.min(mr)], by = response]
  setNames(split(best[, .(min_data_in_leaf, num_leaves)], best$response), best$response)
})
cat("CV-selected config per response:\n")
for (r in names(TUNED)) cat(sprintf("  %-7s min_data_in_leaf=%2d  num_leaves=%2d\n",
    r, TUNED[[r]]$min_data_in_leaf, TUNED[[r]]$num_leaves))

LGB_PARAMS <- list(
  objective        = "regression",
  metric           = "rmse",
  learning_rate    = 0.05,
  num_leaves       = 31,
  min_data_in_leaf = 5,
  feature_fraction = 0.8,
  bagging_fraction = 0.8,
  bagging_freq     = 1,
  num_threads      = 1,     # parallelism comes from mclapply over LOSO folds
  seed             = SEED,
  verbosity        = -1
)

model_specs <- list(
  M1_12m  = 'C',            M1_24m  = 'C',
  M2_12m  = 'C+D',          M2_24m  = 'C+D',
  M3_12m  = 'C+T',          M3_24m  = 'C+T',
  M4_12m  = 'C+T+D',        M4_24m  = 'C+T+D',
  M5_raw_12m  = 'C+M_raw',  M5_raw_24m  = 'C+M_raw',
  M5_anom_12m = 'C+M_anom', M5_anom_24m = 'C+M_anom',
  M6_raw_12m  = 'C+D+M_raw',  M6_raw_24m  = 'C+D+M_raw',
  M6_anom_12m = 'C+D+M_anom', M6_anom_24m = 'C+D+M_anom',
  M7_raw_12m  = 'C+T+M_raw',  M7_raw_24m  = 'C+T+M_raw',
  M7_anom_12m = 'C+T+M_anom', M7_anom_24m = 'C+T+M_anom',
  M8_raw_12m  = 'C+T+D+M_raw',  M8_raw_24m  = 'C+T+D+M_raw',
  M8_anom_12m = 'C+T+D+M_anom', M8_anom_24m = 'C+T+D+M_anom'
)

if (SMOKE) {
  RESPONSE_VARS <- c("GPPsat")
  model_specs <- model_specs[c("M6_raw_12m", "M2_12m")]
}

# ============================================================================
# Predictor selection  (verbatim from run_v10_RF_ranger.R)
# ============================================================================

get_predictor_cols <- function(df, model_type, window, response) {
  all_cols <- colnames(df)
  if (window == '12m') {
    climate_cols <- grep('^lag1_', all_cols, value = TRUE)
  } else {
    climate_cols <- c(grep('^lag1_', all_cols, value = TRUE), grep('^lag2_', all_cols, value = TRUE))
  }
  trait_cols <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', all_cols, value = TRUE)
  dist_cols  <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', all_cols, value = TRUE)

  memory_cols <- c()
  if (grepl('_raw$', model_type)) {
    pattern <- if (window == '12m') paste0('^', response, '_lag1$') else paste0('^', response, '_lag[12]$')
    memory_cols <- grep(pattern, all_cols, value = TRUE)
  } else if (grepl('_anom$', model_type)) {
    pattern <- if (window == '12m') paste0('^', response, '_anom_lag1$') else paste0('^', response, '_anom_lag[12]$')
    memory_cols <- grep(pattern, all_cols, value = TRUE)
  }

  predictors <- c()
  if (grepl('C', model_type)) predictors <- c(predictors, climate_cols)
  if (grepl('T', model_type)) predictors <- c(predictors, trait_cols)
  if (grepl('D', model_type)) predictors <- c(predictors, dist_cols)
  if (grepl('M', model_type)) predictors <- c(predictors, memory_cols)
  unique(predictors[!is.na(predictors)])
}

# ============================================================================
# Main LOSO loop
# ============================================================================

pred_results   <- data.table()
metric_results <- data.table()
t_start <- Sys.time()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))

  b1_file <- sprintf('%s/%s_B1_%s_harmonized.csv', datadir, prefix, resp)
  b2_file <- sprintf('%s/%s_B2_%s_harmonized.csv', datadir, prefix, resp)
  if (!file.exists(b1_file)) { cat(sprintf("  ERROR: not found: %s\n", b1_file)); next }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (model_id in names(model_specs)) {
    window     <- if (grepl('12m$', model_id)) '12m' else '24m'
    df_data    <- if (window == '12m') df_b1 else df_b2
    predictors <- get_predictor_cols(df_data, model_specs[[model_id]], window, resp)

    use_cols <- unique(c('SITE_ID', 'YEAR', resp, predictors))
    use_cols <- use_cols[use_cols %in% colnames(df_data)]

    model_dt <- as.data.table(df_data[, use_cols])
    model_dt <- model_dt[!is.na(get(resp))]

    site_ids <- sort(unique(model_dt$SITE_ID))
    xvars_ok <- setdiff(names(model_dt), c("SITE_ID", "YEAR", resp))
    t0 <- Sys.time()

    fold_list <- mclapply(site_ids, function(test_site) {
      train_dt <- model_dt[SITE_ID != test_site]
      test_dt  <- model_dt[SITE_ID == test_site]

      train_cc <- train_dt[complete.cases(train_dt[, c(resp, xvars_ok), with = FALSE])]
      test_cc  <- test_dt[complete.cases(test_dt[, ..xvars_ok])]
      if (nrow(train_cc) < 10 || nrow(test_cc) == 0) return(NULL)

      Xtr <- as.matrix(train_cc[, ..xvars_ok])
      Xte <- as.matrix(test_cc[, ..xvars_ok])

      pars <- LGB_PARAMS
      if (!is.null(TUNED[[resp]])) {
        pars$min_data_in_leaf <- TUNED[[resp]]$min_data_in_leaf
        pars$num_leaves       <- TUNED[[resp]]$num_leaves
      }
      bst <- tryCatch(
        lgb.train(params = pars,
                  data    = lgb.Dataset(Xtr, label = train_cc[[resp]]),
                  nrounds = NROUNDS,
                  verbose = -1),
        error = function(e) NULL)
      if (is.null(bst)) return(NULL)

      data.table(model = model_id, response = resp, SITE_ID = test_site,
                 YEAR = test_cc$YEAR, observed = test_cc[[resp]],
                 predicted = as.numeric(predict(bst, Xte)))
    }, mc.cores = N_CORES)

    fold_preds <- rbindlist(Filter(Negate(is.null), fold_list), fill = TRUE)
    el <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
    cat(sprintf("  %-14s %3d sites, %3d predictors  (%5.1fs)\n",
                model_id, length(site_ids), length(predictors), el))

    if (nrow(fold_preds) > 0) {
      pred_results <- rbind(pred_results, fold_preds)
      rmse   <- sqrt(mean((fold_preds$predicted - fold_preds$observed)^2, na.rm = TRUE))
      mae    <- mean(abs(fold_preds$predicted - fold_preds$observed), na.rm = TRUE)
      ss_res <- sum((fold_preds$observed - fold_preds$predicted)^2, na.rm = TRUE)
      ss_tot <- sum((fold_preds$observed - mean(fold_preds$observed, na.rm = TRUE))^2, na.rm = TRUE)
      metric_results <- rbind(metric_results, data.table(
        model = model_id, response = resp,
        n_predictors = length(predictors), n_pairs = nrow(fold_preds),
        RMSE = rmse, MAE = mae, R2 = 1 - (ss_res / ss_tot)))
    }
  }
}

# ============================================================================
# Save outputs
# ============================================================================

cat("\nSaving outputs...\n")
if (nrow(pred_results) > 0) {
  f <- file.path(output_base, "LGB_predictions_LOSO.csv")
  fwrite(pred_results, f); cat(sprintf("OK %s (%d rows)\n", f, nrow(pred_results)))
}
if (nrow(metric_results) > 0) {
  f <- file.path(output_base, "LGB_metrics_LOSO.csv")
  fwrite(metric_results, f); cat(sprintf("OK %s (%d rows)\n", f, nrow(metric_results)))
  cat("\nMean R2 by memory group:\n")
  print(as.data.frame(metric_results[, .(R2 = round(mean(R2), 3)),
        by = .(grp = fifelse(grepl("_raw_", model), "raw",
                      fifelse(grepl("_anom_", model), "anom", "none")))]))
}

cat(sprintf("\nTotal elapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat(strrep("=", 80), "\n")
cat("V10 LIGHTGBM TUNED TRAINING COMPLETE:", output_base, "\n")
cat(strrep("=", 80), "\n\n")

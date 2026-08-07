#!/usr/bin/env Rscript
# ============================================================================
# V10 XGBoost Training (CV-TUNED complexity) - LOSO
# Mirror of run_v10_RF_ranger.R: SAME datasets, SAME predictor blocks, SAME
# 24 model specs, SAME LOSO evaluation. ONLY the learner differs (ranger -> xgboost).
# Outputs go to XGB_v10{_all_sites}/ so the RF results are never touched.
# ============================================================================

library(data.table)
library(xgboost)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_v10_XGB.R <dataset_type> [smoke]")
}

dataset_type <- args[1]
SMOKE <- length(args) >= 2 && args[2] == "smoke"

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/XGB_v10_tuned'
  datadir <- 'derived_tables/outputs_afterEGU_results/v10'
  prefix  <- 'v10'
} else if (dataset_type == "all_sites") {
  output_base <- 'derived_tables/outputs_afterEGU_results/XGB_v10_all_sites_tuned'
  datadir <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'
  prefix  <- 'v10_all'
} else {
  stop("Invalid dataset_type")
}

dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 XGBOOST TUNED TRAINING (LOSO): %s%s\n", toupper(dataset_type),
            if (SMOKE) "  [SMOKE TEST]" else ""))
cat(strrep("=", 80), "\n\n", sep="")

# ============================================================================
# Config
# ============================================================================

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
SEED    <- 42
N_CORES <- 60   # LOSO folds are embarrassingly parallel

# --- XGBoost hyperparameters (untuned, sensible defaults) --------------------
# NNROUNDS mirrors the RF's 500 trees. learning_rate is lowered from the xgboost
# default (0.3) because 500 boosting rounds at 0.3 badly overfits n~400 site-years.
# subsample/colsample give the row/column randomness that makes the ensemble
# comparable in spirit to a random forest. Change these in an exp0N experiment.
NROUNDS <- 500

# --- per-response complexity, selected by GROUPED 5-FOLD CV (site groups) -----
# scripts/xgb_tune_hyperparams.R -> regularisation_sweep_xgb_combined.csv
# Selection used only grouped CV, never the reported LOSO, so no leakage.
TUNED <- local({
  R <- fread("plots/V10/XGBoost/regularisation_sweep_xgb_combined.csv")
  R[, rk := frank(-cv_r2), by = .(response, model)]
  best <- R[, .(mr = mean(rk)), by = .(response, max_depth, min_child_weight)][
             , .SD[which.min(mr)], by = response]
  setNames(split(best[, .(max_depth, min_child_weight)], best$response), best$response)
})
cat("CV-selected config per response:\n")
for (r in names(TUNED)) cat(sprintf("  %-7s max_depth=%d  min_child_weight=%d\n",
    r, TUNED[[r]]$max_depth, TUNED[[r]]$min_child_weight))

XGB_PARAMS <- list(
  objective        = "reg:squarederror",
  learning_rate    = 0.05,
  max_depth        = 6,
  subsample        = 0.8,
  colsample_bytree = 0.8,
  min_child_weight = 1,
  nthread          = 1,      # 1 thread per fit; parallelism comes from mclapply
  seed             = SEED
)

model_specs <- list(
  M1_12m  = 'C',
  M1_24m  = 'C',
  M2_12m  = 'C+D',
  M2_24m  = 'C+D',
  M3_12m  = 'C+T',
  M3_24m  = 'C+T',
  M4_12m  = 'C+T+D',
  M4_24m  = 'C+T+D',
  M5_raw_12m  = 'C+M_raw',
  M5_raw_24m  = 'C+M_raw',
  M5_anom_12m = 'C+M_anom',
  M5_anom_24m = 'C+M_anom',
  M6_raw_12m  = 'C+D+M_raw',
  M6_raw_24m  = 'C+D+M_raw',
  M6_anom_12m = 'C+D+M_anom',
  M6_anom_24m = 'C+D+M_anom',
  M7_raw_12m  = 'C+T+M_raw',
  M7_raw_24m  = 'C+T+M_raw',
  M7_anom_12m = 'C+T+M_anom',
  M7_anom_24m = 'C+T+M_anom',
  M8_raw_12m  = 'C+T+D+M_raw',
  M8_raw_24m  = 'C+T+D+M_raw',
  M8_anom_12m = 'C+T+D+M_anom',
  M8_anom_24m = 'C+T+D+M_anom'
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
    climate_cols <- grep('^lag1_', all_cols, value = TRUE)
    climate_cols <- c(climate_cols, grep('^lag2_', all_cols, value = TRUE))
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

  if (!file.exists(b1_file)) {
    cat(sprintf("  ERROR: File not found: %s\n", b1_file))
    next
  }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (model_id in names(model_specs)) {
    window     <- if (grepl('12m$', model_id)) '12m' else '24m'
    model_spec <- model_specs[[model_id]]
    df_data    <- if (window == '12m') df_b1 else df_b2

    predictors <- get_predictor_cols(df_data, model_spec, window, resp)

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

      pars <- XGB_PARAMS
      if (!is.null(TUNED[[resp]])) {
        pars$max_depth        <- TUNED[[resp]]$max_depth
        pars$min_child_weight <- TUNED[[resp]]$min_child_weight
      }
      bst <- tryCatch(
        xgb.train(params = pars,
                  data    = xgb.DMatrix(Xtr, label = train_cc[[resp]]),
                  nrounds = NROUNDS,
                  verbose = 0),
        error = function(e) NULL)
      if (is.null(bst)) return(NULL)

      data.table(
        model     = model_id,
        response  = resp,
        SITE_ID   = test_site,
        YEAR      = test_cc$YEAR,
        observed  = test_cc[[resp]],
        predicted = predict(bst, xgb.DMatrix(Xte))
      )
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
      r2     <- 1 - (ss_res / ss_tot)

      metric_results <- rbind(metric_results, data.table(
        model = model_id, response = resp,
        n_predictors = length(predictors), n_pairs = nrow(fold_preds),
        RMSE = rmse, MAE = mae, R2 = r2
      ))
    }
  }
}

# ============================================================================
# Save outputs
# ============================================================================

cat("\nSaving outputs...\n")

if (nrow(pred_results) > 0) {
  pred_file <- file.path(output_base, "XGB_predictions_LOSO.csv")
  fwrite(pred_results, pred_file)
  cat(sprintf("OK %s (%d rows)\n", pred_file, nrow(pred_results)))
}

if (nrow(metric_results) > 0) {
  metric_file <- file.path(output_base, "XGB_metrics_LOSO.csv")
  fwrite(metric_results, metric_file)
  cat(sprintf("OK %s (%d rows)\n", metric_file, nrow(metric_results)))
  cat("\nMean R2 by model family:\n")
  print(metric_results[, .(R2 = round(mean(R2), 3)), by = .(fam = sub('_.*', '', model))])
}

cat(sprintf("\nTotal elapsed: %.1f min\n",
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat(strrep("=", 80), "\n")
cat("V10 XGBOOST TUNED TRAINING COMPLETE:", output_base, "\n")
cat(strrep("=", 80), "\n\n")

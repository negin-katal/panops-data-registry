#!/usr/bin/env Rscript
# ============================================================================
# V10 TreeSHAP extraction from XGBoost models (M4 / M6 / M8, raw + anom)
# Mirror of run_v10_extract_SHAP_from_ranger.R, using treeshap::xgboost.unify.
# Models are re-trained on the full data in-process (xgb.Booster objects do not
# survive saveRDS across sessions), then SHAP is computed per held-out site
# exactly as in the ranger version: unify on train-without-site, explain test rows.
# ============================================================================

library(data.table)
library(xgboost)
library(treeshap)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript run_v10_XGB_SHAP.R <dataset_type> [smoke]")
dataset_type <- args[1]
SMOKE <- length(args) >= 2 && args[2] == "smoke"

# Override with V10_SHAP_CORES to share the machine with a concurrent training run.
N_CORES <- if (SMOKE) 4 else as.integer(Sys.getenv("V10_SHAP_CORES", "60"))

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/XGB_v10'
  datadir <- 'derived_tables/outputs_afterEGU_results/v10'; prefix <- 'v10'
} else if (dataset_type == "all_sites") {
  output_base <- 'derived_tables/outputs_afterEGU_results/XGB_v10_all_sites'
  datadir <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'; prefix <- 'v10_all'
} else stop("Invalid dataset_type")

dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 XGBOOST TREESHAP: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep="")

# --- must match run_v10_XGB.R -----------------------------------------------
NROUNDS <- 500
XGB_PARAMS <- list(objective = "reg:squarederror", learning_rate = 0.05, max_depth = 6,
                   subsample = 0.8, colsample_bytree = 0.8, min_child_weight = 1,
                   nthread = 1, seed = 42)

RESPONSE_VARS <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')

model_specs <- list(
  M4_12m      = 'C+T+D',      M4_24m      = 'C+T+D',
  M6_raw_12m  = 'C+D+M_raw',  M6_raw_24m  = 'C+D+M_raw',
  M6_anom_12m = 'C+D+M_anom', M6_anom_24m = 'C+D+M_anom',
  M8_raw_12m  = 'C+T+D+M_raw',  M8_raw_24m  = 'C+T+D+M_raw',
  M8_anom_12m = 'C+T+D+M_anom', M8_anom_24m = 'C+T+D+M_anom'
)

get_predictor_group <- function(var) {
  if (grepl('^lag1_|^lag2_', var)) return('Climate')
  if (grepl('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', var)) return('Traits')
  if (grepl('^(absolute_|relative_|new_|mortality_|disturbance_)', var)) return('Disturbance')
  if (grepl('_lag[12]$|_anom_lag[12]$', var)) return('Memory')
  return('Other')
}

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

if (SMOKE) {
  RESPONSE_VARS <- c("GPPsat")
  model_specs   <- model_specs["M6_raw_12m"]
}

shap_results <- list()
t_start <- Sys.time()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))

  b1_file <- sprintf('%s/%s_B1_%s_harmonized.csv', datadir, prefix, resp)
  b2_file <- sprintf('%s/%s_B2_%s_harmonized.csv', datadir, prefix, resp)
  if (!file.exists(b1_file)) { cat("  ERROR: file not found\n"); next }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (model_id in names(model_specs)) {
    window  <- if (grepl('12m$', model_id)) '12m' else '24m'
    df_data <- if (window == '12m') df_b1 else df_b2
    xvars   <- get_predictor_cols(df_data, model_specs[[model_id]], window, resp)

    df_model <- df_data[, c('SITE_ID', 'YEAR', resp, xvars), drop = FALSE]
    df_model <- df_model[complete.cases(df_model), ]
    sites_test <- unique(df_model$SITE_ID)

    cat(sprintf("  %-14s %3d preds: ", model_id, length(xvars)))

    # full-data model (mirrors the production RF models used for SHAP)
    Xfull <- as.matrix(df_model[, xvars, drop = FALSE])
    bst <- tryCatch(
      xgb.train(params = XGB_PARAMS, data = xgb.DMatrix(Xfull, label = df_model[[resp]]),
                nrounds = NROUNDS, verbose = 0),
      error = function(e) NULL)
    if (is.null(bst)) { cat("model FAILED\n"); next }

    fold_shap <- mclapply(sites_test, function(test_site) {
      train_df <- df_model[df_model$SITE_ID != test_site, xvars, drop = FALSE]
      test_df  <- df_model[df_model$SITE_ID == test_site, xvars, drop = FALSE]
      if (nrow(test_df) == 0) return(NULL)

      shap_result <- tryCatch({
        unified <- xgboost.unify(bst, train_df)
        treeshap(unified, test_df, verbose = FALSE)
      }, error = function(e) NULL)
      if (is.null(shap_result)) return(NULL)

      shap_mat <- as.data.table(shap_result$shaps)
      mean_abs_shap <- shap_mat[, lapply(.SD, function(x) mean(abs(x), na.rm = TRUE))]
      shap_long <- melt(mean_abs_shap, measure.vars = names(mean_abs_shap),
                        variable.name = "variable", value.name = "mean_abs_shap")
      shap_long[, `:=`(model = model_id, response = resp, test_site = test_site)]
      shap_long
    }, mc.cores = N_CORES)

    ok <- Filter(Negate(is.null), fold_shap)
    if (length(ok) > 0) {
      shap_results[[length(shap_results) + 1]] <- rbindlist(ok, fill = TRUE)
      cat(sprintf("OK (%d sites)\n", length(ok)))
    } else cat("no results\n")
  }
}

cat("\nSaving SHAP results...\n")
if (length(shap_results) > 0) {
  shap_dt <- rbindlist(shap_results, fill = TRUE)
  shap_dt[, variable := as.character(variable)]
  shap_dt[, group := sapply(variable, get_predictor_group)]

  out_path <- file.path(output_base,
    if (SMOKE) "XGB_site_shap_SMOKE.csv" else "XGB_site_shap_M04_M08.csv")
  fwrite(shap_dt, out_path)
  cat(sprintf("OK %s (%d rows)\n", out_path, nrow(shap_dt)))
  cat(sprintf("  Sites: %d | Models: %d | Responses: %s\n",
              uniqueN(shap_dt$test_site), uniqueN(shap_dt$model),
              paste(unique(shap_dt$response), collapse = ", ")))
} else cat("ERROR: No SHAP results collected\n")

cat(sprintf("\nElapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat(strrep("=", 80), "\n")
cat("V10 XGBOOST TREESHAP COMPLETE\n")
cat(strrep("=", 80), "\n\n")

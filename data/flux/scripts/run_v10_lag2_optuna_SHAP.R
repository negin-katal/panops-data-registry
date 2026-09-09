#!/usr/bin/env Rscript
# ============================================================================
# TreeSHAP for the lag2-corrected 24m models (M4/M6/M8, raw+anom) - the 5
# D-containing 24m model IDs only. Mirrors run_v10_{XGB,RF,LGB}_optuna_SHAP.R
# exactly (same full-data-model-then-per-site-explain design, same RF/LGB
# safe-name handling for treeshap), but reads the lag2 B2 datasets and the
# freshly-retuned lag2 Optuna configs (plots/V10/Optuna_lag2/).
#
#   Rscript run_v10_lag2_optuna_SHAP.R <RF|XGB|LGB> <tc30|tc50> [smoke]
#
# Writes {output_base}/{FAM}_site_shap_M04_M08_24m.csv - a 24m-only sibling of
# the production file, never overwriting it.
# ============================================================================
suppressMessages({library(data.table); library(treeshap); library(parallel)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript run_v10_lag2_optuna_SHAP.R <RF|XGB|LGB> <tc30|tc50> [smoke]")
fam <- args[1]; ds <- args[2]
SMOKE <- length(args) >= 3 && args[3] == "smoke"
stopifnot(fam %in% c("RF","XGB","LGB"), ds %in% c("tc30","tc50"))

N_CORES <- if (SMOKE) 4 else as.integer(Sys.getenv("V10_SHAP_CORES", "60"))

if (ds == "tc30") {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_lag2";      prefix <- "v10_lag2"
  output_base <- sprintf("derived_tables/outputs_afterEGU_results/%s_v10_lag2_optuna", fam)
} else {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_tc50_lag2"; prefix <- "v10_tc50_lag2"
  output_base <- sprintf("derived_tables/outputs_afterEGU_results/%s_v10_tc50_lag2_optuna", fam)
}
dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 78), "\n", sep = "")
cat(sprintf("LAG2 24m TREESHAP: %s | %s%s\n", fam, ds, if (SMOKE) " [SMOKE]" else ""))
cat(strrep("=", 78), "\n\n", sep = "")

OPTUNA <- local({
  cfg <- fread(sprintf("plots/V10/Optuna_lag2/%s_best_configs.csv", ds))
  cfg <- cfg[learner == fam]
  setNames(split(cfg, cfg$response), cfg$response)
})

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
model_specs <- list(M4_24m='C+T+D', M6_raw_24m='C+D+M_raw', M6_anom_24m='C+D+M_anom',
                    M8_raw_24m='C+T+D+M_raw', M8_anom_24m='C+T+D+M_anom')
if (SMOKE) { RESPONSE_VARS <- "GPPsat"; model_specs <- model_specs["M6_raw_24m"] }

get_predictor_group <- function(var) {
  if (grepl('^lag1_|^lag2_', var)) return('Climate')
  if (grepl('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', var)) return('Traits')
  if (grepl('^(absolute_|relative_|new_|mortality_|disturbance_)', var)) return('Disturbance')
  if (grepl('_lag[12]$|_anom_lag[12]$', var)) return('Memory')
  return('Other')
}
get_predictor_cols <- function(df, spec, response) {
  ac <- colnames(df)
  climate <- c(grep('^lag1_', ac, value = TRUE), grep('^lag2_', ac, value = TRUE))
  traits  <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', ac, value = TRUE)
  dist    <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', ac, value = TRUE)
  mem <- c()
  if (grepl('_raw$',  spec)) mem <- grep(paste0('^', response, '_lag[12]$'), ac, value = TRUE)
  if (grepl('_anom$', spec)) mem <- grep(paste0('^', response, '_anom_lag[12]$'), ac, value = TRUE)
  p <- c()
  if (grepl('C', spec)) p <- c(p, climate); if (grepl('T', spec)) p <- c(p, traits)
  if (grepl('D', spec)) p <- c(p, dist);    if (grepl('M', spec)) p <- c(p, mem)
  unique(p[!is.na(p)])
}
safe_names <- function(x) make.unique(gsub("[^A-Za-z0-9_]", "_", x), sep = "_")

shap_results <- list(); t_start <- Sys.time()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))
  b2_file <- sprintf("%s/%s_B2_%s_harmonized.csv", datadir, prefix, resp)
  if (!file.exists(b2_file)) { cat("  ERROR: not found:", b2_file, "\n"); next }
  df_data <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (model_id in names(model_specs)) {
    xvars <- get_predictor_cols(df_data, model_specs[[model_id]], resp)
    df_model <- df_data[, c('SITE_ID', 'YEAR', resp, xvars), drop = FALSE]
    df_model <- df_model[complete.cases(df_model), ]
    sites_test <- unique(df_model$SITE_ID)
    o <- OPTUNA[[resp]]
    cat(sprintf("  %-14s %3d preds: ", model_id, length(xvars)))

    safe <- safe_names(xvars); to_orig <- setNames(xvars, safe)
    Xdf <- as.data.frame(df_model[, xvars, drop = FALSE]); colnames(Xdf) <- safe

    if (fam == "XGB") {
      suppressMessages(library(xgboost))
      pars <- list(objective = "reg:squarederror", nthread = 1, seed = 42,
                   learning_rate = o$learning_rate, max_depth = as.integer(o$max_depth),
                   min_child_weight = o$min_child_weight, subsample = o$subsample,
                   colsample_bytree = o$colsample_bytree, reg_lambda = o$reg_lambda)
      Xmat <- as.matrix(Xdf)
      bst <- tryCatch(xgb.train(params = pars, data = xgb.DMatrix(Xmat, label = df_model[[resp]]),
                                nrounds = as.integer(o$nrounds), verbose = 0), error = function(e) NULL)
      if (is.null(bst)) { cat("model FAILED\n"); next }
      unified <- tryCatch(xgboost.unify(bst, Xdf), error = function(e) NULL)
    } else if (fam == "RF") {
      suppressMessages(library(ranger))
      mt <- max(1L, min(length(xvars), as.integer(round(o$mtry_frac * length(xvars)))))
      rf <- tryCatch(ranger(x = Xdf, y = df_model[[resp]], num.trees = as.integer(o$num_trees),
                            mtry = mt, min.node.size = as.integer(o$min_node_size),
                            sample.fraction = o$sample_fraction, replace = TRUE,
                            num.threads = 1, seed = 42, respect.unordered.factors = "order"),
                     error = function(e) NULL)
      if (is.null(rf)) { cat("model FAILED\n"); next }
      unified <- tryCatch(ranger.unify(rf, Xdf), error = function(e) NULL)
    } else {  # LGB
      suppressMessages(library(lightgbm))
      pars <- list(objective = "regression", metric = "rmse", num_threads = 1, seed = 42, verbosity = -1,
                   learning_rate = o$learning_rate, num_leaves = as.integer(o$num_leaves),
                   min_data_in_leaf = as.integer(o$min_data_in_leaf), feature_fraction = o$feature_fraction,
                   bagging_fraction = o$bagging_fraction, bagging_freq = 1, lambda_l2 = o$lambda_l2)
      Xmat <- as.matrix(Xdf)
      bst <- tryCatch(lgb.train(params = pars, data = lgb.Dataset(Xmat, label = df_model[[resp]]),
                                nrounds = as.integer(o$nrounds), verbose = -1), error = function(e) NULL)
      if (is.null(bst)) { cat("model FAILED\n"); next }
      unified <- tryCatch(lightgbm.unify(bst, Xdf), error = function(e) NULL)
    }
    if (is.null(unified)) { cat("unify FAILED\n"); next }

    fold_shap <- mclapply(sites_test, function(test_site) {
      test_df <- df_model[df_model$SITE_ID == test_site, xvars, drop = FALSE]
      if (nrow(test_df) == 0) return(NULL)
      colnames(test_df) <- safe
      sr <- tryCatch(treeshap(unified, test_df, verbose = FALSE), error = function(e) NULL)
      if (is.null(sr)) return(NULL)
      shap_mat <- as.data.table(sr$shaps)
      mean_abs_shap <- shap_mat[, lapply(.SD, function(x) mean(abs(x), na.rm = TRUE))]
      out <- melt(mean_abs_shap, measure.vars = names(mean_abs_shap),
                  variable.name = "variable", value.name = "mean_abs_shap")
      out[, variable := to_orig[as.character(variable)]]
      if (anyNA(out$variable))
        stop(sprintf("SHAP name mapping lost %d variable name(s) for %s/%s",
                     sum(is.na(out$variable)), model_id, resp))
      out[, `:=`(model = model_id, response = resp, test_site = test_site)]
      out
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
  out_path <- file.path(output_base, if (SMOKE) sprintf("%s_site_shap_24m_SMOKE.csv", fam)
                                      else sprintf("%s_site_shap_M04_M08_24m.csv", fam))
  fwrite(shap_dt, out_path)
  cat(sprintf("OK %s (%d rows)\n", out_path, nrow(shap_dt)))
  cat(sprintf("  Sites: %d | Models: %d | Responses: %s\n",
              uniqueN(shap_dt$test_site), uniqueN(shap_dt$model),
              paste(unique(shap_dt$response), collapse = ", ")))
} else cat("ERROR: No SHAP results collected\n")

cat(sprintf("\nElapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat("LAG2_SHAP_COMPLETE:", output_base, "\n")

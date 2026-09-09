#!/usr/bin/env Rscript
# ============================================================================
# GROUP-LEVEL SIGNED TreeSHAP for the lag2-corrected M4_24m model only
# (XGB or LGB). Mirrors run_draft_signed_shap_{XGBopt,LGBopt}.R exactly (same
# per-site-year signed+abs group aggregation), restricted to the one model
# the coauthor draft actually needs signed values for: M4_24m.
#
#   Rscript run_v10_lag2_signed_shap_M4.R <XGB|LGB> <tc30|tc50>
#
# Writes {output_base}/{FAM}_site_signed_shap_M4_24m.csv - a 24m-only sibling,
# never overwriting the production LOSO signed file.
# ============================================================================
suppressMessages({library(data.table); library(treeshap); library(parallel)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript run_v10_lag2_signed_shap_M4.R <XGB|LGB> <tc30|tc50>")
fam <- args[1]; ds <- args[2]
stopifnot(fam %in% c("XGB","LGB"), ds %in% c("tc30","tc50"))

N_CORES <- as.integer(Sys.getenv("V10_SHAP_CORES", "60"))

if (ds == "tc30") {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_lag2";      prefix <- "v10_lag2"
  output_base <- sprintf("derived_tables/outputs_afterEGU_results/%s_v10_lag2_optuna", fam)
} else {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_tc50_lag2"; prefix <- "v10_tc50_lag2"
  output_base <- sprintf("derived_tables/outputs_afterEGU_results/%s_v10_tc50_lag2_optuna", fam)
}
dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 78), "\n", sep = "")
cat(sprintf("LAG2 M4_24m SIGNED SHAP: %s | %s\n", fam, ds))
cat(strrep("=", 78), "\n\n", sep = "")

OPTUNA <- local({
  cfg <- fread(sprintf("plots/V10/Optuna_lag2/%s_best_configs.csv", ds))
  cfg <- cfg[learner == fam]
  setNames(split(cfg, cfg$response), cfg$response)
})

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

get_predictor_group <- function(var) {
  if (grepl('^lag1_|^lag2_', var)) return('Climate')
  if (grepl('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', var)) return('Traits')
  if (grepl('^(absolute_|relative_|new_|mortality_|disturbance_)', var)) return('Disturbance')
  if (grepl('_lag[12]$|_anom_lag[12]$', var)) return('Memory')
  return('Other')
}
get_predictor_cols <- function(df, response) {
  ac <- colnames(df)
  climate <- c(grep('^lag1_', ac, value = TRUE), grep('^lag2_', ac, value = TRUE))
  traits  <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', ac, value = TRUE)
  dist    <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', ac, value = TRUE)
  unique(c(climate, traits, dist))   # C+T+D = M4
}
safe_names <- function(x) make.unique(gsub("[^A-Za-z0-9_]", "_", x), sep = "_")

shap_results <- list(); t_start <- Sys.time()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))
  b2_file <- sprintf("%s/%s_B2_%s_harmonized.csv", datadir, prefix, resp)
  if (!file.exists(b2_file)) { cat("  ERROR: not found:", b2_file, "\n"); next }
  df_data <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  xvars <- get_predictor_cols(df_data, resp)
  df_model <- df_data[, c('SITE_ID', 'YEAR', resp, xvars), drop = FALSE]
  df_model <- df_model[complete.cases(df_model), ]
  sites_test <- unique(df_model$SITE_ID)
  o <- OPTUNA[[resp]]
  cat(sprintf("  M4_24m         %3d preds: ", length(xvars)))

  safe <- safe_names(xvars); to_orig <- setNames(xvars, safe)
  Xdf <- as.data.frame(df_model[, xvars, drop = FALSE]); colnames(Xdf) <- safe

  if (fam == "XGB") {
    suppressMessages(library(xgboost))
    pars <- list(objective = "reg:squarederror", nthread = 1, seed = 42,
                 learning_rate = o$learning_rate, max_depth = as.integer(o$max_depth),
                 min_child_weight = o$min_child_weight, subsample = o$subsample,
                 colsample_bytree = o$colsample_bytree, reg_lambda = o$reg_lambda)
    bst <- tryCatch(xgb.train(params = pars, data = xgb.DMatrix(as.matrix(Xdf), label = df_model[[resp]]),
                              nrounds = as.integer(o$nrounds), verbose = 0), error = function(e) NULL)
    if (is.null(bst)) { cat("model FAILED\n"); next }
    unified <- tryCatch(xgboost.unify(bst, Xdf), error = function(e) NULL)
  } else {  # LGB
    suppressMessages(library(lightgbm))
    pars <- list(objective = "regression", metric = "rmse", num_threads = 1, seed = 42, verbosity = -1,
                 learning_rate = o$learning_rate, num_leaves = as.integer(o$num_leaves),
                 min_data_in_leaf = as.integer(o$min_data_in_leaf), feature_fraction = o$feature_fraction,
                 bagging_fraction = o$bagging_fraction, bagging_freq = 1, lambda_l2 = o$lambda_l2)
    bst <- tryCatch(lgb.train(params = pars, data = lgb.Dataset(as.matrix(Xdf), label = df_model[[resp]]),
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
    orig_names <- to_orig[names(shap_mat)]
    if (anyNA(orig_names))
      stop(sprintf("SHAP name mapping lost %d variable name(s) for M4_24m/%s", sum(is.na(orig_names)), resp))
    grp <- vapply(orig_names, get_predictor_group, character(1))
    per_row <- rbindlist(lapply(unique(grp), function(g) {
      cols <- names(shap_mat)[grp == g]
      data.table(group = g, signed = rowSums(shap_mat[, ..cols], na.rm = TRUE),
                 absol = rowSums(abs(shap_mat[, ..cols]), na.rm = TRUE))
    }))
    out <- per_row[, .(mean_signed_shap = mean(signed, na.rm = TRUE),
                       mean_abs_shap    = mean(absol,  na.rm = TRUE)), by = group]
    out[, `:=`(model = "M4_24m", response = resp, test_site = test_site)]
    out
  }, mc.cores = N_CORES)

  ok <- Filter(Negate(is.null), fold_shap)
  if (length(ok) > 0) {
    shap_results[[length(shap_results) + 1]] <- rbindlist(ok, fill = TRUE)
    cat(sprintf("OK (%d sites)\n", length(ok)))
  } else cat("no results\n")
}

cat("\nSaving signed SHAP results...\n")
if (length(shap_results) > 0) {
  shap_dt <- rbindlist(shap_results, fill = TRUE)
  out_path <- file.path(output_base, sprintf("%s_site_signed_shap_M4_24m.csv", fam))
  fwrite(shap_dt, out_path)
  cat(sprintf("OK %s (%d rows)\n", out_path, nrow(shap_dt)))
} else cat("ERROR: No SHAP results collected\n")

cat(sprintf("\nElapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat("LAG2_SIGNED_SHAP_COMPLETE:", output_base, "\n")

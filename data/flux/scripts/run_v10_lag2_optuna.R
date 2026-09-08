#!/usr/bin/env Rscript
# ============================================================================
# 24-month models, lag2-enabled disturbance block, Optuna-tuned.
#
# WHY THIS SCRIPT EXISTS: get_predictor_cols() in every other V10 run script
# selects the D block by name prefix with no window condition, so the 24m
# models saw the SAME disturbance columns as the 12m ones. The tc>=30 / tc>=50
# datasets never had disturbance _lag2 at all. This script trains ONLY the
# twelve 24m model structures (M1_24m..M8_anom_24m), on B2 files augmented
# with the two STOCK disturbance metrics' lag2 (absolute_mortality,
# relative_mortality x 5 buffers = 10 cols; see scripts/step_22_build_lag2_
# datasets.R for why only the stock metrics, not all 11 families, are
# included: the others are undefined that far back for ~30 site-years and
# would break the 93/395, 65/287 site counts).
#
# 12m models, and every existing result, are completely untouched - this
# script never reads B1 and never writes into an existing output folder.
#
# Hyperparameters come from a FRESH Optuna retune (plots/V10/Optuna_lag2/),
# scored on M2_24m + M6_raw_24m of THESE lag2 datasets - not reused from the
# original 12m-tuned config - because the predictor count changed.
#
#   Rscript run_v10_lag2_optuna.R <RF|XGB|LGB> <tc30|tc50> <loso|repeated>
# ============================================================================
suppressMessages({library(data.table); library(parallel)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) stop("Usage: Rscript run_v10_lag2_optuna.R <RF|XGB|LGB> <tc30|tc50> <loso|repeated>")
fam <- args[1]; ds <- args[2]; cv_mode <- args[3]
SMOKE <- length(args) >= 4 && args[4] == "smoke"
stopifnot(fam %in% c("RF","XGB","LGB"), ds %in% c("tc30","tc50"), cv_mode %in% c("loso","repeated"))

SEED    <- 42
N_CORES <- as.integer(Sys.getenv("V10_CORES", "40"))
N_REPS  <- as.integer(Sys.getenv("V10_REPS",  "3"))
SUBSAMP <- as.numeric(Sys.getenv("V10_SUBSAMP", "0.8"))

if (ds == "tc30") {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_lag2";      prefix <- "v10_lag2"
} else {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_tc50_lag2"; prefix <- "v10_tc50_lag2"
}

suf <- if (ds == "tc30") "lag2" else "tc50_lag2"
output_base <- if (cv_mode == "loso") {
  sprintf("derived_tables/outputs_afterEGU_results/%s_v10_%s_optuna", fam, suf)
} else {
  sprintf("derived_tables/outputs_afterEGU_results/%s_optuna_repCV_%s", fam, suf)
}
dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 78), "\n", sep = "")
cat(sprintf("LAG2 24m TRAINING: %s | %s | %s%s\n", fam, ds, cv_mode, if (SMOKE) " [SMOKE]" else ""))
cat(strrep("=", 78), "\n\n", sep = "")

OPTUNA <- local({
  cfg <- fread(sprintf("plots/V10/Optuna_lag2/%s_best_configs.csv", ds))
  cfg <- cfg[learner == fam]
  setNames(split(cfg, cfg$response), cfg$response)
})
cat("Optuna (lag2 retune) config per response:\n")
for (r in names(OPTUNA)) cat(sprintf("  %-7s best_cv=%.4f\n", r, OPTUNA[[r]]$best_cv))

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
model_specs <- list(
  M1_24m='C', M2_24m='C+D', M3_24m='C+T', M4_24m='C+T+D',
  M5_raw_24m='C+M_raw', M5_anom_24m='C+M_anom',
  M6_raw_24m='C+D+M_raw', M6_anom_24m='C+D+M_anom',
  M7_raw_24m='C+T+M_raw', M7_anom_24m='C+T+M_anom',
  M8_raw_24m='C+T+D+M_raw', M8_anom_24m='C+T+D+M_anom')
if (SMOKE) { RESPONSE_VARS <- "GPPsat"; model_specs <- model_specs[c("M2_24m","M6_raw_24m")] }

# identical to every other V10 script, window is always '24m' here so the
# lag2 columns (climate ^lag2_, disturbance stock _lag2 suffix) are included
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
  list(pred = unique(p[!is.na(p)]), mem = mem)
}
safe <- function(x) make.unique(gsub("[^A-Za-z0-9_]", "_", x), sep = "_")

fit_predict <- function(tr, te, xv, resp) {
  o <- OPTUNA[[resp]]
  if (fam == "RF") {
    suppressMessages(library(ranger))
    mt <- max(1L, round(o$mtry_frac * length(xv)))
    f <- tryCatch(ranger(x = tr[, ..xv], y = tr[[resp]], num.trees = as.integer(o$num_trees),
                         mtry = mt, min.node.size = as.integer(o$min_node_size),
                         sample.fraction = o$sample_fraction, replace = TRUE,
                         num.threads = 1, seed = SEED, respect.unordered.factors = "order"),
                  error = function(e) NULL)
    if (is.null(f)) return(NULL); return(predict(f, te[, ..xv])$predictions)
  }
  if (fam == "XGB") {
    suppressMessages(library(xgboost))
    p <- list(objective = "reg:squarederror", nthread = 1, seed = SEED,
              learning_rate = o$learning_rate, max_depth = as.integer(o$max_depth),
              min_child_weight = o$min_child_weight, subsample = o$subsample,
              colsample_bytree = o$colsample_bytree, reg_lambda = o$reg_lambda)
    Xtr <- as.matrix(tr[, ..xv]); Xte <- as.matrix(te[, ..xv])
    f <- tryCatch(xgb.train(params = p, data = xgb.DMatrix(Xtr, label = tr[[resp]]),
                            nrounds = as.integer(o$nrounds), verbose = 0), error = function(e) NULL)
    if (is.null(f)) return(NULL); return(as.numeric(predict(f, xgb.DMatrix(Xte))))
  }
  suppressMessages(library(lightgbm))
  p <- list(objective = "regression", metric = "rmse", num_threads = 1, seed = SEED, verbosity = -1,
            learning_rate = o$learning_rate, num_leaves = as.integer(o$num_leaves),
            min_data_in_leaf = as.integer(o$min_data_in_leaf), feature_fraction = o$feature_fraction,
            bagging_fraction = o$bagging_fraction, bagging_freq = 1, lambda_l2 = o$lambda_l2)
  sv <- safe(xv)
  Xtr <- as.matrix(tr[, ..xv]); colnames(Xtr) <- sv
  Xte <- as.matrix(te[, ..xv]); colnames(Xte) <- sv
  f <- tryCatch(lgb.train(params = p, data = lgb.Dataset(Xtr, label = tr[[resp]]),
                          nrounds = as.integer(o$nrounds), verbose = -1), error = function(e) NULL)
  if (is.null(f)) return(NULL); as.numeric(predict(f, Xte))
}

pred_results <- data.table(); metric_results <- data.table(); t0 <- Sys.time()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))
  b2_file <- sprintf("%s/%s_B2_%s_harmonized.csv", datadir, prefix, resp)
  if (!file.exists(b2_file)) { cat(sprintf("  ERROR: not found: %s\n", b2_file)); next }
  df <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (model_id in names(model_specs)) {
    spec <- model_specs[[model_id]]
    sel  <- get_predictor_cols(df, spec, resp)
    xv   <- sel$pred

    dt <- as.data.table(df[, intersect(unique(c('SITE_ID','YEAR',resp,xv)), colnames(df))])
    dt <- dt[!is.na(get(resp))]
    xvo <- intersect(xv, names(dt))
    dt <- dt[complete.cases(dt[, c(resp, xvo), with = FALSE])]
    sites <- sort(unique(dt$SITE_ID))
    tt <- Sys.time()

    if (cv_mode == "loso") {
      folds <- rbindlist(mclapply(sites, function(ts) {
        tr <- dt[SITE_ID != ts]; te <- dt[SITE_ID == ts]
        if (nrow(tr) < 10 || nrow(te) == 0) return(NULL)
        pr <- fit_predict(tr, te, xvo, resp)
        if (is.null(pr)) return(NULL)
        data.table(model = model_id, response = resp, SITE_ID = ts, YEAR = te$YEAR,
                   observed = te[[resp]], predicted = pr)
      }, mc.cores = N_CORES), fill = TRUE)
    } else {
      folds <- rbindlist(mclapply(sites, function(ts) {
        tr_all <- dt[SITE_ID != ts]; te <- dt[SITE_ID == ts]
        if (nrow(tr_all) < 20 || nrow(te) == 0) return(NULL)
        tr_sites <- unique(tr_all$SITE_ID)
        k <- max(5L, floor(SUBSAMP * length(tr_sites)))
        preds <- matrix(NA_real_, nrow = nrow(te), ncol = N_REPS)
        for (r in seq_len(N_REPS)) {
          set.seed(SEED + r * 1000L + which(sites == ts))
          keep <- sample(tr_sites, k)
          pr <- fit_predict(tr_all[SITE_ID %in% keep], te, xvo, resp)
          if (!is.null(pr)) preds[, r] <- pr
        }
        ok <- rowSums(!is.na(preds)) > 0
        if (!any(ok)) return(NULL)
        data.table(model = model_id, response = resp, SITE_ID = ts, YEAR = te$YEAR,
                   observed = te[[resp]], predicted = rowMeans(preds, na.rm = TRUE),
                   pred_sd = apply(preds, 1, sd, na.rm = TRUE),
                   n_reps_used = rowSums(!is.na(preds)))[ok]
      }, mc.cores = N_CORES), fill = TRUE)
    }

    if (nrow(folds) == 0) { cat(sprintf("  %-14s no data\n", model_id)); next }
    pred_results <- rbind(pred_results, folds, fill = TRUE)
    o <- folds$observed; p <- folds$predicted
    mr <- data.table(model = model_id, response = resp, n_predictors = length(xvo),
                      n_pairs = nrow(folds), RMSE = sqrt(mean((p-o)^2)), MAE = mean(abs(p-o)),
                      R2 = 1 - sum((o-p)^2)/sum((o-mean(o))^2))
    if (cv_mode == "repeated") mr <- cbind(mr, data.table(
      mean_pred_sd = mean(folds$pred_sd, na.rm = TRUE), n_reps = N_REPS, subsample = SUBSAMP))
    metric_results <- rbind(metric_results, mr, fill = TRUE)
    cat(sprintf("  %-14s %3d sites, %3d preds  (%4.1fs)\n", model_id, length(sites),
                length(xvo), as.numeric(difftime(Sys.time(), tt, units = "secs"))))
  }
}

if (nrow(pred_results) > 0) {
  fwrite(pred_results, file.path(output_base, sprintf("%s_predictions_LOSO.csv", fam)))
  fwrite(metric_results, file.path(output_base, sprintf("%s_metrics_LOSO.csv", fam)))
  cat(sprintf("\nOK %s  (%d metric rows)\n", output_base, nrow(metric_results)))
  print(as.data.frame(metric_results[, .(R2 = round(mean(R2), 3)),
        by = .(grp = fifelse(grepl("_raw_", model), "raw",
                      fifelse(grepl("_anom_", model), "anom", "none")))]))
}
cat(sprintf("\nElapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("LAG2_TRAINING_COMPLETE:", output_base, "\n")

#!/usr/bin/env Rscript
# ============================================================================
# V10 REPEATED leave-one-site-out cross-validation
#
# Standard LOSO trains each fold on ALL 111 remaining sites. Here, for every
# held-out site we instead train R times on an independent random 80 % subsample
# of the remaining sites, and average the R predictions for that site.
#
#     for each held-out site i:
#        repeat R times: sample 80 % of the other sites -> fit -> predict site i
#        prediction(i) = mean over the R repetitions
#        stability(i)  = sd  over the R repetitions      (new diagnostic)
#
# Why this is worth having:
#   - LOSO gives one prediction from one training set; there is no measure of how
#     sensitive that prediction is to WHICH sites were used. The SD across reps
#     is exactly that, and it is reported alongside the usual metrics.
#   - Each rep trains on ~0.8 x 111 = 89 sites, almost exactly the ~90 sites the
#     grouped 5-fold CV tuning used. So configurations selected by that tuning
#     should transfer BETTER here than they did to full LOSO - a direct test of
#     the CV->LOSO attenuation documented for the tuned variants.
#
# Every variant uses the same hyperparameters as its LOSO counterpart, so the
# ONLY thing that changes is the resampling structure.
#
#   Rscript run_v10_repeatedCV.R <variant> <dataset_type> [smoke]
#     variant: RF_base RF_exp02 RF_optuna XGB_base XGB_tuned XGB_optuna
#              LGB_base LGB_tuned LGB_optuna RF_exp01
# ============================================================================
suppressMessages({library(data.table); library(parallel)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args    <- commandArgs(trailingOnly = TRUE)
variant <- args[1]; dataset_type <- args[2]
SMOKE   <- length(args) >= 3 && args[3] == "smoke"

SEED    <- 42
N_REPS  <- as.integer(Sys.getenv("V10_REPS",  "3"))     # repetitions per held-out site
SUBSAMP <- as.numeric(Sys.getenv("V10_SUBSAMP", "0.8")) # fraction of remaining SITES
N_CORES <- as.integer(Sys.getenv("V10_CORES", "40"))

fam <- sub("_.*$", "", variant)                          # RF | XGB | LGB

if (dataset_type == "filtered") {
  datadir <- "derived_tables/outputs_afterEGU_results/v10"; prefix <- "v10"
} else if (dataset_type == "tc50") {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_tc50"; prefix <- "v10_tc50"
} else {
  datadir <- "derived_tables/outputs_afterEGU_results/v10_all_sites"; prefix <- "v10_all"
}
output_base <- file.path("derived_tables/outputs_afterEGU_results",
                         sprintf("%s_repCV%s", variant,
                                 if (dataset_type == "all_sites") "_all_sites"
                                 else if (dataset_type == "tc50") "_tc50" else ""))
dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

cat("\n", strrep("=", 78), "\n", sep = "")
cat(sprintf("V10 REPEATED CV: %s | %s | %d reps x %.0f%% of sites\n",
            variant, toupper(dataset_type), N_REPS, 100 * SUBSAMP))
cat(strrep("=", 78), "\n\n", sep = "")

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
model_specs <- list(
  M1_12m='C', M1_24m='C', M2_12m='C+D', M2_24m='C+D', M3_12m='C+T', M3_24m='C+T',
  M4_12m='C+T+D', M4_24m='C+T+D',
  M5_raw_12m='C+M_raw', M5_raw_24m='C+M_raw', M5_anom_12m='C+M_anom', M5_anom_24m='C+M_anom',
  M6_raw_12m='C+D+M_raw', M6_raw_24m='C+D+M_raw', M6_anom_12m='C+D+M_anom', M6_anom_24m='C+D+M_anom',
  M7_raw_12m='C+T+M_raw', M7_raw_24m='C+T+M_raw', M7_anom_12m='C+T+M_anom', M7_anom_24m='C+T+M_anom',
  M8_raw_12m='C+T+D+M_raw', M8_raw_24m='C+T+D+M_raw',
  M8_anom_12m='C+T+D+M_anom', M8_anom_24m='C+T+D+M_anom')
if (SMOKE) { RESPONSE_VARS <- "GPPsat"; model_specs <- model_specs[c("M2_12m","M6_raw_12m")] }

get_predictor_cols <- function(df, spec, window, response) {
  ac <- colnames(df)
  climate <- if (window == '12m') grep('^lag1_', ac, value = TRUE)
             else c(grep('^lag1_', ac, value = TRUE), grep('^lag2_', ac, value = TRUE))
  traits <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', ac, value = TRUE)
  dist   <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', ac, value = TRUE)
  mem <- c()
  if (grepl('_raw$',  spec)) mem <- grep(if (window=='12m') paste0('^',response,'_lag1$')
                                         else paste0('^',response,'_lag[12]$'), ac, value = TRUE)
  if (grepl('_anom$', spec)) mem <- grep(if (window=='12m') paste0('^',response,'_anom_lag1$')
                                         else paste0('^',response,'_anom_lag[12]$'), ac, value = TRUE)
  p <- c()
  if (grepl('C',spec)) p <- c(p, climate); if (grepl('T',spec)) p <- c(p, traits)
  if (grepl('D',spec)) p <- c(p, dist);    if (grepl('M',spec)) p <- c(p, mem)
  list(pred = unique(p[!is.na(p)]), mem = mem)
}
safe <- function(x) make.unique(gsub("[^A-Za-z0-9_]", "_", x), sep = "_")

# ── hyperparameters: identical to this variant's LOSO counterpart ─────────────
CFG <- new.env()
if (grepl("_optuna$", variant)) {
  o <- fread("plots/V10/Optuna/optuna_best_configs.csv")[learner == fam]
  CFG$mode <- "optuna"; CFG$tab <- setNames(split(o, o$response), o$response)
} else if (variant == "RF_exp01") {
  b <- fread(sprintf("plots/V10/RF_tuning/exp01_hyperparams/tuning_best_%s.csv", dataset_type))
  CFG$mode <- "exp01"; CFG$tab <- setNames(split(b, b$response), b$response)
} else if (variant == "XGB_tuned") {
  R <- fread("plots/V10/XGBoost/regularisation_sweep_xgb_combined.csv")
  R[, rk := frank(-cv_r2), by = .(response, model)]
  b <- R[, .(mr = mean(rk)), by = .(response, max_depth, min_child_weight)][, .SD[which.min(mr)], by = response]
  CFG$mode <- "xgbgrid"; CFG$tab <- setNames(split(b, b$response), b$response)
} else if (variant == "LGB_tuned") {
  R <- fread("plots/V10/LightGBM/regularisation_sweep_ext.csv")
  R[, rk := frank(-cv_r2), by = .(response, model)]
  b <- R[, .(mr = mean(rk)), by = .(response, min_data_in_leaf, num_leaves)][, .SD[which.min(mr)], by = response]
  CFG$mode <- "lgbgrid"; CFG$tab <- setNames(split(b, b$response), b$response)
} else CFG$mode <- "base"

fit_predict <- function(tr, te, xv, resp, force_split = NULL) {
  o <- if (!is.null(CFG$tab)) CFG$tab[[resp]] else NULL
  if (fam == "RF") {
    suppressMessages(library(ranger))
    mt <- if (CFG$mode == "optuna") max(1L, round(o$mtry_frac * length(xv)))
          else if (CFG$mode == "exp01") max(1L, round(o$mtry_frac * length(xv)))
          else floor(sqrt(length(xv)))
    nt <- if (CFG$mode == "optuna") as.integer(o$num_trees)
          else if (CFG$mode == "exp01") as.integer(o$ntrees) else 500L
    mn <- if (CFG$mode == "optuna") as.integer(o$min_node_size)
          else if (CFG$mode == "exp01") as.integer(o$min_node) else 5L
    sf <- if (CFG$mode == "optuna") o$sample_fraction else 1
    f <- tryCatch(ranger(x = tr[, ..xv], y = tr[[resp]], num.trees = nt, mtry = mt,
                         min.node.size = mn, sample.fraction = sf, replace = TRUE,
                         num.threads = 1, seed = SEED, respect.unordered.factors = "order",
                         always.split.variables = force_split),
                  error = function(e) NULL)
    if (is.null(f)) return(NULL); return(predict(f, te[, ..xv])$predictions)
  }
  if (fam == "XGB") {
    suppressMessages(library(xgboost))
    p <- list(objective="reg:squarederror", learning_rate=0.05, max_depth=6L,
              min_child_weight=1, subsample=0.8, colsample_bytree=0.8, nthread=1, seed=SEED)
    nr <- 500L
    if (CFG$mode == "optuna") { p$learning_rate<-o$learning_rate; p$max_depth<-as.integer(o$max_depth)
      p$min_child_weight<-o$min_child_weight; p$subsample<-o$subsample
      p$colsample_bytree<-o$colsample_bytree; p$reg_lambda<-o$reg_lambda; nr<-as.integer(o$nrounds) }
    if (CFG$mode == "xgbgrid") { p$max_depth<-as.integer(o$max_depth); p$min_child_weight<-o$min_child_weight }
    Xtr <- as.matrix(tr[, ..xv]); Xte <- as.matrix(te[, ..xv])
    f <- tryCatch(xgb.train(params=p, data=xgb.DMatrix(Xtr, label=tr[[resp]]),
                            nrounds=nr, verbose=0), error=function(e) NULL)
    if (is.null(f)) return(NULL); return(as.numeric(predict(f, xgb.DMatrix(Xte))))
  }
  suppressMessages(library(lightgbm))
  p <- list(objective="regression", metric="rmse", learning_rate=0.05, num_leaves=31L,
            min_data_in_leaf=5L, feature_fraction=0.8, bagging_fraction=0.8, bagging_freq=1,
            num_threads=1, seed=SEED, verbosity=-1)
  nr <- 500L
  if (CFG$mode == "optuna") { p$learning_rate<-o$learning_rate; p$num_leaves<-as.integer(o$num_leaves)
    p$min_data_in_leaf<-as.integer(o$min_data_in_leaf); p$feature_fraction<-o$feature_fraction
    p$bagging_fraction<-o$bagging_fraction; p$lambda_l2<-o$lambda_l2; nr<-as.integer(o$nrounds) }
  if (CFG$mode == "lgbgrid") { p$num_leaves<-as.integer(o$num_leaves)
    p$min_data_in_leaf<-as.integer(o$min_data_in_leaf) }
  sv <- safe(xv)
  Xtr <- as.matrix(tr[, ..xv]); colnames(Xtr) <- sv
  Xte <- as.matrix(te[, ..xv]); colnames(Xte) <- sv
  f <- tryCatch(lgb.train(params=p, data=lgb.Dataset(Xtr, label=tr[[resp]]),
                          nrounds=nr, verbose=-1), error=function(e) NULL)
  if (is.null(f)) return(NULL)
  as.numeric(predict(f, Xte))
}

pred_results <- data.table(); metric_results <- data.table(); t0 <- Sys.time()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))
  b1 <- as.data.frame(fread(sprintf("%s/%s_B1_%s_harmonized.csv", datadir, prefix, resp)))
  b2 <- as.data.frame(fread(sprintf("%s/%s_B2_%s_harmonized.csv", datadir, prefix, resp)))

  for (model_id in names(model_specs)) {
    spec   <- model_specs[[model_id]]
    window <- if (grepl('12m$', model_id)) '12m' else '24m'
    df     <- if (window == '12m') b1 else b2
    sel    <- get_predictor_cols(df, spec, window, resp)
    xv     <- sel$pred
    force_split <- if (variant == "RF_exp02" && grepl('_raw$', spec)) sel$mem else NULL

    dt <- as.data.table(df[, intersect(unique(c('SITE_ID','YEAR',resp,xv)), colnames(df))])
    dt <- dt[!is.na(get(resp))]
    xvo <- intersect(xv, names(dt))
    dt <- dt[complete.cases(dt[, c(resp, xvo), with = FALSE])]
    sites <- sort(unique(dt$SITE_ID))
    tt <- Sys.time()

    folds <- rbindlist(mclapply(sites, function(ts) {
      tr_all <- dt[SITE_ID != ts]; te <- dt[SITE_ID == ts]
      if (nrow(tr_all) < 20 || nrow(te) == 0) return(NULL)
      tr_sites <- unique(tr_all$SITE_ID)
      k <- max(5L, floor(SUBSAMP * length(tr_sites)))
      preds <- matrix(NA_real_, nrow = nrow(te), ncol = N_REPS)
      for (r in seq_len(N_REPS)) {
        # deterministic per (site, rep) so the whole run is reproducible
        set.seed(SEED + r * 1000L + which(sites == ts))
        keep <- sample(tr_sites, k)
        pr <- fit_predict(tr_all[SITE_ID %in% keep], te, xvo, resp, force_split)
        if (!is.null(pr)) preds[, r] <- pr
      }
      ok <- rowSums(!is.na(preds)) > 0
      if (!any(ok)) return(NULL)
      data.table(model = model_id, response = resp, SITE_ID = ts, YEAR = te$YEAR,
                 observed = te[[resp]],
                 predicted   = rowMeans(preds, na.rm = TRUE),
                 pred_sd     = apply(preds, 1, sd, na.rm = TRUE),
                 n_reps_used = rowSums(!is.na(preds)))[ok]
    }, mc.cores = N_CORES), fill = TRUE)

    if (nrow(folds) == 0) { cat(sprintf("  %-14s no data\n", model_id)); next }
    pred_results <- rbind(pred_results, folds)
    o <- folds$observed; p <- folds$predicted
    metric_results <- rbind(metric_results, data.table(
      model = model_id, response = resp, n_predictors = length(xvo), n_pairs = nrow(folds),
      RMSE = sqrt(mean((p - o)^2)), MAE = mean(abs(p - o)),
      R2 = 1 - sum((o - p)^2) / sum((o - mean(o))^2),
      mean_pred_sd = mean(folds$pred_sd, na.rm = TRUE),
      n_reps = N_REPS, subsample = SUBSAMP))
    cat(sprintf("  %-14s %3d sites, %3d preds  (%4.1fs)\n", model_id, length(sites),
                length(xvo), as.numeric(difftime(Sys.time(), tt, units = "secs"))))
  }
}

if (nrow(pred_results) > 0) {
  fwrite(pred_results, file.path(output_base, sprintf("%s_predictions_LOSO.csv", fam)))
  fwrite(metric_results, file.path(output_base, sprintf("%s_metrics_LOSO.csv", fam)))
  cat(sprintf("\nOK %s  (%d metric rows)\n", output_base, nrow(metric_results)))
  cat("\nMean R2 by memory group:\n")
  print(as.data.frame(metric_results[, .(R2 = round(mean(R2), 3),
        mean_pred_sd = round(mean(mean_pred_sd), 4)),
        by = .(grp = fifelse(grepl("_raw_", model), "raw",
                      fifelse(grepl("_anom_", model), "anom", "none")))]))
}
cat(sprintf("\nElapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("V10 REPEATED CV COMPLETE\n")

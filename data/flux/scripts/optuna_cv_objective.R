#!/usr/bin/env Rscript
# ============================================================================
# Grouped 5-fold CV objective, called once per Optuna trial.
#
# Optuna (Python) is used only as the SAMPLER. Every trial is evaluated by this
# script, i.e. by the same ranger / xgboost / lightgbm R code that trains the
# reported models. That avoids any cross-language parameter-transfer problem and
# keeps the objective identical to the exhaustive-grid sweeps:
#   - folds = disjoint groups of SITES (seed 42), so no site is in both train and
#     validation of a fold, and selection never touches the reported LOSO
#   - evaluated on M2_12m (C+D, no memory, weak diffuse signal) and
#     M6_raw_12m (C+D+M raw, one dominant predictor), then averaged, so a single
#     configuration has to serve both regimes
#
# Usage:
#   Rscript optuna_cv_objective.R <learner> <response> <params-json>
# Prints a single number to stdout: the mean grouped-CV RMSE (lower = better),
# or "NA" if the fit failed.
# ============================================================================
suppressMessages({library(data.table); library(jsonlite)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args    <- commandArgs(trailingOnly = TRUE)
learner <- args[1]; resp <- args[2]; pj <- fromJSON(args[3])

SEED <- 42; NFOLD <- 5
datadir <- "derived_tables/outputs_afterEGU_results/v10_all_sites"; prefix <- "v10_all"
MODELS  <- list(M2_12m = "C+D", M6_raw_12m = "C+D+M_raw")

sel_cols <- function(df, spec, resp) {
  ac <- colnames(df)
  climate <- grep('^lag1_', ac, value = TRUE)
  dist <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', ac, value = TRUE)
  mem  <- if (grepl('_raw$', spec)) grep(paste0('^', resp, '_lag1$'), ac, value = TRUE) else c()
  p <- c()
  if (grepl('C', spec)) p <- c(p, climate)
  if (grepl('D', spec)) p <- c(p, dist)
  if (grepl('M', spec)) p <- c(p, mem)
  unique(p[!is.na(p)])
}
safe <- function(x) make.unique(gsub("[^A-Za-z0-9_]", "_", x), sep = "_")

df <- as.data.frame(fread(sprintf("%s/%s_B1_%s_harmonized.csv", datadir, prefix, resp)))

rmses <- c()
for (mid in names(MODELS)) {
  xv <- sel_cols(df, MODELS[[mid]], resp)
  d  <- df[, c("SITE_ID", resp, xv)]; d <- d[complete.cases(d), ]
  sites <- unique(d$SITE_ID)
  set.seed(SEED); fold_of <- setNames(sample(rep_len(1:NFOLD, length(sites))), sites)
  y <- d[[resp]]
  pred <- rep(NA_real_, nrow(d))

  for (k in 1:NFOLD) {
    te <- fold_of[as.character(d$SITE_ID)] == k
    if (sum(te) == 0 || sum(!te) < 20) next
    ok <- TRUE
    if (learner == "RF") {
      suppressMessages(library(ranger))
      p <- max(1L, min(length(xv), as.integer(round(pj$mtry_frac * length(xv)))))
      fit <- tryCatch(ranger(x = d[!te, xv, drop = FALSE], y = y[!te],
                             num.trees = as.integer(pj$num_trees), mtry = p,
                             min.node.size = as.integer(pj$min_node_size),
                             sample.fraction = pj$sample_fraction,
                             replace = TRUE, num.threads = 1, seed = SEED,
                             respect.unordered.factors = "order"),
                      error = function(e) NULL)
      if (is.null(fit)) { ok <- FALSE } else
        pred[te] <- predict(fit, d[te, xv, drop = FALSE])$predictions
    } else if (learner == "XGB") {
      suppressMessages(library(xgboost))
      X <- as.matrix(d[, xv])
      par <- list(objective = "reg:squarederror", learning_rate = pj$learning_rate,
                  max_depth = as.integer(pj$max_depth),
                  min_child_weight = pj$min_child_weight,
                  subsample = pj$subsample, colsample_bytree = pj$colsample_bytree,
                  reg_lambda = pj$reg_lambda, nthread = 1, seed = SEED)
      fit <- tryCatch(xgb.train(params = par,
                                data = xgb.DMatrix(X[!te, , drop = FALSE], label = y[!te]),
                                nrounds = as.integer(pj$nrounds), verbose = 0),
                      error = function(e) NULL)
      if (is.null(fit)) { ok <- FALSE } else
        pred[te] <- as.numeric(predict(fit, xgb.DMatrix(X[te, , drop = FALSE])))
    } else if (learner == "LGB") {
      suppressMessages(library(lightgbm))
      X <- as.matrix(d[, xv]); colnames(X) <- safe(xv)   # LightGBM rewrites names
      par <- list(objective = "regression", metric = "rmse",
                  learning_rate = pj$learning_rate,
                  num_leaves = as.integer(pj$num_leaves),
                  min_data_in_leaf = as.integer(pj$min_data_in_leaf),
                  feature_fraction = pj$feature_fraction,
                  bagging_fraction = pj$bagging_fraction, bagging_freq = 1,
                  lambda_l2 = pj$lambda_l2,
                  num_threads = 1, seed = SEED, verbosity = -1)
      fit <- tryCatch(lgb.train(params = par,
                                data = lgb.Dataset(X[!te, , drop = FALSE], label = y[!te]),
                                nrounds = as.integer(pj$nrounds), verbose = -1),
                      error = function(e) NULL)
      if (is.null(fit)) { ok <- FALSE } else
        pred[te] <- as.numeric(predict(fit, X[te, , drop = FALSE]))
    } else stop("unknown learner")
    if (!ok) { cat("NA\n"); quit(status = 0) }
  }
  good <- !is.na(pred)
  if (!any(good)) { cat("NA\n"); quit(status = 0) }
  # scale-free per model so the two regimes contribute comparably to the mean
  rmses <- c(rmses, sqrt(mean((pred[good] - y[good])^2)) / sd(y[good]))
}

cat(sprintf("%.8f\n", mean(rmses)))

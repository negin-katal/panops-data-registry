#!/usr/bin/env Rscript
# ============================================================================
# XGBoost complexity sweep — exhaustive grid search over GROUPED 5-FOLD CV
#
# Same protocol as scripts/lgb_tune_regularisation.R and exp01, so the three
# tuned learners are directly comparable:
#   - folds = disjoint groups of SITES, so no site is in both train and
#     validation of a fold, and selection never touches the reported LOSO
#   - exhaustive grid (not Bayesian/TPE) so the whole response surface is
#     visible and the result is fully reproducible
#
# Swept knobs mirror the LightGBM sweep's two complexity controls:
#   max_depth        <-> num_leaves        (capacity of each tree)
#   min_child_weight <-> min_data_in_leaf  (how small a leaf may get)
# Values BELOW the shipped max_depth=6 are included deliberately: the LightGBM
# sweep found that at n ~ 414 site-years less capacity is better, and both
# earlier sweeps initially put their optimum on a grid boundary.
#
# Tested on two models spanning both regimes:
#   M2_12m      (C+D, no memory)     - weak diffuse signal
#   M6_raw_12m  (C+D+M raw)          - one dominant predictor
# across all five responses.
#
# Output: plots/V10/XGBoost/regularisation_sweep_xgb_ext.csv
# ============================================================================
library(data.table); library(xgboost); library(parallel)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

SEED <- 42; NFOLD <- 5; N_CORES <- as.integer(Sys.getenv("V10_CORES", "40"))
NROUNDS <- 500                      # held fixed, as in the shipped run
OUT <- "plots/V10/XGBoost"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

datadir <- "derived_tables/outputs_afterEGU_results/v10_all_sites"; prefix <- "v10_all"
MODELS    <- list(M2_12m = "C+D", M6_raw_12m = "C+D+M_raw")
RESPONSES <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

GRID <- CJ(max_depth        = c(1, 2, 3, 4),
           min_child_weight = c(1, 3, 5, 10),
           sorted = FALSE)

sel_cols <- function(df, spec, window, resp) {
  ac <- colnames(df)
  climate <- if (window == '12m') grep('^lag1_', ac, value = TRUE)
             else c(grep('^lag1_', ac, value = TRUE), grep('^lag2_', ac, value = TRUE))
  dist <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', ac, value = TRUE)
  mem  <- if (grepl('_raw$', spec)) grep(paste0('^', resp, '_lag1$'), ac, value = TRUE) else c()
  p <- c()
  if (grepl('C', spec)) p <- c(p, climate)
  if (grepl('D', spec)) p <- c(p, dist)
  if (grepl('M', spec)) p <- c(p, mem)
  unique(p[!is.na(p)])
}

res <- list()
for (resp in RESPONSES) {
  df <- as.data.frame(fread(sprintf("%s/%s_B1_%s_harmonized.csv", datadir, prefix, resp)))
  for (mid in names(MODELS)) {
    xv <- sel_cols(df, MODELS[[mid]], "12m", resp)
    d  <- df[, c("SITE_ID", resp, xv)]; d <- d[complete.cases(d), ]
    sites <- unique(d$SITE_ID)
    set.seed(SEED); fold_of <- setNames(sample(rep_len(1:NFOLD, length(sites))), sites)
    X <- as.matrix(d[, xv]); y <- d[[resp]]

    out <- rbindlist(mclapply(seq_len(nrow(GRID)), function(i) {
      p <- list(objective = "reg:squarederror", learning_rate = 0.05,
                max_depth = GRID$max_depth[i], min_child_weight = GRID$min_child_weight[i],
                subsample = 0.8, colsample_bytree = 0.8, nthread = 1, seed = SEED)
      pred <- rep(NA_real_, nrow(d))
      for (k in 1:NFOLD) {
        te <- fold_of[as.character(d$SITE_ID)] == k
        if (sum(te) == 0 || sum(!te) < 20) next
        bst <- tryCatch(xgb.train(params = p,
                                  data = xgb.DMatrix(X[!te, , drop = FALSE], label = y[!te]),
                                  nrounds = NROUNDS, verbose = 0),
                        error = function(e) NULL)
        if (is.null(bst)) next
        pred[te] <- as.numeric(predict(bst, xgb.DMatrix(X[te, , drop = FALSE])))
      }
      ok <- !is.na(pred)
      if (!any(ok)) return(NULL)
      data.table(response = resp, model = mid,
                 max_depth = GRID$max_depth[i], min_child_weight = GRID$min_child_weight[i],
                 cv_rmse = sqrt(mean((pred[ok] - y[ok])^2)),
                 cv_r2   = 1 - sum((y[ok] - pred[ok])^2) / sum((y[ok] - mean(y[ok]))^2))
    }, mc.cores = N_CORES), fill = TRUE)

    res[[length(res) + 1]] <- out
    cat(sprintf("%s / %-12s done\n", resp, mid))
  }
}

R <- rbindlist(res, fill = TRUE)
fwrite(R, file.path(OUT, "regularisation_sweep_xgb_ext.csv"))

cat("\n=== grouped-5-fold CV R2 (higher better); shipped setting = max_depth 6 / min_child_weight 1 ===\n")
for (rp in RESPONSES) for (mid in names(MODELS)) {
  cat(sprintf("\n-- %s / %s --\n", rp, mid))
  print(dcast(R[response == rp & model == mid], min_child_weight ~ max_depth,
              value.var = "cv_r2")[, lapply(.SD, function(z) if (is.numeric(z)) round(z, 3) else z)])
}

cat("\n=== best per response (mean rank over the two model types) ===\n")
R[, rk := frank(-cv_r2), by = .(response, model)]
pick <- R[, .(mean_rank = mean(rk)), by = .(response, max_depth, min_child_weight)][
          , .SD[which.min(mean_rank)], by = response]
print(pick[, .(response, max_depth, min_child_weight, mean_rank = round(mean_rank, 1))])

cat("\n=== gain vs shipped (max_depth 6, min_child_weight 1) ===\n")
cur <- R[max_depth == 6 & min_child_weight == 1, .(response, model, current = cv_r2)]
tun <- merge(R, pick[, .(response, max_depth, min_child_weight)],
             by = c("response", "max_depth", "min_child_weight"))[, .(response, model, tuned = cv_r2)]
g <- merge(cur, tun, by = c("response", "model"))[, gain := tuned - current]
print(g[order(model, response), .(response, model, current = round(current, 3),
                                  tuned = round(tuned, 3), gain = round(gain, 3))])
cat(sprintf("\nmean gain: M2_12m %+.3f | M6_raw_12m %+.3f\n",
            g[model == "M2_12m", mean(gain)], g[model == "M6_raw_12m", mean(gain)]))

cat("\n=== boundary check: how often does each max_depth win? ===\n")
print(R[, .SD[which.max(cv_r2)], by = .(response, model)][, .N, by = max_depth][order(max_depth)])

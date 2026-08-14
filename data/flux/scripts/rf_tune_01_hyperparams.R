#!/usr/bin/env Rscript
# ============================================================================
# exp01: RF hyperparameter tuning (mtry, min.node.size, num.trees)
# Method: grouped 5-fold CV (folds = site groups) — NO leakage into LOSO report.
# Tuned on the full model M8_raw_24m (C+T+D+M) per response; mtry as a FRACTION
# of predictors so the winner generalises across the 24 model configs.
# Output: per response, CV-RMSE for every grid combo + best config vs defaults.
# ============================================================================

library(data.table)
library(ranger)
library(parallel)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript rf_tune_01_hyperparams.R <filtered|all_sites>")
dataset_type <- args[1]

SEED <- 42
N_CORES <- 60
K <- 5  # grouped folds for tuning

# grid (baseline = ranger defaults: mtry=floor(sqrt(p)) ~5% of p, min.node.size=5, num.trees=500)
GRID <- CJ(mtry_frac = c(0.20, 0.33, 0.50, 0.70, 1.00),
           min_node  = c(3, 5, 10),
           ntrees    = c(500, 1000))

if (dataset_type == "filtered") {
  b2 <- "derived_tables/outputs_afterEGU_results/v10/v10_B2_%s_harmonized.csv"
  out_dir <- "plots/V10/RF_tuning/exp01_hyperparams"
} else if (dataset_type == "tc50") {
  b2 <- "derived_tables/outputs_afterEGU_results/v10_tc50/v10_tc50_B2_%s_harmonized.csv"
  out_dir <- "plots/V10/RF_tuning/exp01_hyperparams"
} else if (dataset_type == "all_sites") {
  b2 <- "derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B2_%s_harmonized.csv"
  out_dir <- "plots/V10/RF_tuning/exp01_hyperparams"
} else stop("bad dataset")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

RESP <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

# full-model (M8_raw_24m) predictor selection
predictors_M8raw24 <- function(cols, resp) {
  climate <- grep("^lag1_|^lag2_", cols, value = TRUE)
  traits  <- grep("^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)", cols, value = TRUE)
  dist    <- grep("^(absolute_|relative_|new_|mortality_|disturbance_)", cols, value = TRUE)
  mem     <- grep(paste0("^", resp, "_lag[12]$"), cols, value = TRUE)
  unique(c(climate, traits, dist, mem))
}

rmse <- function(a, b) sqrt(mean((a - b)^2))

results <- list()
for (resp in RESP) {
  df <- as.data.frame(fread(sprintf(b2, resp)))
  xv <- predictors_M8raw24(colnames(df), resp)
  d  <- as.data.table(df[, c("SITE_ID", resp, xv)])
  d  <- d[complete.cases(d)]
  p  <- length(xv)

  # assign sites to K folds
  set.seed(SEED)
  sites <- unique(d$SITE_ID)
  fold_of <- setNames(sample(rep(1:K, length.out = length(sites))), sites)
  d[, fold := fold_of[SITE_ID]]

  # evaluate one grid row via grouped K-fold pooled RMSE
  eval_combo <- function(i) {
    g <- GRID[i]
    mt <- max(1, floor(g$mtry_frac * p))
    preds <- rep(NA_real_, nrow(d)); obs <- d[[resp]]
    for (k in 1:K) {
      tr <- d[fold != k]; te <- d[fold == k]
      rf <- ranger(x = tr[, ..xv], y = tr[[resp]], num.trees = g$ntrees,
                   mtry = mt, min.node.size = g$min_node, seed = SEED,
                   num.threads = 1, respect.unordered.factors = "order")
      preds[d$fold == k] <- predict(rf, te[, ..xv])$predictions
    }
    data.table(response = resp, mtry_frac = g$mtry_frac, mtry = mt,
               min_node = g$min_node, ntrees = g$ntrees,
               cv_rmse = rmse(obs, preds), n_pred = p)
  }
  res <- rbindlist(mclapply(seq_len(nrow(GRID)), eval_combo, mc.cores = N_CORES))
  results[[resp]] <- res
  best <- res[which.min(cv_rmse)]
  # default combo rmse (mtry≈0.33, node 5, trees 500)
  defr <- res[abs(mtry_frac - 0.33) < 1e-9 & min_node == 5 & ntrees == 500, cv_rmse]
  cat(sprintf("%-7s p=%3d | best: mtry_frac=%.2f node=%d trees=%d  CV_RMSE=%.4f  (default=%.4f, %+.1f%%)\n",
              resp, best$n_pred, best$mtry_frac, best$min_node, best$ntrees, best$cv_rmse,
              defr, 100 * (best$cv_rmse - defr) / defr))
}

allres <- rbindlist(results)
fwrite(allres, file.path(out_dir, sprintf("tuning_grid_%s.csv", dataset_type)))
# best per response
best_tab <- allres[, .SD[which.min(cv_rmse)], by = response]
fwrite(best_tab, file.path(out_dir, sprintf("tuning_best_%s.csv", dataset_type)))
cat("\nSaved:", file.path(out_dir, sprintf("tuning_best_%s.csv", dataset_type)), "\n")

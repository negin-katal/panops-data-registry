#!/usr/bin/env Rscript
# ============================================================================
# exp01: LOSO re-run with TUNED hyperparameters (from tuning_best_<ds>.csv).
# Baseline datasets untouched (read-only). Outputs to *_tuned/ so baseline
# RF_v10 / RF_v10_all_sites stay intact for comparison.
# Per-response tuned config; mtry = round(mtry_frac * n_predictors) per model.
# LOSO folds parallelised with mclapply(60). Predictions + metrics only.
# ============================================================================

library(data.table)
library(ranger)
library(parallel)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript run_v10_RF_ranger_tuned.R <filtered|all_sites>")
dataset_type <- args[1]
SEED <- 42; N_CORES <- as.integer(Sys.getenv('V10_CORES', '70'))

if (dataset_type == "filtered") {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10_optuna"
  datadir <- "derived_tables/outputs_afterEGU_results/v10"; prefix <- "v10"
} else if (dataset_type == "tc50") {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10_tc50_optuna"
  datadir <- "derived_tables/outputs_afterEGU_results/v10_tc50"; prefix <- "v10_tc50"
} else if (dataset_type == "all_sites") {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites_optuna"
  datadir <- "derived_tables/outputs_afterEGU_results/v10_all_sites"; prefix <- "v10_all"
} else stop("bad dataset")
dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

# --- per-response hyperparameters from OPTUNA (TPE) --------------------------
# Optuna was the SAMPLER only; every trial was scored by the same grouped 5-fold
# CV objective (disjoint site groups, seed 42) evaluated by this same ranger
# code, so nothing leaked into the reported LOSO and no cross-language parameter
# transfer was involved. Search space was wider than the exhaustive grid:
# mtry_frac, num.trees, min.node.size AND sample.fraction (4 dims).
best <- fread("plots/V10/Optuna/optuna_best_configs.csv")[learner == "RF"]
setnames(best, c("min_node_size", "num_trees"), c("min_node", "ntrees"))
setkey(best, response)

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
model_specs <- list(
  M1_12m='C', M1_24m='C', M2_12m='C+D', M2_24m='C+D', M3_12m='C+T', M3_24m='C+T',
  M4_12m='C+T+D', M4_24m='C+T+D',
  M5_raw_12m='C+M_raw', M5_raw_24m='C+M_raw', M5_anom_12m='C+M_anom', M5_anom_24m='C+M_anom',
  M6_raw_12m='C+D+M_raw', M6_raw_24m='C+D+M_raw', M6_anom_12m='C+D+M_anom', M6_anom_24m='C+D+M_anom',
  M7_raw_12m='C+T+M_raw', M7_raw_24m='C+T+M_raw', M7_anom_12m='C+T+M_anom', M7_anom_24m='C+T+M_anom',
  M8_raw_12m='C+T+D+M_raw', M8_raw_24m='C+T+D+M_raw', M8_anom_12m='C+T+D+M_anom', M8_anom_24m='C+T+D+M_anom'
)

get_predictor_cols <- function(df, model_type, window, response) {
  ac <- colnames(df)
  climate <- if (window == '12m') grep('^lag1_', ac, value=TRUE) else grep('^lag1_|^lag2_', ac, value=TRUE)
  traits  <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', ac, value=TRUE)
  dist    <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', ac, value=TRUE)
  mem <- c()
  if (grepl('_raw$', model_type))  mem <- grep(if (window=='12m') paste0('^',response,'_lag1$') else paste0('^',response,'_lag[12]$'), ac, value=TRUE)
  if (grepl('_anom$', model_type)) mem <- grep(if (window=='12m') paste0('^',response,'_anom_lag1$') else paste0('^',response,'_anom_lag[12]$'), ac, value=TRUE)
  p <- c()
  if (grepl('C', model_type)) p <- c(p, climate)
  if (grepl('T', model_type)) p <- c(p, traits)
  if (grepl('D', model_type)) p <- c(p, dist)
  if (grepl('M', model_type)) p <- c(p, mem)
  unique(p[!is.na(p)])
}

pred_results <- data.table(); metric_results <- data.table()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s (mtry_frac=%.2f node=%d trees=%d samp=%.2f):\n",
              resp, best[resp]$mtry_frac, best[resp]$min_node, best[resp]$ntrees,
              best[resp]$sample_fraction))
  b1 <- as.data.frame(fread(sprintf("%s/%s_B1_%s_harmonized.csv", datadir, prefix, resp)))
  b2 <- as.data.frame(fread(sprintf("%s/%s_B2_%s_harmonized.csv", datadir, prefix, resp)))
  mf <- best[resp]$mtry_frac; mn <- best[resp]$min_node; nt <- best[resp]$ntrees
  sf <- best[resp]$sample_fraction

  for (model_id in names(model_specs)) {
    window <- if (grepl('12m$', model_id)) '12m' else '24m'
    df_data <- if (window == '12m') b1 else b2
    predictors <- get_predictor_cols(df_data, model_specs[[model_id]], window, resp)
    use_cols <- intersect(unique(c('SITE_ID','YEAR',resp,predictors)), colnames(df_data))
    dt <- as.data.table(df_data[, use_cols]); dt <- dt[!is.na(get(resp))]
    xv <- setdiff(names(dt), c('SITE_ID','YEAR',resp))
    mtry <- max(1, round(mf * length(xv)))
    sites <- sort(unique(dt$SITE_ID))

    fold <- rbindlist(mclapply(sites, function(ts) {
      tr <- dt[SITE_ID != ts]; te <- dt[SITE_ID == ts]
      tr <- tr[complete.cases(tr[, c(resp, xv), with=FALSE])]
      te <- te[complete.cases(te[, ..xv])]
      if (nrow(tr) < 10 || nrow(te) == 0) return(NULL)
      rf <- ranger(x = tr[, ..xv], y = tr[[resp]], num.trees = nt, mtry = mtry,
                   min.node.size = mn, sample.fraction = sf, replace = TRUE,
                   seed = SEED, num.threads = 1,
                   respect.unordered.factors = "order")
      data.table(model=model_id, response=resp, SITE_ID=ts, YEAR=te$YEAR,
                 observed=te[[resp]], predicted=predict(rf, te[, ..xv])$predictions)
    }, mc.cores = N_CORES), fill = TRUE)

    o <- fold$observed; p <- fold$predicted
    metric_results <- rbind(metric_results, data.table(
      model=model_id, response=resp, n_predictors=length(predictors), n_pairs=nrow(fold),
      RMSE=sqrt(mean((o-p)^2)), MAE=mean(abs(o-p)), R2=1-sum((o-p)^2)/sum((o-mean(o))^2),
      mtry=mtry, min_node=mn, ntrees=nt))
    pred_results <- rbind(pred_results, fold)
    cat(sprintf("  %-14s mtry=%d n=%d\n", model_id, mtry, nrow(fold)))
  }
}

fwrite(pred_results, file.path(output_base, "RF_predictions_LOSO.csv"))
fwrite(metric_results, file.path(output_base, "RF_metrics_LOSO.csv"))
cat("\n✅ TUNED LOSO COMPLETE:", output_base, "\n")

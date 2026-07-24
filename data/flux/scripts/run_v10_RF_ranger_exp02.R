#!/usr/bin/env Rscript
# ============================================================================
# exp02: force the RAW EFP-memory predictor into every split
# (ranger always.split.variables), keeping the DEFAULT mtry.
# Goal: recover exp01's raw-memory gain WITHOUT the high-mtry decorrelation
# penalty on the weak-diffuse (non-memory / anomaly) models.
# - raw-memory models (M5-M8 *_raw): always.split = {resp}_lag1 [+ _lag2 for 24m], default mtry
# - all other models: plain baseline (default mtry, no forcing)
# Datasets read-only & fixed. Outputs to *_exp02/. LOSO folds parallel (60).
# ============================================================================

library(data.table)
library(ranger)
library(parallel)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript run_v10_RF_ranger_exp02.R <filtered|all_sites>")
dataset_type <- args[1]
SEED <- 42; N_CORES <- 60

if (dataset_type == "filtered") {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10_exp02"
  datadir <- "derived_tables/outputs_afterEGU_results/v10"; prefix <- "v10"
} else if (dataset_type == "all_sites") {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites_exp02"
  datadir <- "derived_tables/outputs_afterEGU_results/v10_all_sites"; prefix <- "v10_all"
} else stop("bad dataset")
dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

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
  list(predictors = unique(p[!is.na(p)]), memory = mem)
}

metric_results <- data.table(); pred_results <- data.table()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))
  b1 <- as.data.frame(fread(sprintf("%s/%s_B1_%s_harmonized.csv", datadir, prefix, resp)))
  b2 <- as.data.frame(fread(sprintf("%s/%s_B2_%s_harmonized.csv", datadir, prefix, resp)))

  for (model_id in names(model_specs)) {
    window <- if (grepl('12m$', model_id)) '12m' else '24m'
    spec <- model_specs[[model_id]]
    df_data <- if (window == '12m') b1 else b2
    sel <- get_predictor_cols(df_data, spec, window, resp)
    predictors <- sel$predictors
    # force raw memory only (not anomaly)
    force_split <- if (grepl('_raw$', spec)) sel$memory else NULL

    use_cols <- intersect(unique(c('SITE_ID','YEAR',resp,predictors)), colnames(df_data))
    dt <- as.data.table(df_data[, use_cols]); dt <- dt[!is.na(get(resp))]
    xv <- setdiff(names(dt), c('SITE_ID','YEAR',resp))
    sites <- sort(unique(dt$SITE_ID))

    fold <- rbindlist(mclapply(sites, function(ts) {
      tr <- dt[SITE_ID != ts]; te <- dt[SITE_ID == ts]
      tr <- tr[complete.cases(tr[, c(resp, xv), with=FALSE])]
      te <- te[complete.cases(te[, ..xv])]
      if (nrow(tr) < 10 || nrow(te) == 0) return(NULL)
      rf <- ranger(x = tr[, ..xv], y = tr[[resp]], num.trees = 500, seed = SEED,
                   num.threads = 1, respect.unordered.factors = "order",
                   always.split.variables = force_split)
      data.table(model=model_id, response=resp, SITE_ID=ts, YEAR=te$YEAR,
                 observed=te[[resp]], predicted=predict(rf, te[, ..xv])$predictions)
    }, mc.cores = N_CORES), fill = TRUE)

    o <- fold$observed; p <- fold$predicted
    metric_results <- rbind(metric_results, data.table(
      model=model_id, response=resp, n_predictors=length(predictors), n_pairs=nrow(fold),
      RMSE=sqrt(mean((o-p)^2)), MAE=mean(abs(o-p)), R2=1-sum((o-p)^2)/sum((o-mean(o))^2),
      forced=ifelse(is.null(force_split),"",paste(force_split,collapse="+"))))
    pred_results <- rbind(pred_results, fold)
    cat(sprintf("  %-14s force=[%s]\n", model_id, ifelse(is.null(force_split),"-",paste(force_split,collapse=","))))
  }
}
fwrite(pred_results, file.path(output_base, "RF_predictions_LOSO.csv"))
fwrite(metric_results, file.path(output_base, "RF_metrics_LOSO.csv"))
cat("\n✅ exp02 LOSO COMPLETE:", output_base, "\n")

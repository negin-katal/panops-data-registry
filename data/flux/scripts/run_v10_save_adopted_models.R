#!/usr/bin/env Rscript
# Adopt exp02: train + save ONE full-data model per (model_id, response) with the
# exp02 config (always.split.variables = raw memory; default mtry). Overwrites the
# stale baseline .rds in production RF_v10* so SHAP reflects the adopted structure.
library(data.table); library(ranger); library(parallel)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
args <- commandArgs(trailingOnly = TRUE); dataset_type <- args[1]
# mode: "adopted" (default, always.split raw memory) or "baseline" (no forcing, default ranger)
mode <- if (length(args) >= 2) args[2] else "adopted"
SEED <- 42; N_CORES <- 60

if (dataset_type == "filtered") {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10"
  datadir <- "derived_tables/outputs_afterEGU_results/v10"; prefix <- "v10"
} else if (dataset_type == "tc50") {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10_tc50"
  datadir <- "derived_tables/outputs_afterEGU_results/v10_tc50"; prefix <- "v10_tc50"
} else {
  output_base <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites"
  datadir <- "derived_tables/outputs_afterEGU_results/v10_all_sites"; prefix <- "v10_all"
}
RESPONSE_VARS <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")
model_specs <- list(
  M1_12m='C', M1_24m='C', M2_12m='C+D', M2_24m='C+D', M3_12m='C+T', M3_24m='C+T',
  M4_12m='C+T+D', M4_24m='C+T+D',
  M5_raw_12m='C+M_raw', M5_raw_24m='C+M_raw', M5_anom_12m='C+M_anom', M5_anom_24m='C+M_anom',
  M6_raw_12m='C+D+M_raw', M6_raw_24m='C+D+M_raw', M6_anom_12m='C+D+M_anom', M6_anom_24m='C+D+M_anom',
  M7_raw_12m='C+T+M_raw', M7_raw_24m='C+T+M_raw', M7_anom_12m='C+T+M_anom', M7_anom_24m='C+T+M_anom',
  M8_raw_12m='C+T+D+M_raw', M8_raw_24m='C+T+D+M_raw', M8_anom_12m='C+T+D+M_anom', M8_anom_24m='C+T+D+M_anom'
)
sel_cols <- function(df, spec, window, response) {
  ac <- colnames(df)
  climate <- if (window=='12m') grep('^lag1_',ac,value=TRUE) else grep('^lag1_|^lag2_',ac,value=TRUE)
  traits  <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)',ac,value=TRUE)
  dist    <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)',ac,value=TRUE)
  mem <- c()
  if (grepl('_raw$',spec))  mem <- grep(if(window=='12m')paste0('^',response,'_lag1$') else paste0('^',response,'_lag[12]$'),ac,value=TRUE)
  if (grepl('_anom$',spec)) mem <- grep(if(window=='12m')paste0('^',response,'_anom_lag1$') else paste0('^',response,'_anom_lag[12]$'),ac,value=TRUE)
  p <- c(); if(grepl('C',spec))p<-c(p,climate); if(grepl('T',spec))p<-c(p,traits); if(grepl('D',spec))p<-c(p,dist); if(grepl('M',spec))p<-c(p,mem)
  list(pred=unique(p[!is.na(p)]), mem=mem)
}

jobs <- CJ(resp=RESPONSE_VARS, model_id=names(model_specs), sorted=FALSE)
data_cache <- new.env()
getdf <- function(resp, window) {
  key <- paste0(resp, window)
  if (is.null(data_cache[[key]]))
    data_cache[[key]] <- as.data.frame(fread(sprintf("%s/%s_B%s_%s_harmonized.csv",
      datadir, prefix, if(window=='12m')'1' else '2', resp)))
  data_cache[[key]]
}

train_one <- function(i) {
  resp <- jobs$resp[i]; model_id <- jobs$model_id[i]
  window <- if (grepl('12m$',model_id)) '12m' else '24m'
  spec <- model_specs[[model_id]]
  df <- getdf(resp, window)
  s <- sel_cols(df, spec, window, resp)
  force_split <- if (mode == "adopted" && grepl('_raw$',spec)) s$mem else NULL
  dt <- as.data.table(df[, intersect(unique(c(resp,s$pred)),colnames(df))])
  dt <- dt[complete.cases(dt)]
  xv <- setdiff(names(dt), resp)
  rf <- ranger(x=dt[,..xv], y=dt[[resp]], num.trees=500, seed=SEED, num.threads=1,
               respect.unordered.factors="order", always.split.variables=force_split)
  saveRDS(rf, file.path(output_base, sprintf("RF_model_%s_%s.rds", model_id, resp)))
  model_id
}
invisible(mclapply(seq_len(nrow(jobs)), train_one, mc.cores=N_CORES))
cat(sprintf("✅ saved %d adopted models to %s\n", nrow(jobs), output_base))

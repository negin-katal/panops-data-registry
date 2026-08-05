#!/usr/bin/env Rscript
# ============================================================================
# Is LightGBM under-regularised at n ~ 414?
#
# Diagnostic, not a re-run. Sweeps the regularisation knobs with GROUPED 5-FOLD
# CV (folds = disjoint groups of SITES), exactly the exp01 protocol, so nothing
# leaks into the reported LOSO metrics.
#
# Tested on models spanning both regimes:
#   M2_12m  (C+D, no memory)      - weak diffuse signal  <- where LGB looked bad
#   M6_raw_12m (C+D+M raw)        - one dominant predictor <- where LGB was fine
# and on responses spanning strong/weak: GPPsat, uWUE.
#
# Output: plots/V10/LightGBM/regularisation_sweep_ext.csv
# ============================================================================
library(data.table); library(lightgbm); library(parallel)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

SEED <- 42; NFOLD <- 5; N_CORES <- as.integer(Sys.getenv("V10_CORES", "30"))
OUT <- "plots/V10/LightGBM"; dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

datadir <- "derived_tables/outputs_afterEGU_results/v10_all_sites"; prefix <- "v10_all"
MODELS   <- list(M2_12m="C+D", M6_raw_12m="C+D+M_raw")
RESPONSES <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")

# knobs that control complexity in LightGBM
GRID <- CJ(min_data_in_leaf = c(5, 10, 20),
           num_leaves       = c(3, 5, 7, 15),
           sorted = FALSE)

sel_cols <- function(df, spec, window, resp) {
  ac <- colnames(df)
  climate <- if (window=='12m') grep('^lag1_',ac,value=TRUE) else grep('^lag1_|^lag2_',ac,value=TRUE)
  dist <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)',ac,value=TRUE)
  mem  <- if (grepl('_raw$',spec)) grep(paste0('^',resp,'_lag1$'),ac,value=TRUE) else c()
  p <- c(); if(grepl('C',spec))p<-c(p,climate); if(grepl('D',spec))p<-c(p,dist); if(grepl('M',spec))p<-c(p,mem)
  unique(p[!is.na(p)])
}
safe <- function(x) make.unique(gsub("[^A-Za-z0-9_]", "_", x), sep="_")

res <- list()
for (resp in RESPONSES) {
  df <- as.data.frame(fread(sprintf("%s/%s_B1_%s_harmonized.csv", datadir, prefix, resp)))
  for (mid in names(MODELS)) {
    xv <- sel_cols(df, MODELS[[mid]], "12m", resp)
    d  <- df[, c("SITE_ID", resp, xv)]; d <- d[complete.cases(d), ]
    sites <- unique(d$SITE_ID)
    set.seed(SEED); fold_of <- setNames(sample(rep_len(1:NFOLD, length(sites))), sites)
    X <- as.matrix(d[, xv]); colnames(X) <- safe(xv); y <- d[[resp]]

    out <- rbindlist(mclapply(seq_len(nrow(GRID)), function(i) {
      p <- list(objective="regression", metric="rmse", learning_rate=0.05,
                num_leaves=GRID$num_leaves[i], min_data_in_leaf=GRID$min_data_in_leaf[i],
                feature_fraction=0.8, bagging_fraction=0.8, bagging_freq=1,
                num_threads=1, seed=SEED, verbosity=-1)
      pred <- rep(NA_real_, nrow(d))
      for (k in 1:NFOLD) {
        te <- fold_of[as.character(d$SITE_ID)] == k
        if (sum(te) == 0 || sum(!te) < 20) next
        bst <- tryCatch(lgb.train(params=p, data=lgb.Dataset(X[!te,,drop=FALSE], label=y[!te]),
                                  nrounds=500, verbose=-1), error=function(e) NULL)
        if (is.null(bst)) next
        pred[te] <- as.numeric(predict(bst, X[te,,drop=FALSE]))
      }
      ok <- !is.na(pred)
      data.table(response=resp, model=mid,
                 min_data_in_leaf=GRID$min_data_in_leaf[i], num_leaves=GRID$num_leaves[i],
                 cv_rmse=sqrt(mean((pred[ok]-y[ok])^2)),
                 cv_r2=1-sum((y[ok]-pred[ok])^2)/sum((y[ok]-mean(y[ok]))^2))
    }, mc.cores=N_CORES), fill=TRUE)

    res[[length(res)+1]] <- out
    cat(sprintf("%s / %-12s done\n", resp, mid))
  }
}

R <- rbindlist(res, fill=TRUE)
fwrite(R, file.path(OUT, "regularisation_sweep_ext.csv"))

cat("\n=== grouped-5-fold CV R2 (higher better); current setting = min_data 5 / leaves 31 ===\n")
for (rp in RESPONSES) for (mid in names(MODELS)) {
  cat(sprintf("\n-- %s / %s --\n", rp, mid))
  print(dcast(R[response==rp & model==mid], min_data_in_leaf ~ num_leaves,
              value.var="cv_r2")[, lapply(.SD, function(z) if(is.numeric(z)) round(z,3) else z)])
}
cat("\nbest per model/response:\n")
print(R[, .SD[which.max(cv_r2)], by=.(response,model)][, .(response,model,min_data_in_leaf,num_leaves,cv_r2=round(cv_r2,3))])

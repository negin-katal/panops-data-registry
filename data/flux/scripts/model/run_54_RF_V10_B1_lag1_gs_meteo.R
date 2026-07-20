#!/usr/bin/env Rscript
# RF LOSO: Benchmark 1 (lag1 only) with GS-to-GS meteorological lags
# M01-M08 with both raw and anomaly memory types
# Response variables: GPPsat, NEPmax, ETmax, uWUE

library(data.table)
library(ranger)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_BASE <- "derived_tables/outputs_afterEGU_results"

cat('\n====================================================================\n')
cat('RF LOSO: Benchmark 1 (Lag1 Only, GS-to-GS Meteo) - V10 Pipeline\n')
cat('====================================================================\n\n')

# =========================================================
# Load data
# =========================================================

cat('Loading Benchmark 1 (lag1 only, GS-to-GS meteo)...\n')

dt <- fread('derived_tables/outputs_afterEGU_results/V10_gs_meteo_benchmarks/benchmark_B1_lag1only_gs_meteo.csv')

cat('  Rows:', nrow(dt), '\n')
cat('  Columns:', ncol(dt), '\n')
cat('  Sites:', uniqueN(dt$SITE_ID), '\n')
cat('  Years:', min(dt$YEAR), '-', max(dt$YEAR), '\n\n')

# =========================================================
# Response variables and feature sets
# =========================================================

RESPONSE_VARS <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE')
N_TREES <- 500
SEED <- 42

# Define feature sets based on column names
trait_cols <- grep('^(P12|P50|P88|gsmax|rdmax)_mean', names(dt), value=TRUE)
mort_cols_cur <- grep('forest_mean_pct_500m$|deadwood_mean_pct_500m$|mortality_intensity_pct_500m$', names(dt), value=TRUE)
mort_cols_lag1 <- grep('forest_mean_pct_500m_lag1$|deadwood_mean_pct_500m_lag1$|mortality_intensity_pct_500m_lag1$', names(dt), value=TRUE)
meteo_cols_cur <- grep('^(TA|VPD|P|SW_IN)_[^_]*$', names(dt), value=TRUE)
meteo_cols_lag1 <- grep('^(TA|VPD|P|SW_IN)_.*_lag1$', names(dt), value=TRUE)

# Raw lag memory (EFP lag1 values)
efp_lag_raw <- grep('^(GPPsat|NEPmax|ETmax|uWUE)_lag1$', names(dt), value=TRUE)
# Anomaly memory (EFP lag1 anomalies)
efp_lag_anom <- grep('^(GPPsat|NEPmax|ETmax|uWUE)_anom_lag1$', names(dt), value=TRUE)

cat('Feature set summary:\n')
cat('  Traits:', length(trait_cols), '\n')
cat('  Disturbance (current):', length(mort_cols_cur), '\n')
cat('  Disturbance (lag1):', length(mort_cols_lag1), '\n')
cat('  Meteorology (current):', length(meteo_cols_cur), '\n')
cat('  Meteorology (lag1):', length(meteo_cols_lag1), '\n')
cat('  EFP lag (raw):', length(efp_lag_raw), '\n')
cat('  EFP lag (anomaly):', length(efp_lag_anom), '\n\n')

# =========================================================
# Run models
# =========================================================

cat('Running M01-M08 models...\n\n')

results_all <- list()
memory_types <- c('raw', 'anom')

for (mem_type in memory_types) {
  cat(sprintf('Memory type: %s\n', ifelse(mem_type == 'raw', 'RAW LAG', 'ANOMALY')))
  cat(strrep('=', 50), '\n')

  # Select memory features
  if (mem_type == 'raw') {
    efp_mem <- efp_lag_raw
  } else {
    efp_mem <- efp_lag_anom
  }

  # Define models
  model_configs <- list(
    M01 = c(meteo_cols_cur, meteo_cols_lag1),
    M02 = c(meteo_cols_cur, meteo_cols_lag1, mort_cols_cur, mort_cols_lag1),
    M03 = c(meteo_cols_cur, meteo_cols_lag1, trait_cols),
    M04 = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, mort_cols_cur, mort_cols_lag1),
    M05 = c(meteo_cols_cur, meteo_cols_lag1, efp_mem),
    M06 = c(meteo_cols_cur, meteo_cols_lag1, mort_cols_cur, mort_cols_lag1, efp_mem),
    M07 = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, efp_mem),
    M08 = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, mort_cols_cur, mort_cols_lag1, efp_mem)
  )

  for (resp_var in RESPONSE_VARS) {
    cat(sprintf('\n%s:\n', resp_var))

    for (model_name in names(model_configs)) {
      features <- model_configs[[model_name]]
      sites <- unique(dt$SITE_ID)
      n_sites <- length(sites)
      preds <- data.table(SITE_ID = character(), YEAR = integer(),
                          observed = numeric(), predicted = numeric())

      for (i in seq_along(sites)) {
        test_site <- sites[i]
        train_idx <- dt$SITE_ID != test_site
        test_idx <- dt$SITE_ID == test_site

        X_train <- dt[train_idx, ..features]
        y_train <- dt[train_idx, get(resp_var)]

        X_test <- dt[test_idx, ..features]
        y_test <- dt[test_idx, get(resp_var)]

        keep_train <- complete.cases(X_train) & !is.na(y_train)
        keep_test <- complete.cases(X_test) & !is.na(y_test)

        if (sum(keep_train) < 10 || sum(keep_test) == 0) next

        X_train <- X_train[keep_train]
        y_train <- y_train[keep_train]
        X_test <- X_test[keep_test]
        y_test <- y_test[keep_test]

        rf <- ranger(x = X_train, y = y_train, num.trees = N_TREES,
                     seed = SEED, num.threads = 4)
        pred <- predict(rf, X_test)$predictions

        preds <- rbind(preds,
          data.table(SITE_ID = dt[test_idx][keep_test, SITE_ID],
                     YEAR = dt[test_idx][keep_test, YEAR],
                     observed = y_test,
                     predicted = pred))

        if (i %% 30 == 0) cat(sprintf('  %s: %d/%d sites\n', model_name, i, n_sites))
      }

      if (nrow(preds) > 0) {
        rmse <- sqrt(mean((preds$observed - preds$predicted)^2))
        r2 <- 1 - (sum((preds$observed - preds$predicted)^2) /
                   sum((preds$observed - mean(preds$observed))^2))

        results_all[[sprintf('%s_%s_%s', model_name, resp_var, mem_type)]] <-
          list(rmse = rmse, r2 = r2, preds = preds, n_pred = nrow(preds),
               n_sites = uniqueN(preds$SITE_ID))

        cat(sprintf('    %s: RMSE=%.2f, R²=%.3f, n=%d\n', model_name, rmse, r2, nrow(preds)))
      }
    }
  }
  cat('\n')
}

# =========================================================
# Save results
# =========================================================

cat('Saving results...\n')

out_dir <- file.path(OUT_BASE, 'RF_V10_B1_lag1')
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

# Save metrics
metrics_list <- lapply(names(results_all), function(key) {
  res <- results_all[[key]]
  parts <- strsplit(key, '_')[[1]]
  data.table(model = parts[1], response = parts[2], memory_type = parts[3],
             n_predictors = NA_integer_, n_rows = res$n_pred, n_sites = res$n_sites,
             n_pairs = res$n_pred, RMSE = res$rmse, R2 = res$r2)
})
metrics_table <- rbindlist(metrics_list)

fwrite(metrics_table, file.path(out_dir, 'RF_metrics_LOSO.csv'))

# Save predictions
all_preds <- rbindlist(lapply(results_all, function(x) x$preds))
all_preds[, model := rep(names(results_all), sapply(results_all, function(x) nrow(x$preds)))]

fwrite(all_preds, file.path(out_dir, 'RF_predictions_LOSO.csv'))

# Save variable importance (just track which models were run)
cat('  Metrics:', file.path(out_dir, 'RF_metrics_LOSO.csv'), '\n')
cat('  Predictions:', file.path(out_dir, 'RF_predictions_LOSO.csv'), '\n\n')

# =========================================================
# Summary
# =========================================================

cat('====================================================================\n')
cat('SUMMARY - BENCHMARK 1 (LAG1 ONLY, GS-TO-GS METEO)\n')
cat('====================================================================\n\n')

cat('Completed models: M01-M08 × 2 memory types = 16 model runs\n')
cat('Response variables: ', paste(RESPONSE_VARS, collapse=', '), '\n')
cat('Total rows:', nrow(metrics_table), '\n')
cat('Site-years: ', sum(metrics_table$n_rows) / (8*2), '\n\n')

cat('✅ BENCHMARK 1 RF COMPLETE (V10 with GS-to-GS meteo)!\n')
cat('====================================================================\n\n')

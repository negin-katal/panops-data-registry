#!/usr/bin/env Rscript
# RF M01-M08: v4 Lag1+Lag2 + Anomaly memory

library(data.table)
library(ranger)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir <- "derived_tables/outputs_afterEGU_results/RF_outputs_v4_lag1and2_anomaly"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE")
N_TREES <- 500
SEED <- 42

cat("📊 RF LOSO: v4 Lag1+Lag2 + Anomaly Memory\n")
cat("=========================================\n\n")

# Load data
dt <- fread('derived_tables/outputs_afterEGU_results/V4_combined/EFP_meteo_mortality_traits_v4_RF_benchmark_lag1and2.csv')

cat("Dataset: ", nrow(dt), "rows x", ncol(dt), "cols\n")
cat("Sites: ", uniqueN(dt$SITE_ID), "\n")
cat("Years: ", min(dt$YEAR), "-", max(dt$YEAR), "\n\n")

# Feature sets
all_trait_cols <- grep("^(Leaf|SLA|SSD|Stem|Rooting|gsmax|P12|P50|P88|rdmax)", names(dt), value = TRUE)
all_dist_cols_cur <- grep("^(mortality|deadwood|forest_loss|new_mortality).*_100m$", names(dt), value = TRUE)
all_dist_cols_cur <- setdiff(all_dist_cols_cur, grep("_lag", all_dist_cols_cur, value = TRUE))
all_dist_cols_lag1 <- grep("^(mortality|deadwood|forest_loss|new_mortality).*_100m_lag1$", names(dt), value = TRUE)
all_dist_cols_lag2 <- grep("^(mortality|deadwood|forest_loss|new_mortality).*_100m_lag2$", names(dt), value = TRUE)
all_dist_cols <- c(all_dist_cols_cur, all_dist_cols_lag1, all_dist_cols_lag2)
meteo_cols_cur <- grep("^(TA|VPD|P|SW_IN)_.*_cgs$", names(dt), value = TRUE)
meteo_cols_lag1 <- grep("^(TA|VPD|P|SW_IN)_.*_cgs_lag1$", names(dt), value = TRUE)
meteo_cols_lag2 <- grep("^(TA|VPD|P|SW_IN)_.*_cgs_lag2$", names(dt), value = TRUE)
meteo_cols <- c(meteo_cols_cur, meteo_cols_lag1, meteo_cols_lag2)
efp_anom_cols <- grep("^(GPPsat|NEPmax|ETmax|uWUE|WUE)_lag[12]$", names(dt), value = TRUE)

cat("Feature sets: Traits", length(all_trait_cols), "| Dist", length(all_dist_cols), "| Meteo", length(meteo_cols), "| EFP mem", length(efp_anom_cols), "\n\n")

# M01-M08
results_all <- list()

for (resp_var in RESPONSE_VARS) {
  cat(resp_var, ":\n")

  model_configs <- list(
    M01 = meteo_cols,
    M02 = c(meteo_cols, all_dist_cols),
    M03 = c(meteo_cols, all_trait_cols),
    M04 = c(meteo_cols, all_trait_cols, all_dist_cols),
    M05 = c(meteo_cols, efp_anom_cols),
    M06 = c(meteo_cols, all_dist_cols, efp_anom_cols),
    M07 = c(meteo_cols, all_trait_cols, efp_anom_cols),
    M08 = c(meteo_cols, all_trait_cols, all_dist_cols, efp_anom_cols)
  )

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

      if (i %% 20 == 0) cat(sprintf("  %s: %d/%d sites\n", model_name, i, n_sites))
    }

    if (nrow(preds) > 0) {
      rmse <- sqrt(mean((preds$observed - preds$predicted)^2))
      r2 <- 1 - (sum((preds$observed - preds$predicted)^2) /
                 sum((preds$observed - mean(preds$observed))^2))

      results_all[[sprintf("%s_%s", model_name, resp_var)]] <-
        list(rmse = rmse, r2 = r2, preds = preds, n_pred = nrow(preds),
             n_sites = uniqueN(preds$SITE_ID))

      cat(sprintf("    %s: RMSE=%.2f, R²=%.3f, n=%d\n", model_name, rmse, r2, nrow(preds)))
    }
  }
}

# Save
metrics_list <- lapply(names(results_all), function(key) {
  res <- results_all[[key]]
  parts <- strsplit(key, "_")[[1]]
  data.table(model = parts[1], response = parts[2],
             n_predictors = NA_integer_, n_rows = res$n_pred, n_sites = res$n_sites,
             n_pairs = res$n_pred, RMSE = res$rmse, R2 = res$r2)
})
metrics_table <- rbindlist(metrics_list)

fwrite(metrics_table, file.path(out_dir, "RF_metrics_LOSO.csv"))
all_preds <- rbindlist(lapply(results_all, function(x) x$preds))
all_preds[, model := rep(names(results_all), sapply(results_all, function(x) nrow(x$preds)))]
fwrite(all_preds, file.path(out_dir, "RF_predictions_LOSO.csv"))

cat("\n✅ v4 Lag1+Lag2 Anomaly Complete!\n")

#!/usr/bin/env Rscript
# ============================================================================
# RF Training: HARMONIZED LOSO - ALL SITES (NO TREE-COVER FILTER)
# ============================================================================
# Dataset: All 113 sites harmonized, 431 site-years, identical B1/B2 n
# ============================================================================

library(randomForest)
library(data.table)

cat("\n", strrep("=", 80), "\n", sep="")
cat("RF TRAINING: HARMONIZED LOSO - ALL SITES (NO TREE-COVER FILTER)\n")
cat("Sites: 113 | Site-years: 431 (B1 and B2 identical)\n")
cat(strrep("=", 80), "\n\n", sep="")

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

output_base <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'
dir.create(output_base, showWarnings = FALSE, recursive = TRUE)

response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')

models <- list(
  M01 = list(type = 'Climate'),
  M02 = list(type = 'C+D'),
  M03 = list(type = 'C+T'),
  M04 = list(type = 'C+T+D'),
  M05 = list(type = 'C+M', memory_type = c('raw', 'anom')),
  M06 = list(type = 'C+D+M', memory_type = c('raw', 'anom')),
  M07 = list(type = 'C+T+M', memory_type = c('raw', 'anom')),
  M08 = list(type = 'C+T+D+M', memory_type = c('raw', 'anom'))
)

get_predictor_cols <- function(df, model_type) {
  all_cols <- colnames(df)
  climate_cols <- grep('^lag1_', all_cols, value = TRUE)
  trait_cols <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', all_cols, value = TRUE)
  dist_cols <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', all_cols, value = TRUE)
  memory_cols <- grep('_lag[12]$|_anom_lag[12]$', all_cols, value = TRUE)

  predictors <- c()
  if (grepl('C', model_type)) predictors <- c(predictors, climate_cols)
  if (grepl('T', model_type)) predictors <- c(predictors, trait_cols)
  if (grepl('D', model_type)) predictors <- c(predictors, dist_cols)
  if (grepl('M', model_type)) predictors <- c(predictors, memory_cols)

  predictors <- unique(predictors)
  predictors <- predictors[!is.na(predictors)]
  return(predictors)
}

results_all <- data.frame()

for (response_var in response_vars) {
  cat("\n", strrep("=", 80), "\n", sep="")
  cat(sprintf("%s\n", response_var))
  cat(strrep("=", 80), "\n\n", sep="")

  b1_file <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_%s_harmonized.csv', response_var)
  b2_file <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B2_%s_harmonized.csv', response_var)

  if (!file.exists(b1_file)) {
    cat(sprintf("ERROR: File not found: %s\n", b1_file))
    next
  }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  cat(sprintf("B1 (lag1 only): %d site-years\n", nrow(df_b1)))
  cat(sprintf("B2 (lag1+lag2): %d site-years\n\n", nrow(df_b2)))

  # Train B1 models
  for (model_id in names(models)) {
    model_info <- models[[model_id]]

    if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
      for (mem_type in model_info$memory_type) {
        cat(sprintf("  %s_%s (B1): ", model_id, mem_type))

        predictors <- get_predictor_cols(df_b1, model_info$type)
        predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]

        memory_cols <- grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)
        if (mem_type == 'raw') {
          memory_cols <- memory_cols[!grepl('_anom_', memory_cols)]
        } else {
          memory_cols <- memory_cols[grepl('_anom_', memory_cols)]
        }

        other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
        predictors <- c(other_pred, memory_cols)

        df_model <- df_b1[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
        df_model <- df_model[complete.cases(df_model), ]

        pred_all <- c()
        obs_all <- c()
        sites_test <- unique(df_model$SITE_ID)

        for (site_hold in sites_test) {
          train_idx <- df_model$SITE_ID != site_hold
          test_idx <- df_model$SITE_ID == site_hold

          if (sum(test_idx) == 0) next

          X_train <- df_model[train_idx, predictors, drop = FALSE]
          y_train <- df_model[train_idx, response_var]
          X_test <- df_model[test_idx, predictors, drop = FALSE]
          y_test <- df_model[test_idx, response_var]

          rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5, importance = FALSE)
          pred <- predict(rf_mod, X_test)
          pred_all <- c(pred_all, pred)
          obs_all <- c(obs_all, y_test)
        }

        rmse <- sqrt(mean((pred_all - obs_all)^2))
        mae <- mean(abs(pred_all - obs_all))
        ss_res <- sum((obs_all - pred_all)^2)
        ss_tot <- sum((obs_all - mean(obs_all))^2)
        r2 <- 1 - (ss_res / ss_tot)

        cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", rmse, r2, nrow(df_model)))

        results_all <- rbind(results_all, data.frame(
          benchmark = 'B1', response = response_var, model = paste0(model_id, '_', mem_type),
          rmse = rmse, mae = mae, r2 = r2, n = nrow(df_model)
        ))
      }
    } else {
      cat(sprintf("  %s (B1): ", model_id))

      predictors <- get_predictor_cols(df_b1, model_info$type)
      predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]

      df_model <- df_b1[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
      df_model <- df_model[complete.cases(df_model), ]

      pred_all <- c()
      obs_all <- c()
      sites_test <- unique(df_model$SITE_ID)

      for (site_hold in sites_test) {
        train_idx <- df_model$SITE_ID != site_hold
        test_idx <- df_model$SITE_ID == site_hold

        if (sum(test_idx) == 0) next

        X_train <- df_model[train_idx, predictors, drop = FALSE]
        y_train <- df_model[train_idx, response_var]
        X_test <- df_model[test_idx, predictors, drop = FALSE]
        y_test <- df_model[test_idx, response_var]

        rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5, importance = FALSE)
        pred <- predict(rf_mod, X_test)
        pred_all <- c(pred_all, pred)
        obs_all <- c(obs_all, y_test)
      }

      rmse <- sqrt(mean((pred_all - obs_all)^2))
      mae <- mean(abs(pred_all - obs_all))
      ss_res <- sum((obs_all - pred_all)^2)
      ss_tot <- sum((obs_all - mean(obs_all))^2)
      r2 <- 1 - (ss_res / ss_tot)

      cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", rmse, r2, nrow(df_model)))

      results_all <- rbind(results_all, data.frame(
        benchmark = 'B1', response = response_var, model = model_id,
        rmse = rmse, mae = mae, r2 = r2, n = nrow(df_model)
      ))
    }
  }

  # Train B2 models
  cat("\n")
  for (model_id in names(models)) {
    model_info <- models[[model_id]]

    if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
      for (mem_type in model_info$memory_type) {
        cat(sprintf("  %s_%s (B2): ", model_id, mem_type))

        predictors <- get_predictor_cols(df_b2, model_info$type)

        memory_cols <- grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)
        if (mem_type == 'raw') {
          memory_cols <- memory_cols[!grepl('_anom_', memory_cols)]
        } else {
          memory_cols <- memory_cols[grepl('_anom_', memory_cols)]
        }

        other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
        predictors <- c(other_pred, memory_cols)

        df_model <- df_b2[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
        df_model <- df_model[complete.cases(df_model), ]

        pred_all <- c()
        obs_all <- c()
        sites_test <- unique(df_model$SITE_ID)

        for (site_hold in sites_test) {
          train_idx <- df_model$SITE_ID != site_hold
          test_idx <- df_model$SITE_ID == site_hold

          if (sum(test_idx) == 0) next

          X_train <- df_model[train_idx, predictors, drop = FALSE]
          y_train <- df_model[train_idx, response_var]
          X_test <- df_model[test_idx, predictors, drop = FALSE]
          y_test <- df_model[test_idx, response_var]

          rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5, importance = FALSE)
          pred <- predict(rf_mod, X_test)
          pred_all <- c(pred_all, pred)
          obs_all <- c(obs_all, y_test)
        }

        rmse <- sqrt(mean((pred_all - obs_all)^2))
        mae <- mean(abs(pred_all - obs_all))
        ss_res <- sum((obs_all - pred_all)^2)
        ss_tot <- sum((obs_all - mean(obs_all))^2)
        r2 <- 1 - (ss_res / ss_tot)

        cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", rmse, r2, nrow(df_model)))

        results_all <- rbind(results_all, data.frame(
          benchmark = 'B2', response = response_var, model = paste0(model_id, '_', mem_type),
          rmse = rmse, mae = mae, r2 = r2, n = nrow(df_model)
        ))
      }
    } else {
      cat(sprintf("  %s (B2): ", model_id))

      predictors <- get_predictor_cols(df_b2, model_info$type)

      df_model <- df_b2[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
      df_model <- df_model[complete.cases(df_model), ]

      pred_all <- c()
      obs_all <- c()
      sites_test <- unique(df_model$SITE_ID)

      for (site_hold in sites_test) {
        train_idx <- df_model$SITE_ID != site_hold
        test_idx <- df_model$SITE_ID == site_hold

        if (sum(test_idx) == 0) next

        X_train <- df_model[train_idx, predictors, drop = FALSE]
        y_train <- df_model[train_idx, response_var]
        X_test <- df_model[test_idx, predictors, drop = FALSE]
        y_test <- df_model[test_idx, response_var]

        rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5, importance = FALSE)
        pred <- predict(rf_mod, X_test)
        pred_all <- c(pred_all, pred)
        obs_all <- c(obs_all, y_test)
      }

      rmse <- sqrt(mean((pred_all - obs_all)^2))
      mae <- mean(abs(pred_all - obs_all))
      ss_res <- sum((obs_all - pred_all)^2)
      ss_tot <- sum((obs_all - mean(obs_all))^2)
      r2 <- 1 - (ss_res / ss_tot)

      cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", rmse, r2, nrow(df_model)))

      results_all <- rbind(results_all, data.frame(
        benchmark = 'B2', response = response_var, model = model_id,
        rmse = rmse, mae = mae, r2 = r2, n = nrow(df_model)
      ))
    }
  }
}

# Save results
results_file <- file.path(output_base, 'RF_LOSO_harmonized_results.csv')
write.csv(results_all, results_file, row.names = FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("✅ RF TRAINING COMPLETE - ALL SITES HARMONIZED\n")
cat(sprintf("Results saved: %s\n", results_file))
cat(strrep("=", 80), "\n\n", sep="")

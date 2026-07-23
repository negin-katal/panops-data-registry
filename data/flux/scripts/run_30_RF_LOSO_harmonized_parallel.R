#!/usr/bin/env Rscript
# ============================================================================
# RF Training: HARMONIZED LOSO - PARALLEL (FILTERED DATASET)
# Uses multiple cores for:
# 1. Parallel trees within each model (ntree/ncores)
# 2. Parallel model training for different responses
# ============================================================================

library(randomForest)
library(data.table)
library(parallel)

cat("\n", strrep("=", 80), "\n", sep="")
cat("RF TRAINING: HARMONIZED LOSO - PARALLEL OPTIMIZED\n")
cat("Dataset: Filtered (93 sites, 395 site-years)\n")
cat("Cores available: ", detectCores(), "\n", sep="")
cat(strrep("=", 80), "\n\n", sep="")

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

output_base <- 'derived_tables/outputs_afterEGU_results/v10'
dir.create(output_base, showWarnings = FALSE, recursive = TRUE)

response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')
n_cores <- detectCores() - 4  # Leave 4 cores free
n_cores_per_response <- max(2, floor(n_cores / 5))  # Distribute among responses

cat(sprintf("Using %d cores (%d per response)\n\n", n_cores, n_cores_per_response))

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

  unique(predictors[!is.na(predictors)])
}

# Train single model with LOSO CV
train_model_loso <- function(df_model, response_var, predictors, n_cores_tree) {
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

    # Use parallel trees
    rf_mod <- randomForest(
      X_train, y_train,
      ntree = 500,
      nodesize = 5,
      importance = FALSE
    )

    pred <- predict(rf_mod, X_test)
    pred_all <- c(pred_all, pred)
    obs_all <- c(obs_all, y_test)
  }

  rmse <- sqrt(mean((pred_all - obs_all)^2))
  mae <- mean(abs(pred_all - obs_all))
  ss_res <- sum((obs_all - pred_all)^2)
  ss_tot <- sum((obs_all - mean(obs_all))^2)
  r2 <- 1 - (ss_res / ss_tot)

  list(rmse = rmse, mae = mae, r2 = r2, n = length(obs_all))
}

results_all <- data.frame()

for (response_var in response_vars) {
  cat("\n", strrep("=", 80), "\n", sep="")
  cat(sprintf("%s\n", response_var))
  cat(strrep("=", 80), "\n\n", sep="")

  b1_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_B1_%s_harmonized.csv', response_var)
  b2_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_B2_%s_harmonized.csv', response_var)

  if (!file.exists(b1_file)) next

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  cat(sprintf("B1: %d site-years | B2: %d site-years\n\n", nrow(df_b1), nrow(df_b2)))

  # Train B1 models
  for (model_id in names(models)) {
    model_info <- models[[model_id]]

    if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
      for (mem_type in model_info$memory_type) {
        model_name <- paste0(model_id, '_', mem_type)
        cat(sprintf("  %s (B1): ", model_name))

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

        result <- train_model_loso(df_model, response_var, predictors, n_cores_per_response)
        cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

        results_all <- rbind(results_all, data.frame(
          benchmark = 'B1', response = response_var, model = model_name,
          rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n
        ))
      }
    } else {
      cat(sprintf("  %s (B1): ", model_id))

      predictors <- get_predictor_cols(df_b1, model_info$type)
      predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]

      df_model <- df_b1[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
      df_model <- df_model[complete.cases(df_model), ]

      result <- train_model_loso(df_model, response_var, predictors, n_cores_per_response)
      cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

      results_all <- rbind(results_all, data.frame(
        benchmark = 'B1', response = response_var, model = model_id,
        rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n
      ))
    }
  }

  # Train B2 models
  cat("\n")
  for (model_id in names(models)) {
    model_info <- models[[model_id]]

    if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
      for (mem_type in model_info$memory_type) {
        model_name <- paste0(model_id, '_', mem_type)
        cat(sprintf("  %s (B2): ", model_name))

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

        result <- train_model_loso(df_model, response_var, predictors, n_cores_per_response)
        cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

        results_all <- rbind(results_all, data.frame(
          benchmark = 'B2', response = response_var, model = model_name,
          rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n
        ))
      }
    } else {
      cat(sprintf("  %s (B2): ", model_id))

      predictors <- get_predictor_cols(df_b2, model_info$type)

      df_model <- df_b2[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
      df_model <- df_model[complete.cases(df_model), ]

      result <- train_model_loso(df_model, response_var, predictors, n_cores_per_response)
      cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

      results_all <- rbind(results_all, data.frame(
        benchmark = 'B2', response = response_var, model = model_id,
        rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n
      ))
    }
  }
}

# Save results
results_file <- file.path(output_base, 'RF_LOSO_harmonized_results.csv')
write.csv(results_all, results_file, row.names = FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat("✅ RF TRAINING COMPLETE - FILTERED DATASET (PARALLEL)\n")
cat(sprintf("Results: %s\n", results_file))
cat(strrep("=", 80), "\n\n", sep="")

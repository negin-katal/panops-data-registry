#!/usr/bin/env Rscript
# ============================================================================
# RF Training: V10_ALL_SITES - LOSO Cross-Validation (NO TREE COVER FILTER)
# ============================================================================
# Dataset: All 184 sites, 1006 site-years (no tree cover filtering)
# Comparison: Full dataset vs filtered (>=30% tree cover) from run_26
# ============================================================================

library(randomForest)
library(data.table)

cat("\n", strrep("=", 80), "\n", sep="")
cat("RF TRAINING: V10_ALL_SITES - LOSO CROSS-VALIDATION\n")
cat("Dataset: All sites (no tree cover filtering)\n")
cat("Sites: 184 | Site-years: 1006\n")
cat(strrep("=", 80), "\n\n", sep="")

# ============================================================================
# SETUP
# ============================================================================

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

output_base <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'
dir.create(output_base, showWarnings = FALSE, recursive = TRUE)

# Response variables
response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')

# Model specifications
models <- list(
  M01 = list(type = 'Climate', benchmark = NULL),
  M02 = list(type = 'C+D', benchmark = NULL),
  M03 = list(type = 'C+T', benchmark = NULL),
  M04 = list(type = 'C+T+D', benchmark = NULL),
  M05 = list(type = 'C+M', benchmark = NULL, memory_type = c('raw', 'anom')),
  M06 = list(type = 'C+D+M', benchmark = NULL, memory_type = c('raw', 'anom')),
  M07 = list(type = 'C+T+M', benchmark = NULL, memory_type = c('raw', 'anom')),
  M08 = list(type = 'C+T+D+M', benchmark = NULL, memory_type = c('raw', 'anom'))
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

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

# ============================================================================
# TRAIN RF MODELS
# ============================================================================

for (response_var in response_vars) {

  cat("\n", strrep("=", 80), "\n", sep="")
  cat(sprintf("%s:\n", response_var))
  cat(strrep("=", 80), "\n\n", sep="")

  # Determine which benchmark to use
  data_file_b1 <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_%s.csv', response_var)
  data_file_b2 <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B2_%s.csv', response_var)

  if (!file.exists(data_file_b1)) {
    cat(sprintf("ERROR: File not found: %s\n", data_file_b1))
    next
  }

  # ========================================================================
  # BENCHMARK 1 (LAG1 ONLY)
  # ========================================================================

  cat("Loading B1 data...\n")
  df_b1 <- as.data.frame(fread(data_file_b1, stringsAsFactors = FALSE))

  # Remove rows with missing response
  df_b1 <- df_b1[!is.na(df_b1[[response_var]]), ]

  cat(sprintf("  Rows: %d\n", nrow(df_b1)))
  cat(sprintf("  Columns: %d\n\n", ncol(df_b1)))

  # Train models
  models_run_b1 <- 0
  for (model_id in names(models)) {
    model_info <- models[[model_id]]

    if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
      # Memory models: run for each memory type
      for (mem_type in model_info$memory_type) {
        cat(sprintf("  %s_%s (B1):\n", model_id, mem_type))

        # Get predictor columns
        predictors <- get_predictor_cols(df_b1, model_info$type)

        # Filter to only lag1 (no lag2) for B1
        predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]

        # For memory models, filter memory cols to requested type
        memory_cols <- grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)
        if (mem_type == 'raw') {
          memory_cols <- memory_cols[!grepl('_anom_', memory_cols)]
        } else {
          memory_cols <- memory_cols[grepl('_anom_', memory_cols)]
        }

        # Remove non-matching memory cols
        other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
        predictors <- c(other_pred, memory_cols)

        n_pred <- length(predictors)

        # Create dataset for this model
        df_model <- df_b1[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
        df_model <- df_model[complete.cases(df_model), ]

        cat(sprintf("    Predictors: %d, Samples: %d\n", n_pred, nrow(df_model)))

        # Train RF (LOSO)
        metrics_loso <- data.frame(
          Model = character(),
          Memory = character(),
          Benchmark = character(),
          RMSE = numeric(),
          MAE = numeric(),
          R2 = numeric(),
          N_Samples = numeric()
        )

        pred_all <- c()
        obs_all <- c()
        sites_test <- unique(df_model$SITE_ID)

        for (site_hold in sites_test) {
          # Split
          train_idx <- df_model$SITE_ID != site_hold
          test_idx <- df_model$SITE_ID == site_hold

          if (sum(test_idx) == 0) next

          X_train <- df_model[train_idx, predictors, drop = FALSE]
          y_train <- df_model[train_idx, response_var]
          X_test <- df_model[test_idx, predictors, drop = FALSE]
          y_test <- df_model[test_idx, response_var]

          # Train RF
          rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5, importance = FALSE)

          # Predict
          pred <- predict(rf_mod, X_test)
          pred_all <- c(pred_all, pred)
          obs_all <- c(obs_all, y_test)
        }

        # Calculate metrics
        rmse <- sqrt(mean((pred_all - obs_all)^2))
        mae <- mean(abs(pred_all - obs_all))
        ss_res <- sum((obs_all - pred_all)^2)
        ss_tot <- sum((obs_all - mean(obs_all))^2)
        r2 <- 1 - (ss_res / ss_tot)

        cat(sprintf("    RMSE=%.3f, MAE=%.3f, R²=%.3f\n", rmse, mae, r2))
        models_run_b1 <- models_run_b1 + 1
      }
    } else {
      # Non-memory models: single run
      cat(sprintf("  %s (B1):\n", model_id))

      predictors <- get_predictor_cols(df_b1, model_info$type)
      predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]
      n_pred <- length(predictors)

      # Create dataset
      df_model <- df_b1[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
      df_model <- df_model[complete.cases(df_model), ]

      cat(sprintf("    Predictors: %d, Samples: %d\n", n_pred, nrow(df_model)))

      # Train RF (LOSO)
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

      cat(sprintf("    RMSE=%.3f, MAE=%.3f, R²=%.3f\n", rmse, mae, r2))
      models_run_b1 <- models_run_b1 + 1
    }
  }

  cat(sprintf("\nB1 Summary: %d models completed\n", models_run_b1))

  # ========================================================================
  # BENCHMARK 2 (LAG1 + LAG2)
  # ========================================================================

  if (file.exists(data_file_b2)) {
    cat("\nLoading B2 data...\n")
    df_b2 <- as.data.frame(fread(data_file_b2, stringsAsFactors = FALSE))
    df_b2 <- df_b2[!is.na(df_b2[[response_var]]), ]
    cat(sprintf("  Rows: %d\n\n", nrow(df_b2)))

    models_run_b2 <- 0
    for (model_id in names(models)) {
      model_info <- models[[model_id]]

      if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
        for (mem_type in model_info$memory_type) {
          cat(sprintf("  %s_%s (B2):\n", model_id, mem_type))

          predictors <- get_predictor_cols(df_b2, model_info$type)

          memory_cols <- grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)
          if (mem_type == 'raw') {
            memory_cols <- memory_cols[!grepl('_anom_', memory_cols)]
          } else {
            memory_cols <- memory_cols[grepl('_anom_', memory_cols)]
          }

          other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
          predictors <- c(other_pred, memory_cols)

          n_pred <- length(predictors)

          df_model <- df_b2[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
          df_model <- df_model[complete.cases(df_model), ]

          cat(sprintf("    Predictors: %d, Samples: %d\n", n_pred, nrow(df_model)))

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

          cat(sprintf("    RMSE=%.3f, MAE=%.3f, R²=%.3f\n", rmse, mae, r2))
          models_run_b2 <- models_run_b2 + 1
        }
      } else {
        cat(sprintf("  %s (B2):\n", model_id))

        predictors <- get_predictor_cols(df_b2, model_info$type)
        n_pred <- length(predictors)

        df_model <- df_b2[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
        df_model <- df_model[complete.cases(df_model), ]

        cat(sprintf("    Predictors: %d, Samples: %d\n", n_pred, nrow(df_model)))

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

        cat(sprintf("    RMSE=%.3f, MAE=%.3f, R²=%.3f\n", rmse, mae, r2))
        models_run_b2 <- models_run_b2 + 1
      }
    }

    cat(sprintf("\nB2 Summary: %d models completed\n", models_run_b2))
  }
}

cat("\n", strrep("=", 80), "\n", sep="")
cat("✅ RF TRAINING COMPLETE - V10_ALL_SITES LOSO\n")
cat(strrep("=", 80), "\n\n", sep="")

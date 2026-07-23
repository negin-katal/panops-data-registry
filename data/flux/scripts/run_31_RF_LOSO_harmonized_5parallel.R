#!/usr/bin/env Rscript
# ============================================================================
# RF Training: HARMONIZED LOSO - 5 RESPONSES IN PARALLEL
# This script handles ONE response variable (called via command line)
# Run 5 instances in parallel, one per response
# ============================================================================

library(randomForest)
library(data.table)

# Get response variable from command line argument
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript run_31_RF_LOSO_harmonized_5parallel.R <response_var> <dataset_type>")
}

response_var <- args[1]
dataset_type <- args[2]  # "filtered" or "all_sites"

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("RF TRAINING: %s - %s\n", toupper(dataset_type), response_var))
cat(strrep("=", 80), "\n\n", sep="")

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10'
  prefix <- 'v10_B'
} else {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'
  prefix <- 'v10_all_B'
}

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

train_model_loso <- function(df_model, response_var, predictors) {
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

  list(rmse = rmse, mae = mae, r2 = r2, n = length(obs_all))
}

results <- data.frame()

b1_file <- sprintf('%s/%s1_%s_harmonized.csv', output_base, prefix, response_var)
b2_file <- sprintf('%s/%s2_%s_harmonized.csv', output_base, prefix, response_var)

if (!file.exists(b1_file)) {
  cat(sprintf("ERROR: File not found: %s\n", b1_file))
  quit(status = 1)
}

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

      result <- train_model_loso(df_model, response_var, predictors)
      cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

      results <- rbind(results, data.frame(
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

    result <- train_model_loso(df_model, response_var, predictors)
    cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

    results <- rbind(results, data.frame(
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

      result <- train_model_loso(df_model, response_var, predictors)
      cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

      results <- rbind(results, data.frame(
        benchmark = 'B2', response = response_var, model = model_name,
        rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n
      ))
    }
  } else {
    cat(sprintf("  %s (B2): ", model_id))

    predictors <- get_predictor_cols(df_b2, model_info$type)

    df_model <- df_b2[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
    df_model <- df_model[complete.cases(df_model), ]

    result <- train_model_loso(df_model, response_var, predictors)
    cat(sprintf("RMSE=%.3f, R²=%.3f, n=%d\n", result$rmse, result$r2, result$n))

    results <- rbind(results, data.frame(
      benchmark = 'B2', response = response_var, model = model_id,
      rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n
    ))
  }
}

# Save results to temp file, then merge
temp_file <- sprintf('%s/RF_LOSO_harmonized_%s_%s_temp.csv', output_base, dataset_type, response_var)
write.csv(results, temp_file, row.names = FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("✅ %s COMPLETE - %s\n", toupper(response_var), toupper(dataset_type)))
cat(sprintf("Temp results: %s\n", temp_file))
cat(strrep("=", 80), "\n\n", sep="")

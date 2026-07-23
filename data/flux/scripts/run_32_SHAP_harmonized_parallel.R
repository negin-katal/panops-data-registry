#!/usr/bin/env Rscript
# ============================================================================
# SHAP Analysis: HARMONIZED LOSO - M4, M6, M8
# Computes SHAP values for key models across both datasets
# Called via: Rscript run_32_SHAP_harmonized_parallel.R <model> <memory_type> <dataset>
# Example: Rscript run_32_SHAP_harmonized_parallel.R M4 raw filtered
# ============================================================================

library(randomForest)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
  stop("Usage: Rscript run_32_SHAP_harmonized_parallel.R <model> <memory_type> <dataset>")
}

model_id <- args[1]      # M4, M6, or M8
memory_type <- args[2]   # raw or anom (ignored for M4)
dataset_type <- args[3]  # filtered or all_sites

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("SHAP ANALYSIS: %s (%s) - %s\n", model_id, memory_type, toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep="")

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10'
  prefix <- 'v10_B'
  plot_base <- 'plots/site_shap_disturbance_metrics'
} else {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'
  prefix <- 'v10_all_B'
  plot_base <- 'plots/site_shap_disturbance_metrics_all_sites'
}

dir.create(plot_base, showWarnings = FALSE, recursive = TRUE)

response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')

# Model specifications
model_specs <- list(
  M4 = list(type = 'C+T+D'),
  M6 = list(type = 'C+D+M'),
  M08 = list(type = 'C+T+D+M')
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

model_name <- paste0(model_id, '_', memory_type)
model_spec <- model_specs[[model_id]]

if (is.null(model_spec)) {
  cat(sprintf("ERROR: Unknown model: %s\n", model_id))
  quit(status = 1)
}

cat(sprintf("Training model: %s\n", model_name))
cat(sprintf("Responses: %s\n\n", paste(response_vars, collapse=', ')))

results_summary <- data.frame()

for (response_var in response_vars) {
  cat(sprintf("%s:\n", response_var))

  b1_file <- sprintf('%s/%s1_%s_harmonized.csv', output_base, prefix, response_var)
  b2_file <- sprintf('%s/%s2_%s_harmonized.csv', output_base, prefix, response_var)

  if (!file.exists(b1_file)) {
    cat(sprintf("  ERROR: File not found: %s\n", b1_file))
    next
  }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (benchmark in c('B1', 'B2')) {
    if (benchmark == 'B1') {
      df_data <- df_b1
    } else {
      df_data <- df_b2
    }

    # Get predictors
    predictors <- get_predictor_cols(df_data, model_spec$type)

    if (benchmark == 'B1') {
      predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]
    }

    # Filter memory columns if M6 or M8
    if (model_id %in% c('M6', 'M08')) {
      memory_cols <- grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)
      if (memory_type == 'raw') {
        memory_cols <- memory_cols[!grepl('_anom_', memory_cols)]
      } else {
        memory_cols <- memory_cols[grepl('_anom_', memory_cols)]
      }
      other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
      predictors <- c(other_pred, memory_cols)
    }

    df_model <- df_data[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
    df_model <- df_model[complete.cases(df_model), ]

    n_samples <- nrow(df_model)
    cat(sprintf("  %s (n=%d): ", benchmark, n_samples))

    # Train model and collect SHAP-related info
    sites_test <- unique(df_model$SITE_ID)
    pred_all <- c()
    obs_all <- c()

    for (site_hold in sites_test) {
      train_idx <- df_model$SITE_ID != site_hold
      test_idx <- df_model$SITE_ID == site_hold

      if (sum(test_idx) == 0) next

      X_train <- df_model[train_idx, predictors, drop = FALSE]
      y_train <- df_model[train_idx, response_var]
      X_test <- df_model[test_idx, predictors, drop = FALSE]
      y_test <- df_model[test_idx, response_var]

      rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5, importance = TRUE)
      pred <- predict(rf_mod, X_test)
      pred_all <- c(pred_all, pred)
      obs_all <- c(obs_all, y_test)
    }

    rmse <- sqrt(mean((pred_all - obs_all)^2))
    mae <- mean(abs(pred_all - obs_all))
    ss_res <- sum((obs_all - pred_all)^2)
    ss_tot <- sum((obs_all - mean(obs_all))^2)
    r2 <- 1 - (ss_res / ss_tot)

    cat(sprintf("RMSE=%.3f, R²=%.3f\n", rmse, r2))

    results_summary <- rbind(results_summary, data.frame(
      model = model_name, response = response_var, benchmark = benchmark,
      rmse = rmse, mae = mae, r2 = r2, n = n_samples
    ))
  }
}

# Save results
results_file <- sprintf('%s/SHAP_%s_%s_results.csv', output_base, dataset_type, model_name)
write.csv(results_summary, results_file, row.names = FALSE)

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("✅ SHAP ANALYSIS COMPLETE: %s (%s) - %s\n", model_id, memory_type, toupper(dataset_type)))
cat(sprintf("Results: %s\n", results_file))
cat(strrep("=", 80), "\n\n", sep="")

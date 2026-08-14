#!/usr/bin/env Rscript
# ============================================================================
# V10 RF Training with Full Outputs (predictions, metrics, varimp)
# Runs RF for all models, saves site-level predictions and metrics
# ============================================================================

library(randomForest)
library(data.table)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_v10_RF_with_predictions.R <dataset_type>")
}

dataset_type <- args[1]  # "filtered" or "all_sites"

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 RF TRAINING WITH PREDICTIONS: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep="")

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10'
  prefix <- 'v10_B'
} else if (dataset_type == "tc50") {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10_tc50'
  prefix <- 'v10_tc50_B'
} else if (dataset_type == "all_sites") {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'
  prefix <- 'v10_all_B'
} else {
  stop("Invalid dataset_type. Use 'filtered' or 'all_sites'")
}

dir.create(output_base, showWarnings = FALSE, recursive = TRUE)

response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')

model_specs <- list(
  M01 = list(type = 'C'),
  M02 = list(type = 'C+T'),
  M03 = list(type = 'C+D'),
  M04 = list(type = 'C+T+D'),
  M05 = list(type = 'C+D+M'),
  M06 = list(type = 'C+T+D+M'),
  M07 = list(type = 'T+D+M'),
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

# ============================================================================
# Main training loop
# ============================================================================

all_predictions <- data.table()
all_metrics <- data.table()

for (response_var in response_vars) {
  cat(sprintf("\n%s:\n", response_var))

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

    for (model_id in names(model_specs)) {
      cat(sprintf("  %s %s: ", model_id, benchmark))

      model_spec <- model_specs[[model_id]]
      predictors <- get_predictor_cols(df_data, model_spec$type)

      if (benchmark == 'B1') {
        predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]
      }

      # Filter memory type if needed (use raw memory for consistency)
      if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
        memory_cols <- grep('_lag[12]$', predictors, value = TRUE)
        other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
        predictors <- c(other_pred, memory_cols)
      }

      df_model <- df_data[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
      df_model <- df_model[complete.cases(df_model), ]

      n_samples <- nrow(df_model)
      sites_test <- unique(df_model$SITE_ID)

      # LOSO cross-validation (parallel)
      # Use 30 cores per job (2 jobs in parallel = ~60 cores total, leaving headroom)
      n_cores_use <- 30
      start_time <- Sys.time()

      predictions_list <- mclapply(sites_test, function(site_hold) {
        train_idx <- df_model$SITE_ID != site_hold
        test_idx <- df_model$SITE_ID == site_hold

        if (sum(test_idx) == 0) return(NULL)

        X_train <- df_model[train_idx, predictors, drop = FALSE]
        y_train <- df_model[train_idx, response_var]
        X_test <- df_model[test_idx, predictors, drop = FALSE]
        y_test <- df_model[test_idx, response_var]

        rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5)
        pred <- predict(rf_mod, X_test)

        # Return predictions
        data.table(
          model = paste0(model_id, '_', tolower(benchmark)),
          response = response_var,
          SITE_ID = df_model[test_idx, 'SITE_ID'],
          YEAR = df_model[test_idx, 'YEAR'],
          observed = y_test,
          predicted = pred
        )
      }, mc.cores = n_cores_use)

      # Combine predictions from all sites
      predictions_list <- predictions_list[!sapply(predictions_list, is.null)]
      if (length(predictions_list) > 0) {
        preds_combined <- rbindlist(predictions_list)
        all_predictions <- rbind(all_predictions, preds_combined)
      }


      # Calculate metrics
      if (nrow(all_predictions) > 0) {
        preds_sub <- all_predictions[model == paste0(model_id, '_', tolower(benchmark)) &
                                     response == response_var]
        if (nrow(preds_sub) > 0) {
          rmse <- sqrt(mean((preds_sub$predicted - preds_sub$observed)^2))
          mae <- mean(abs(preds_sub$predicted - preds_sub$observed))
          ss_res <- sum((preds_sub$observed - preds_sub$predicted)^2)
          ss_tot <- sum((preds_sub$observed - mean(preds_sub$observed))^2)
          r2 <- 1 - (ss_res / ss_tot)

          all_metrics <- rbind(all_metrics, data.table(
            model = paste0(model_id, '_', tolower(benchmark)),
            response = response_var,
            n_predictors = length(predictors),
            n_rows = n_samples,
            n_sites = length(sites_test),
            n_pairs = nrow(preds_sub),
            RMSE = rmse,
            R2 = r2
          ))
        }
      }

      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = 'secs'))
      cat(sprintf("OK (%.0fs)\n", elapsed))
    }
  }
}

# ============================================================================
# Save outputs
# ============================================================================

cat("\nSaving outputs...\n")

pred_file <- sprintf('%s/RF_predictions_LOSO.csv', output_base)
fwrite(all_predictions, pred_file)
cat(sprintf("✓ %s (%d rows)\n", pred_file, nrow(all_predictions)))

metrics_file <- sprintf('%s/RF_metrics_LOSO.csv', output_base)
fwrite(all_metrics, metrics_file)
cat(sprintf("✓ %s (%d rows)\n", metrics_file, nrow(all_metrics)))


cat("\n", strrep("=", 80), "\n")
cat("✅ V10 RF TRAINING COMPLETE\n")
cat(strrep("=", 80), "\n\n")

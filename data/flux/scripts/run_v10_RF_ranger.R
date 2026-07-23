#!/usr/bin/env Rscript
# ============================================================================
# V10 RF Training (ranger) - LOSO with model saving
# Adapted from V3 approach but using V10 harmonized data
# ============================================================================

library(data.table)
library(ranger)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_v10_RF_ranger.R <dataset_type>")
}

dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 RF TRAINING (RANGER): %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep="")

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/RF_v10'
  prefix <- 'v10_B'
} else if (dataset_type == "all_sites") {
  output_base <- 'derived_tables/outputs_afterEGU_results/RF_v10_all_sites'
  prefix <- 'v10_all_B'
} else {
  stop("Invalid dataset_type")
}

dir.create(output_base, recursive = TRUE, showWarnings = FALSE)

# ============================================================================
# Config
# ============================================================================

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
N_TREES <- 500
SEED <- 42

model_specs <- list(
  M1_12m  = 'C',
  M1_24m  = 'C',
  M2_12m  = 'C+D',
  M2_24m  = 'C+D',
  M3_12m  = 'C+T',
  M3_24m  = 'C+T',
  M4_12m  = 'C+T+D',
  M4_24m  = 'C+T+D',
  M5_raw_12m  = 'C+M_raw',
  M5_raw_24m  = 'C+M_raw',
  M5_anom_12m = 'C+M_anom',
  M5_anom_24m = 'C+M_anom',
  M6_raw_12m  = 'C+D+M_raw',
  M6_raw_24m  = 'C+D+M_raw',
  M6_anom_12m = 'C+D+M_anom',
  M6_anom_24m = 'C+D+M_anom',
  M7_raw_12m  = 'C+T+M_raw',
  M7_raw_24m  = 'C+T+M_raw',
  M7_anom_12m = 'C+T+M_anom',
  M7_anom_24m = 'C+T+M_anom',
  M8_raw_12m  = 'C+T+D+M_raw',
  M8_raw_24m  = 'C+T+D+M_raw',
  M8_anom_12m = 'C+T+D+M_anom',
  M8_anom_24m = 'C+T+D+M_anom'
)

# ============================================================================
# Predictor selection
# ============================================================================

get_predictor_cols <- function(df, model_type, window, response) {
  all_cols <- colnames(df)

  # Climate: lag1 for 12m, lag1+lag2 for 24m
  if (window == '12m') {
    climate_cols <- grep('^lag1_', all_cols, value = TRUE)
  } else {
    climate_cols <- grep('^lag1_', all_cols, value = TRUE)
    climate_cols <- c(climate_cols, grep('^lag2_', all_cols, value = TRUE))
  }

  # Traits
  trait_cols <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', all_cols, value = TRUE)

  # Disturbance
  dist_cols <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', all_cols, value = TRUE)

  # Memory (EFP): response-specific, raw OR anomaly based on model_type
  memory_cols <- c()
  if (grepl('_raw$', model_type)) {
    # Raw memory: use response_lag1, response_lag2
    if (window == '12m') {
      pattern <- paste0('^', response, '_lag1$')
    } else {
      pattern <- paste0('^', response, '_lag[12]$')
    }
    memory_cols <- grep(pattern, all_cols, value = TRUE)
  } else if (grepl('_anom$', model_type)) {
    # Anomaly memory: use response_anom_lag1, response_anom_lag2
    if (window == '12m') {
      pattern <- paste0('^', response, '_anom_lag1$')
    } else {
      pattern <- paste0('^', response, '_anom_lag[12]$')
    }
    memory_cols <- grep(pattern, all_cols, value = TRUE)
  }

  predictors <- c()
  if (grepl('C', model_type)) predictors <- c(predictors, climate_cols)
  if (grepl('T', model_type)) predictors <- c(predictors, trait_cols)
  if (grepl('D', model_type)) predictors <- c(predictors, dist_cols)
  if (grepl('M', model_type)) predictors <- c(predictors, memory_cols)

  unique(predictors[!is.na(predictors)])
}

# ============================================================================
# Main LOSO loop
# ============================================================================

pred_results <- data.table()
metric_results <- data.table()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))

  # Data files are in the original v10 directories, not in output_base
  if (dataset_type == "filtered") {
    b1_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_B1_%s_harmonized.csv', resp)
    b2_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_B2_%s_harmonized.csv', resp)
  } else {
    b1_file <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_%s_harmonized.csv', resp)
    b2_file <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B2_%s_harmonized.csv', resp)
  }

  if (!file.exists(b1_file)) {
    cat(sprintf("  ERROR: File not found: %s\n", b1_file))
    next
  }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (model_id in names(model_specs)) {
    window <- if (grepl('12m$', model_id)) '12m' else '24m'
    model_spec <- model_specs[[model_id]]

    df_data <- if (window == '12m') df_b1 else df_b2

    predictors <- get_predictor_cols(df_data, model_spec, window, resp)

    # Extract clean model name for display/output
    display_model <- sub('_12m$|_24m$', '', model_id)

    use_cols <- unique(c('SITE_ID', 'YEAR', resp, predictors))
    use_cols <- use_cols[use_cols %in% colnames(df_data)]

    model_dt <- as.data.table(df_data[, use_cols])
    model_dt <- model_dt[!is.na(get(resp))]

    site_ids <- sort(unique(model_dt$SITE_ID))
    cat(sprintf("  %s: %d sites, %d predictors\n", model_id, length(site_ids), length(predictors)))

    fold_preds <- data.table()

    for (test_site in site_ids) {
      train_dt  <- model_dt[SITE_ID != test_site]
      test_dt   <- model_dt[SITE_ID == test_site]
      xvars_ok  <- setdiff(names(model_dt), c("SITE_ID", "YEAR", resp))

      train_cc <- train_dt[complete.cases(train_dt[, c(resp, xvars_ok), with = FALSE])]
      test_cc  <- test_dt[complete.cases(test_dt[, ..xvars_ok])]

      if (nrow(train_cc) < 10 || nrow(test_cc) == 0) next

      # Train ranger model
      rf <- ranger(
        x = train_cc[, ..xvars_ok],
        y = train_cc[[resp]],
        num.trees = N_TREES,
        seed = SEED,
        respect.unordered.factors = "order"
      )

      # Save model
      model_file <- file.path(output_base, sprintf("RF_model_%s_%s.rds", model_id, resp))
      saveRDS(rf, model_file)

      # Get predictions
      pred <- predict(rf, data = test_cc[, ..xvars_ok])$predictions

      fold_preds <- rbind(fold_preds, data.table(
        model = model_id,
        response = resp,
        SITE_ID = test_site,
        YEAR = test_cc$YEAR,
        observed = test_cc[[resp]],
        predicted = pred
      ))
    }

    if (nrow(fold_preds) > 0) {
      pred_results <- rbind(pred_results, fold_preds)

      # Calculate metrics
      rmse <- sqrt(mean((fold_preds$predicted - fold_preds$observed)^2, na.rm = TRUE))
      mae <- mean(abs(fold_preds$predicted - fold_preds$observed), na.rm = TRUE)
      ss_res <- sum((fold_preds$observed - fold_preds$predicted)^2, na.rm = TRUE)
      ss_tot <- sum((fold_preds$observed - mean(fold_preds$observed, na.rm = TRUE))^2, na.rm = TRUE)
      r2 <- 1 - (ss_res / ss_tot)

      metric_results <- rbind(metric_results, data.table(
        model = model_id,
        response = resp,
        n_predictors = length(predictors),
        n_pairs = nrow(fold_preds),
        RMSE = rmse,
        MAE = mae,
        R2 = r2
      ))
    }
  }
}

# ============================================================================
# Save outputs
# ============================================================================

cat("\nSaving outputs...\n")

if (nrow(pred_results) > 0) {
  pred_file <- file.path(output_base, "RF_predictions_LOSO.csv")
  fwrite(pred_results, pred_file)
  cat(sprintf("✓ %s (%d rows)\n", pred_file, nrow(pred_results)))
}

if (nrow(metric_results) > 0) {
  metric_file <- file.path(output_base, "RF_metrics_LOSO.csv")
  fwrite(metric_results, metric_file)
  cat(sprintf("✓ %s (%d rows)\n", metric_file, nrow(metric_results)))
}

cat("\n", strrep("=", 80), "\n")
cat("✅ V10 RF TRAINING COMPLETE\n")
cat("Models saved in: ", output_base, "\n")
cat(strrep("=", 80), "\n\n")

#!/usr/bin/env Rscript
# RF LOSO Cross-Validation for All 8 Model Types
# M01-M04: No memory
# M05-M08: With EFP memory (raw or anomaly)
# Runs for each response variable × benchmark (B1/B2)

library(data.table)
library(randomForest)
library(parallel)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('RF LOSO CROSS-VALIDATION - ALL MODELS\n')
cat('====================================================================\n\n')

# Setup
response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')
benchmarks <- c('B1', 'B2')
memory_types <- c('raw', 'anom')  # raw or anomaly
n_cores <- 8

cat(sprintf('Responses: %d\n', length(response_vars)))
cat(sprintf('Benchmarks: %d\n', length(benchmarks)))
cat(sprintf('Memory types: %d (for M05-M08)\n', length(memory_types)))
cat(sprintf('Total model configurations: %d\n\n', length(response_vars) * length(benchmarks) * 2 + length(response_vars) * length(benchmarks)))

# Model configurations
models <- data.table(
  model_id = c('M01', 'M02', 'M03', 'M04', 'M05', 'M06', 'M07', 'M08'),
  model_name = c(
    'Climate only',
    'Climate + Disturbance',
    'Climate + Traits',
    'Climate + Traits + Disturbance',
    'Climate + EFP Memory',
    'Climate + EFP Memory + Disturbance',
    'Climate + Traits + EFP Memory',
    'Climate + Traits + EFP Memory + Disturbance'
  ),
  has_memory = c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE)
)

cat('Models:\n')
print(models)
cat('\n')

# Function to get predictor columns
get_predictors <- function(df, model_id, response_var, memory_type = NULL) {

  # Climate/Meteo: TA, VPD, P, SW_IN at mean/p05/p95
  climate_cols <- grep('^(TA_|VPD_|P_|SW_IN_)', names(df), value=TRUE)

  # Traits: static traits
  trait_cols <- grep('(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', names(df), value=TRUE)

  # Disturbance: deadwood, mortality, relative_disturbance, new_
  dist_cols <- grep('(deadwood|absolute_mortality|relative_disturbance|mortality_loss|mortality_stock|new_)', names(df), value=TRUE)

  # EFP Memory: lag columns for the same response variable
  if (!is.null(memory_type)) {
    if (memory_type == 'raw') {
      memory_cols <- grep(sprintf('^%s_lag', response_var), names(df), value=TRUE)
      memory_cols <- memory_cols[!grepl('_anom_', memory_cols)]
    } else {
      memory_cols <- grep(sprintf('^%s.*_anom_', response_var), names(df), value=TRUE)
    }
  } else {
    memory_cols <- c()
  }

  # Combine based on model
  predictors <- c()

  if (model_id %in% c('M01', 'M05', 'M07')) {  # C only or C+Memory
    predictors <- climate_cols
  }

  if (model_id %in% c('M02', 'M06')) {  # C+D or C+Memory+D
    predictors <- c(climate_cols, dist_cols)
  }

  if (model_id %in% c('M03', 'M07')) {  # C+T or C+T+Memory
    predictors <- c(climate_cols, trait_cols)
  }

  if (model_id == 'M04') {  # C+T+D
    predictors <- c(climate_cols, trait_cols, dist_cols)
  }

  if (model_id == 'M08') {  # C+T+D+Memory
    predictors <- c(climate_cols, trait_cols, dist_cols, memory_cols)
  }

  # Add memory for M05, M06, M07, M08 if applicable
  if (model_id %in% c('M05', 'M06', 'M07', 'M08') && !is.null(memory_type)) {
    predictors <- c(predictors, memory_cols)
  }

  # Handle model_id-specific logic
  if (model_id == 'M01') predictors <- climate_cols
  if (model_id == 'M02') predictors <- c(climate_cols, dist_cols)
  if (model_id == 'M03') predictors <- c(climate_cols, trait_cols)
  if (model_id == 'M04') predictors <- c(climate_cols, trait_cols, dist_cols)
  if (model_id == 'M05') predictors <- c(climate_cols, memory_cols)
  if (model_id == 'M06') predictors <- c(climate_cols, dist_cols, memory_cols)
  if (model_id == 'M07') predictors <- c(climate_cols, trait_cols, memory_cols)
  if (model_id == 'M08') predictors <- c(climate_cols, trait_cols, dist_cols, memory_cols)

  # Remove duplicates and missing columns
  predictors <- unique(predictors[predictors %in% names(df)])

  return(predictors)
}

# Function to run LOSO RF
run_loso_rf <- function(df, response_var, predictors, model_name) {

  sites <- unique(df$SITE_ID)
  n_sites <- length(sites)

  predictions <- data.table(
    SITE_ID = character(),
    YEAR = integer(),
    observed = numeric(),
    predicted = numeric(),
    residual = numeric()
  )

  metrics <- data.table(
    site = character(),
    n_train = integer(),
    n_test = integer(),
    rmse = numeric(),
    mae = numeric(),
    r2 = numeric()
  )

  cat(sprintf('  Running LOSO for %s (%s)...\n', response_var, model_name))

  for (i in 1:n_sites) {
    holdout_site <- sites[i]

    # Train/test split
    train_idx <- df$SITE_ID != holdout_site
    test_idx <- df$SITE_ID == holdout_site

    df_train <- df[train_idx]
    df_test <- df[test_idx]

    # Remove rows with NA in response or predictors
    train_complete <- complete.cases(df_train[, c(response_var, predictors), with=FALSE])
    test_complete <- complete.cases(df_test[, c(response_var, predictors), with=FALSE])

    df_train <- df_train[train_complete]
    df_test <- df_test[test_complete]

    if (nrow(df_train) == 0 || nrow(df_test) == 0) next

    # Train RF
    tryCatch({
      rf <- randomForest(
        formula = as.formula(paste(response_var, '~', paste(predictors, collapse=' + '))),
        data = df_train,
        ntree = 500,
        mtry = max(1, floor(sqrt(length(predictors)))),
        na.action = na.omit
      )

      # Predict on test
      pred <- predict(rf, df_test)
      obs <- df_test[[response_var]]

      # Store predictions
      predictions <- rbind(predictions, data.table(
        SITE_ID = df_test$SITE_ID,
        YEAR = df_test$YEAR,
        observed = obs,
        predicted = pred,
        residual = obs - pred
      ))

      # Calculate metrics for this site
      rmse <- sqrt(mean((obs - pred)^2, na.rm=TRUE))
      mae <- mean(abs(obs - pred), na.rm=TRUE)
      ss_res <- sum((obs - pred)^2)
      ss_tot <- sum((obs - mean(obs))^2)
      r2 <- 1 - (ss_res / ss_tot)

      metrics <- rbind(metrics, data.table(
        site = holdout_site,
        n_train = nrow(df_train),
        n_test = nrow(df_test),
        rmse = rmse,
        mae = mae,
        r2 = r2
      ))
    }, error = function(e) {
      cat(sprintf('    WARNING: Error for site %s: %s\n', holdout_site, e$message))
    })

    if (i %% 20 == 0) cat(sprintf('    Processed %d/%d sites\n', i, n_sites))
  }

  # Overall metrics
  overall_rmse <- sqrt(mean(predictions$residual^2, na.rm=TRUE))
  overall_mae <- mean(abs(predictions$residual), na.rm=TRUE)
  ss_res <- sum(predictions$residual^2)
  ss_tot <- sum((predictions$observed - mean(predictions$observed))^2)
  overall_r2 <- 1 - (ss_res / ss_tot)

  cat(sprintf('    Overall RMSE: %.4f, MAE: %.4f, R²: %.4f\n', overall_rmse, overall_mae, overall_r2))

  return(list(
    predictions = predictions,
    metrics = metrics,
    overall_rmse = overall_rmse,
    overall_mae = overall_mae,
    overall_r2 = overall_r2,
    n_predictors = length(predictors)
  ))
}

# Main execution
cat('Starting RF training...\n\n')

results_summary <- data.table()

for (benchmark in benchmarks) {
  cat(sprintf('BENCHMARK: %s\n', benchmark))
  cat(paste(rep('=', 60), collapse=''), '\n\n')

  for (response_var in response_vars) {
    cat(sprintf('Response: %s\n', response_var))

    # Load data
    data_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_%s_%s.csv', benchmark, response_var)
    df <- fread(data_file)

    cat(sprintf('  Loaded: %d rows × %d columns\n\n', nrow(df), ncol(df)))

    # M01-M04 (no memory)
    for (model_row in 1:4) {
      model_id <- models$model_id[model_row]
      model_name <- models$model_name[model_row]

      predictors <- get_predictors(df, model_id, response_var)

      result <- run_loso_rf(df, response_var, predictors, model_name)

      results_summary <- rbind(results_summary, data.table(
        benchmark = benchmark,
        response = response_var,
        model = model_id,
        n_predictors = result$n_predictors,
        n_predictions = nrow(result$predictions),
        rmse = result$overall_rmse,
        mae = result$overall_mae,
        r2 = result$overall_r2
      ))

      cat('\n')
    }

    # M05-M08 (with memory)
    for (memory_type in memory_types) {
      for (model_row in 5:8) {
        model_id <- models$model_id[model_row]
        model_name <- models$model_name[model_row]

        predictors <- get_predictors(df, model_id, response_var, memory_type)

        result <- run_loso_rf(df, response_var, predictors, model_name)

        results_summary <- rbind(results_summary, data.table(
          benchmark = benchmark,
          response = response_var,
          model = sprintf('%s_%s', model_id, memory_type),
          n_predictors = result$n_predictors,
          n_predictions = nrow(result$predictions),
          rmse = result$overall_rmse,
          mae = result$overall_mae,
          r2 = result$overall_r2
        ))

        cat('\n')
      }
    }
  }
}

# Summary
cat('\n====================================================================\n')
cat('SUMMARY OF ALL MODELS\n')
cat('====================================================================\n\n')

print(results_summary[order(benchmark, response, model)])

# Save summary
out_file <- 'derived_tables/outputs_afterEGU_results/v10/RF_LOSO_results_summary.csv'
fwrite(results_summary, out_file)

cat(sprintf('\nResults saved: %s\n', out_file))
cat('✅ RF LOSO TRAINING COMPLETE\n\n')


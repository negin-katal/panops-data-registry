#!/usr/bin/env Rscript
# RF LOSO Cross-Validation for M01-M08
# Proper implementation with correct column naming

library(data.table)
library(randomForest)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('RF LOSO CROSS-VALIDATION - M01-M08 MODELS\n')
cat('====================================================================\n\n')

# Setup
response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')
benchmarks <- c('B1', 'B2')
memory_types <- c('raw', 'anom')

cat(sprintf('Responses: %d\n', length(response_vars)))
cat(sprintf('Benchmarks: %d (B1=lag1 only, B2=lag1+lag2)\n', length(benchmarks)))
cat(sprintf('Memory types: %d (raw or anomaly)\n\n', length(memory_types)))

# Helper: Run LOSO RF
run_loso_rf <- function(df, response_var, predictors_list, model_name, benchmark) {

  sites <- unique(df$SITE_ID)
  n_sites <- length(sites)

  predictions <- data.table()
  site_metrics <- data.table()

  cat(sprintf('  %s (%s): %d predictors', model_name, benchmark, length(predictors_list)))

  for (i in 1:n_sites) {
    holdout_site <- sites[i]

    train_idx <- df$SITE_ID != holdout_site
    test_idx <- df$SITE_ID == holdout_site

    df_train <- df[train_idx]
    df_test <- df[test_idx]

    # Check completeness
    train_complete <- complete.cases(df_train[, c(response_var, predictors_list), with=FALSE])
    test_complete <- complete.cases(df_test[, c(response_var, predictors_list), with=FALSE])

    df_train <- df_train[train_complete]
    df_test <- df_test[test_complete]

    if (nrow(df_train) < 10 || nrow(df_test) == 0) {
      next
    }

    tryCatch({
      rf <- randomForest(
        x = df_train[, predictors_list, with=FALSE],
        y = df_train[[response_var]],
        ntree = 300,
        mtry = floor(sqrt(length(predictors_list))),
        na.action = na.omit
      )

      pred <- predict(rf, df_test[, predictors_list, with=FALSE])
      obs <- df_test[[response_var]]

      predictions <- rbind(predictions, data.table(
        SITE_ID = df_test$SITE_ID,
        YEAR = df_test$YEAR,
        observed = obs,
        predicted = pred,
        residual = obs - pred
      ))

      rmse <- sqrt(mean((obs - pred)^2, na.rm=TRUE))
      mae <- mean(abs(obs - pred), na.rm=TRUE)
      r2 <- 1 - (sum((obs - pred)^2) / sum((obs - mean(obs))^2))

      site_metrics <- rbind(site_metrics, data.table(
        site = holdout_site,
        rmse = rmse,
        mae = mae,
        r2 = r2
      ))

    }, error = function(e) {
      # Silent
    })
  }

  if (nrow(predictions) == 0) {
    cat(' - NO PREDICTIONS\n')
    return(NULL)
  }

  overall_rmse <- sqrt(mean(predictions$residual^2, na.rm=TRUE))
  overall_mae <- mean(abs(predictions$residual), na.rm=TRUE)
  overall_r2 <- 1 - (sum(predictions$residual^2) / sum((predictions$observed - mean(predictions$observed))^2))

  cat(sprintf(' → RMSE=%.3f, R²=%.3f\n', overall_rmse, overall_r2))

  return(list(
    predictions = predictions,
    rmse = overall_rmse,
    mae = overall_mae,
    r2 = overall_r2,
    n_pred = nrow(predictions)
  ))
}

# Main loop
results_summary <- data.table()

for (benchmark in benchmarks) {
  cat(sprintf('\n%s\n', toupper(benchmark)))
  cat(paste(rep('=', 60), collapse=''), '\n\n')

  for (response_var in response_vars) {
    cat(sprintf('%s:\n', response_var))

    # Load data
    data_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_%s_%s.csv', benchmark, response_var)
    if (!file.exists(data_file)) {
      cat(sprintf('  File not found: %s\n', data_file))
      next
    }

    df <- fread(data_file)

    # Define predictor columns
    climate_cols <- grep('^lag[12]_M', names(df), value=TRUE)
    dist_cols <- grep('(absolute_mortality|relative_mortality|new_|relative_disturbance)', names(df), value=TRUE)
    # Keep only non-lag2 for B1
    if (benchmark == 'B1') {
      dist_cols <- dist_cols[!grepl('_lag2', dist_cols)]
      climate_cols <- climate_cols[!grepl('^lag2_', climate_cols)]
    }

    trait_cols <- grep('(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', names(df), value=TRUE)

    # M01: Climate only
    result <- run_loso_rf(df, response_var, climate_cols, 'M01_Climate', benchmark)
    if (!is.null(result)) {
      results_summary <- rbind(results_summary, data.table(
        benchmark = benchmark, response = response_var, model = 'M01',
        rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
    }

    # M02: Climate + Disturbance
    result <- run_loso_rf(df, response_var, c(climate_cols, dist_cols), 'M02_C+D', benchmark)
    if (!is.null(result)) {
      results_summary <- rbind(results_summary, data.table(
        benchmark = benchmark, response = response_var, model = 'M02',
        rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
    }

    # M03: Climate + Traits
    result <- run_loso_rf(df, response_var, c(climate_cols, trait_cols), 'M03_C+T', benchmark)
    if (!is.null(result)) {
      results_summary <- rbind(results_summary, data.table(
        benchmark = benchmark, response = response_var, model = 'M03',
        rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
    }

    # M04: Climate + Traits + Disturbance
    result <- run_loso_rf(df, response_var, c(climate_cols, trait_cols, dist_cols), 'M04_C+T+D', benchmark)
    if (!is.null(result)) {
      results_summary <- rbind(results_summary, data.table(
        benchmark = benchmark, response = response_var, model = 'M04',
        rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
    }

    # M05-M08 with memory
    for (mem_type in memory_types) {
      # Get memory columns (only matching response variable)
      if (mem_type == 'raw') {
        memory_cols <- grep(sprintf('^%s_lag', response_var), names(df), value=TRUE)
        memory_cols <- memory_cols[!grepl('_anom_', memory_cols)]
      } else {
        memory_cols <- grep(sprintf('^%s.*_anom_lag', response_var), names(df), value=TRUE)
      }

      # For B1, keep only lag1
      if (benchmark == 'B1') {
        memory_cols <- memory_cols[!grepl('_lag2', memory_cols)]
      }

      if (length(memory_cols) == 0) next

      # M05: Climate + Memory
      result <- run_loso_rf(df, response_var, c(climate_cols, memory_cols), sprintf('M05_%s', mem_type), benchmark)
      if (!is.null(result)) {
        results_summary <- rbind(results_summary, data.table(
          benchmark = benchmark, response = response_var, model = sprintf('M05_%s', mem_type),
          rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
      }

      # M06: Climate + Memory + Disturbance
      result <- run_loso_rf(df, response_var, c(climate_cols, memory_cols, dist_cols), sprintf('M06_%s', mem_type), benchmark)
      if (!is.null(result)) {
        results_summary <- rbind(results_summary, data.table(
          benchmark = benchmark, response = response_var, model = sprintf('M06_%s', mem_type),
          rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
      }

      # M07: Climate + Traits + Memory
      result <- run_loso_rf(df, response_var, c(climate_cols, trait_cols, memory_cols), sprintf('M07_%s', mem_type), benchmark)
      if (!is.null(result)) {
        results_summary <- rbind(results_summary, data.table(
          benchmark = benchmark, response = response_var, model = sprintf('M07_%s', mem_type),
          rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
      }

      # M08: Climate + Traits + Disturbance + Memory
      result <- run_loso_rf(df, response_var, c(climate_cols, trait_cols, dist_cols, memory_cols), sprintf('M08_%s', mem_type), benchmark)
      if (!is.null(result)) {
        results_summary <- rbind(results_summary, data.table(
          benchmark = benchmark, response = response_var, model = sprintf('M08_%s', mem_type),
          rmse = result$rmse, mae = result$mae, r2 = result$r2, n = result$n_pred))
      }
    }

    cat('\n')
  }
}

# Save results
cat(paste(rep('=', 60), collapse=''), '\n')
cat('SUMMARY\n')
cat(paste(rep('=', 60), collapse=''), '\n\n')

print(results_summary[order(benchmark, response, model)])

out_file <- 'derived_tables/outputs_afterEGU_results/v10/RF_LOSO_results.csv'
fwrite(results_summary, out_file)

cat(sprintf('\n✅ Results saved: %s\n\n', out_file))


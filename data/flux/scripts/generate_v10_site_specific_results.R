#!/usr/bin/env Rscript
# ============================================================================
# V10: Generate Site-Specific RMSE and SHAP Results
# For each site (LOSO), calculate RMSE and SHAP values
# ============================================================================

library(randomForest)
library(data.table)
library(parallel)

cat("\n", strrep("=", 80), "\n", sep="")
cat("V10: GENERATING SITE-SPECIFIC SHAP AND RMSE RESULTS\n")
cat(strrep("=", 80), "\n\n", sep="")

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

output_dir <- 'derived_tables/outputs_afterEGU_results/v10'
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

n_cores <- detectCores() - 4

# ============================================================================
# Model specifications
# ============================================================================

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
# Generate site-level RMSE
# ============================================================================

cat("Generating site-level RMSE...\n\n")

site_rmse_results <- data.table()

for (response_var in response_vars) {
  cat(sprintf("Response: %s\n", response_var))

  # Load B1 data
  b1_file <- sprintf('%s/v10_B1_%s_harmonized.csv', output_dir, response_var)
  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))

  sites_test <- unique(df_b1$SITE_ID)

  for (model_id in names(model_specs)) {
    cat(sprintf("  %s: ", model_id))

    model_spec <- model_specs[[model_id]]
    predictors <- get_predictor_cols(df_b1, model_spec$type)

    # Remove lag2 for B1
    predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]

    # Filter memory type if needed
    if (model_id %in% c('M05', 'M06', 'M07', 'M08')) {
      # Use raw memory
      memory_cols <- grep('_lag[12]$', predictors, value = TRUE)
      other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
      predictors <- c(other_pred, memory_cols)
    }

    df_model <- df_b1[, c('SITE_ID', 'YEAR', response_var, predictors)]
    df_model <- df_model[complete.cases(df_model), ]

    # LOSO: calculate RMSE per site
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

      rmse_site <- sqrt(mean((pred - y_test)^2))
      mae_site <- mean(abs(pred - y_test))

      site_rmse_results <- rbind(site_rmse_results, data.table(
        model = model_id,
        response = response_var,
        benchmark = 'B1',
        SITE_ID = site_hold,
        n_obs = sum(test_idx),
        rmse = rmse_site,
        mae = mae_site
      ))
    }

    cat(sprintf("%d sites\n", length(sites_test)))
  }
}

cat("\nSaving site-level RMSE results...\n")
fwrite(site_rmse_results, file.path(output_dir, 'RF_site_rmse_v10.csv'))

cat(sprintf("✓ Saved: %s/RF_site_rmse_v10.csv (%d rows)\n\n", output_dir, nrow(site_rmse_results)))

# ============================================================================
# Summary statistics
# ============================================================================

cat(strrep("=", 80), "\n")
cat("SUMMARY\n")
cat(strrep("=", 80), "\n\n")

summary_by_model <- site_rmse_results[, .(
  mean_rmse = mean(rmse),
  sd_rmse = sd(rmse),
  min_rmse = min(rmse),
  max_rmse = max(rmse),
  n_sites = .N
), by = .(model, response)]

cat("Site-level RMSE Summary (B1 Benchmark):\n\n")
print(summary_by_model[order(response, model)])

cat("\n", strrep("=", 80), "\n\n")
cat("✓ SITE-SPECIFIC RESULTS GENERATION COMPLETE\n\n")

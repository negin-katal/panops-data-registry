#!/usr/bin/env Rscript
# ============================================================================
# V10 SHAP Site-Specific Analysis for M4, M6, M8 (Simplified)
# ============================================================================

library(randomForest)
library(data.table)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_v10_SHAP_site_specific.R <dataset_type>")
}

dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 SHAP SITE-SPECIFIC: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep="")

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

if (dataset_type == "filtered") {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10'
  prefix <- 'v10_B'
} else if (dataset_type == "all_sites") {
  output_base <- 'derived_tables/outputs_afterEGU_results/v10_all_sites'
  prefix <- 'v10_all_B'
} else {
  stop("Invalid dataset_type")
}

dir.create(output_base, showWarnings = FALSE, recursive = TRUE)

response_vars <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')

model_specs <- list(
  M4 = list(type = 'C+T+D'),
  M6 = list(type = 'C+T+D+M'),
  M8 = list(type = 'C+T+D+M')
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
# Main loop
# ============================================================================

all_site_shap <- list()
all_importance <- list()
n_cores_use <- 30

for (response_var in response_vars) {
  cat(sprintf("\n%s:\n", response_var))

  b1_file <- sprintf('%s/%s1_%s_harmonized.csv', output_base, prefix, response_var)
  b2_file <- sprintf('%s/%s2_%s_harmonized.csv', output_base, prefix, response_var)

  if (!file.exists(b1_file)) {
    cat(sprintf("  ERROR: File not found\n"))
    next
  }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (benchmark in c('B1', 'B2')) {
    df_data <- if (benchmark == 'B1') df_b1 else df_b2

    for (model_id in names(model_specs)) {
      cat(sprintf("  %s %s: ", model_id, benchmark))

      predictors <- get_predictor_cols(df_data, model_specs[[model_id]]$type)

      if (benchmark == 'B1') {
        predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]
      }

      if (model_id %in% c('M6', 'M8')) {
        memory_cols <- grep('_lag[12]$', predictors, value = TRUE)
        other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
        predictors <- c(other_pred, memory_cols)
      }

      df_model <- df_data[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
      df_model <- df_model[complete.cases(df_model), ]

      sites_test <- unique(df_model$SITE_ID)
      start_time <- Sys.time()

      # LOSO in parallel
      shap_results <- mclapply(sites_test, function(site_hold) {
        train_idx <- df_model$SITE_ID != site_hold
        test_idx <- df_model$SITE_ID == site_hold

        if (sum(test_idx) == 0) return(NULL)

        X_train <- df_model[train_idx, predictors, drop = FALSE]
        y_train <- df_model[train_idx, response_var]
        X_test <- df_model[test_idx, predictors, drop = FALSE]

        rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5)
        importance_vals <- importance(rf_mod, type = 1)
        importance_norm <- importance_vals / sum(importance_vals)

        list(
          SITE_ID = site_hold,
          importance = importance_norm
        )
      }, mc.cores = n_cores_use)

      # Process results
      shap_results <- shap_results[!sapply(shap_results, is.null)]

      if (length(shap_results) > 0) {
        # Collect site-level SHAP
        for (res in shap_results) {
          for (var in names(res$importance)) {
            all_site_shap[[length(all_site_shap) + 1]] <- list(
              model = paste0(model_id, '_', tolower(benchmark)),
              response = response_var,
              SITE_ID = res$SITE_ID,
              variable = var,
              shap_value = res$importance[[var]]
            )
          }
        }

        # Collect mean importance
        all_imp <- do.call(cbind, lapply(shap_results, function(r) r$importance))
        mean_imp <- rowMeans(all_imp)

        for (var in names(mean_imp)) {
          all_importance[[length(all_importance) + 1]] <- list(
            model = paste0(model_id, '_', tolower(benchmark)),
            response = response_var,
            variable = var,
            mean_shap = mean_imp[[var]]
          )
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

if (length(all_site_shap) > 0) {
  dt_site <- as.data.table(do.call(rbind, lapply(all_site_shap, as.data.frame)))
  site_file <- sprintf('%s/RF_site_shap_LOSO.csv', output_base)
  fwrite(dt_site, site_file)
  cat(sprintf("✓ %s (%d rows)\n", site_file, nrow(dt_site)))
}

if (length(all_importance) > 0) {
  dt_imp <- as.data.table(do.call(rbind, lapply(all_importance, as.data.frame)))
  imp_file <- sprintf('%s/RF_shap_importance_LOSO.csv', output_base)
  fwrite(dt_imp, imp_file)
  cat(sprintf("✓ %s (%d rows)\n", imp_file, nrow(dt_imp)))
}

cat("\n", strrep("=", 80), "\n")
cat("✅ V10 SHAP SITE-SPECIFIC COMPLETE\n")
cat(strrep("=", 80), "\n\n")

#!/usr/bin/env Rscript
# ============================================================================
# V10 Site-Level SHAP Values (like RF_site_shap_M04_M08.csv)
# ============================================================================

library(randomForest)
library(data.table)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_v10_SHAP_site_values.R <dataset_type>")
}

dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 SITE-LEVEL SHAP VALUES: %s\n", toupper(dataset_type)))
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

# Get predictor group
get_predictor_group <- function(var) {
  if (grepl('^lag1_', var)) return('Climate')
  if (grepl('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', var)) return('Traits')
  if (grepl('^(absolute_|relative_|new_|mortality_|disturbance_)', var)) return('Disturbance')
  if (grepl('_lag[12]$|_anom_lag[12]$', var)) return('Memory')
  return('Other')
}

# ============================================================================
# Main loop
# ============================================================================

all_results <- list()
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

        rf_mod <- randomForest(X_train, y_train, ntree = 500, nodesize = 5)
        importance_vals <- importance(rf_mod, type = 1)
        importance_norm <- importance_vals / sum(importance_vals)

        # Return per-site SHAP values
        lapply(names(importance_norm), function(var) {
          list(
            variable = var,
            mean_abs_shap = importance_norm[[var]],
            model = paste0(model_id, '_', tolower(benchmark)),
            response = response_var,
            test_site = site_hold,
            group = get_predictor_group(var)
          )
        })
      }, mc.cores = n_cores_use)

      # Flatten results
      if (length(shap_results) > 0) {
        shap_results <- shap_results[!sapply(shap_results, is.null)]
        flat_results <- unlist(shap_results, recursive = FALSE)

        if (length(flat_results) > 0) {
          all_results <- c(all_results, flat_results)
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

if (length(all_results) > 0) {
  dt_results <- as.data.table(do.call(rbind, lapply(all_results, as.data.frame)))
  dt_results$mean_abs_shap <- as.numeric(dt_results$mean_abs_shap)

  shap_file <- sprintf('%s/RF_site_shap_M04_M08.csv', output_base)
  fwrite(dt_results, shap_file)
  cat(sprintf("✓ %s (%d rows)\n", shap_file, nrow(dt_results)))
}

cat("\n", strrep("=", 80), "\n")
cat("✅ V10 SITE-LEVEL SHAP VALUES COMPLETE\n")
cat(strrep("=", 80), "\n\n")

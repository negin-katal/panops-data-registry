#!/usr/bin/env Rscript
# ============================================================================
# V10 Extract TreeSHAP from Saved Ranger Models
# Loads saved ranger models and computes SHAP values using treeshap
# ============================================================================

library(data.table)
library(ranger)
library(treeshap)
library(parallel)

N_CORES <- 60  # per-site LOSO SHAP is embarrassingly parallel

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_v10_extract_SHAP_from_ranger.R <dataset_type>")
}

dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 TREESHAP EXTRACTION FROM RANGER: %s\n", toupper(dataset_type)))
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

# ============================================================================
# Predictor group mapping
# ============================================================================

get_predictor_group <- function(var) {
  if (grepl('^lag1_|^lag2_', var)) return('Climate')
  if (grepl('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', var)) return('Traits')
  if (grepl('^(absolute_|relative_|new_|mortality_|disturbance_)', var)) return('Disturbance')
  if (grepl('_lag[12]$|_anom_lag[12]$', var)) return('Memory')
  return('Other')
}

# ============================================================================
# Main extraction loop
# ============================================================================

RESPONSE_VARS <- c('GPPsat', 'NEPmax', 'ETmax', 'uWUE', 'WUE')

shap_results <- list()

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))

  # Read from original v10 data directories
  if (dataset_type == "filtered") {
    b1_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_B1_%s_harmonized.csv', resp)
    b2_file <- sprintf('derived_tables/outputs_afterEGU_results/v10/v10_B2_%s_harmonized.csv', resp)
  } else {
    b1_file <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_%s_harmonized.csv', resp)
    b2_file <- sprintf('derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B2_%s_harmonized.csv', resp)
  }

  if (!file.exists(b1_file)) {
    cat(sprintf("  ERROR: File not found\n"))
    next
  }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  # Get only M4, M6_raw, M6_anom, M8_raw, M8_anom models
  model_pattern <- sprintf("RF_model_(M4_|M6_(raw|anom)_|M8_(raw|anom)_).*_%s\\.rds$", resp)
  all_model_files <- list.files(output_base, pattern = sprintf("RF_model_.*_%s\\.rds$", resp), full.names = TRUE)
  model_files <- grep(model_pattern, all_model_files, perl = TRUE, value = TRUE)

  for (model_file in model_files) {
    # Extract model info from filename
    basename <- basename(model_file)
    model_id <- sub(sprintf("RF_model_(.*)_%s\\.rds$", resp), "\\1", basename)
    window <- if (grepl('12m$', model_id)) '12m' else '24m'
    benchmark <- if (window == '12m') 'B1' else 'B2'

    df_data <- if (benchmark == 'B1') df_b1 else df_b2

    cat(sprintf("  %s %s: ", model_id, benchmark))

    # Load model
    rf_mod <- tryCatch({
      readRDS(model_file)
    }, error = function(e) {
      cat(sprintf("ERROR loading model\n"))
      NULL
    })

    if (is.null(rf_mod)) next

    # Get predictors used in training
    xvars <- rf_mod$forest$independent.variable.names

    # Prepare data
    df_model <- df_data[, c('SITE_ID', 'YEAR', resp, xvars), drop = FALSE]
    df_model <- df_model[complete.cases(df_model), ]
    sites_test <- unique(df_model$SITE_ID)

    fold_shap <- mclapply(seq_along(sites_test), function(i) {
      test_site <- sites_test[i]
      train_dt <- as.data.table(df_model[df_model$SITE_ID != test_site, ])
      test_dt <- as.data.table(df_model[df_model$SITE_ID == test_site, ])

      if (nrow(test_dt) == 0) return(NULL)

      # Compute TreeSHAP
      shap_result <- tryCatch({
        unified <- ranger.unify(rf_mod, as.data.frame(train_dt[, ..xvars]))
        treeshap(unified, as.data.frame(test_dt[, ..xvars]), verbose = FALSE)
      }, error = function(e) NULL)

      if (is.null(shap_result)) return(NULL)

      # Extract mean absolute SHAP
      shap_mat <- as.data.table(shap_result$shaps)
      mean_abs_shap <- shap_mat[, lapply(.SD, function(x) mean(abs(x), na.rm = TRUE))]
      shap_long <- melt(mean_abs_shap,
                        measure.vars = names(mean_abs_shap),
                        variable.name = "variable",
                        value.name = "mean_abs_shap")
      shap_long[, `:=`(model = model_id, response = resp, test_site = test_site)]
      shap_long
    }, mc.cores = N_CORES)

    if (length(fold_shap) > 0) {
      shap_results[[length(shap_results) + 1]] <- rbindlist(fold_shap, fill = TRUE)
      cat(sprintf("OK\n"))
    } else {
      cat(sprintf("no results\n"))
    }
  }
}

# ============================================================================
# Save results
# ============================================================================

cat("\nSaving SHAP results...\n")

if (length(shap_results) > 0) {
  shap_dt <- rbindlist(shap_results, fill = TRUE)
  shap_dt[, variable := as.character(variable)]

  # Add predictor groups
  shap_dt[, group := sapply(variable, get_predictor_group)]

  out_path <- file.path(output_base, "RF_site_shap_M04_M08.csv")
  fwrite(shap_dt, out_path)
  cat(sprintf("✓ %s (%d rows)\n", out_path, nrow(shap_dt)))
  cat(sprintf("  Sites: %d | Responses: %s\n",
              uniqueN(shap_dt$test_site),
              paste(unique(shap_dt$response), collapse=", ")))
} else {
  cat("ERROR: No SHAP results collected\n")
}

cat("\n", strrep("=", 80), "\n")
cat("✅ V10 TREESHAP EXTRACTION COMPLETE\n")
cat(strrep("=", 80), "\n\n")

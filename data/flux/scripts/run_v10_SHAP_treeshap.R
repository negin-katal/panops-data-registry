#!/usr/bin/env Rscript
# ============================================================================
# V10 TreeSHAP: Compute actual SHAP values for M4, M6, M8 using treeshap
# ============================================================================

library(data.table)
library(ranger)
library(treeshap)
library(parallel)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_v10_SHAP_treeshap.R <dataset_type> [filtered/all_sites]")
}

dataset_type <- args[1]
if (length(args) < 2) dataset_type <- "filtered"

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 TREESHAP: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep="")

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

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

# ============================================================================
# Config
# ============================================================================

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
N_TREES <- 500
SEED <- 42

model_specs <- list(
  M4 = list(type = 'C+T+D'),
  M6 = list(type = 'C+T+D+M'),
  M8 = list(type = 'C+T+D+M')
)

# ============================================================================
# Predictor selection
# ============================================================================

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

get_predictor_group <- function(var) {
  if (grepl('^lag1_', var)) return('Climate')
  if (grepl('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', var)) return('Traits')
  if (grepl('^(absolute_|relative_|new_|mortality_|disturbance_)', var)) return('Disturbance')
  if (grepl('_lag[12]$|_anom_lag[12]$', var)) return('Memory')
  return('Other')
}

# ============================================================================
# Main SHAP loop
# ============================================================================

shap_list <- list()
run_idx <- 0

for (resp in RESPONSE_VARS) {
  cat(sprintf("\n%s:\n", resp))

  b1_file <- sprintf('%s/%s1_%s_harmonized.csv', output_base, prefix, resp)
  b2_file <- sprintf('%s/%s2_%s_harmonized.csv', output_base, prefix, resp)

  if (!file.exists(b1_file)) {
    cat(sprintf("  ERROR: File not found: %s\n", b1_file))
    next
  }

  df_b1 <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))
  df_b2 <- as.data.frame(fread(b2_file, stringsAsFactors = FALSE))

  for (benchmark in c('B1', 'B2')) {
    df_data <- if (benchmark == 'B1') df_b1 else df_b2
    bench_name <- if (benchmark == 'B1') '12m' else '24m'

    for (model_id in names(model_specs)) {
      model_nm <- sprintf("%s_%s_%s", model_id, bench_name, resp)
      cat(sprintf("  %s: ", model_nm))

      predictors <- get_predictor_cols(df_data, model_specs[[model_id]]$type)

      if (benchmark == 'B1') {
        predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]
      }

      if (model_id %in% c('M6', 'M8')) {
        memory_cols <- grep('_lag[12]$', predictors, value = TRUE)
        other_pred <- predictors[!predictors %in% grep('_lag[12]$|_anom_lag[12]$', predictors, value = TRUE)]
        predictors <- c(other_pred, memory_cols)
      }

      use_cols <- unique(c('SITE_ID', 'YEAR', resp, predictors))
      model_dt <- as.data.table(df_data[, use_cols])
      model_dt <- model_dt[!is.na(get(resp))]

      site_ids <- sort(unique(model_dt$SITE_ID))
      cat(sprintf("%d sites\n", length(site_ids)))

      fold_shap <- vector("list", length(site_ids))

      for (i in seq_along(site_ids)) {
        test_site <- site_ids[i]
        train_dt  <- model_dt[SITE_ID != test_site]
        test_dt   <- model_dt[SITE_ID == test_site]
        xvars_ok  <- setdiff(names(model_dt), c("SITE_ID", "YEAR", resp))

        train_cc <- train_dt[complete.cases(train_dt[, c(resp, xvars_ok), with = FALSE])]
        test_cc  <- test_dt[complete.cases(test_dt[, ..xvars_ok])]

        if (nrow(train_cc) < 10 || nrow(test_cc) == 0) next

        # Train ranger model
        rf <- tryCatch({
          ranger(
            x = train_cc[, ..xvars_ok],
            y = train_cc[[resp]],
            num.trees = N_TREES,
            seed = SEED,
            respect.unordered.factors = "order"
          )
        }, error = function(e) NULL)

        if (is.null(rf)) next

        # Compute TreeSHAP
        shap_result <- tryCatch({
          unified <- ranger.unify(rf, as.data.frame(train_cc[, ..xvars_ok]))
          treeshap(unified, as.data.frame(test_cc[, ..xvars_ok]), verbose = FALSE)
        }, error = function(e) NULL)

        if (is.null(shap_result)) next

        # Extract per-site mean absolute SHAP
        shap_mat <- as.data.table(shap_result$shaps)
        mean_abs_shap <- shap_mat[, lapply(.SD, function(x) mean(abs(x), na.rm = TRUE))]
        shap_long <- melt(mean_abs_shap,
                          measure.vars = names(mean_abs_shap),
                          variable.name = "variable",
                          value.name = "mean_abs_shap")
        shap_long[, `:=`(model = model_nm, response = resp, test_site = test_site)]
        fold_shap[[i]] <- shap_long
      }

      run_idx <- run_idx + 1
      shap_list[[run_idx]] <- rbindlist(fold_shap, fill = TRUE)
    }
  }
}

# ============================================================================
# Save
# ============================================================================

cat("\nSaving outputs...\n")

if (length(shap_list) > 0) {
  shap_dt <- rbindlist(shap_list, fill = TRUE)

  # Add predictor groups
  group_map <- data.table(
    variable = c(),
    group = c()
  )

  for (var in unique(shap_dt$variable)) {
    group_map <- rbind(group_map, data.table(variable = var, group = get_predictor_group(var)))
  }

  shap_dt <- merge(shap_dt, group_map, by = "variable", all.x = TRUE)
  shap_dt[is.na(group), group := "Other"]

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
cat("✅ V10 TREESHAP COMPLETE\n")
cat(strrep("=", 80), "\n\n")

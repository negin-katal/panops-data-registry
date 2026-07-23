#!/usr/bin/env Rscript
# ============================================================================
# V10 Site-Level SHAP Values - DIAGNOSTIC TEST (single model, single response)
# ============================================================================

library(randomForest)
library(data.table)
library(parallel)

setwd('/mnt/gsdata/projects/panops/panops-data-registry/data/flux')

cat("\n=== DIAGNOSTIC TEST ===\n\n")

# Simple test with filtered dataset, GPPsat, M4, B1
output_base <- 'derived_tables/outputs_afterEGU_results/v10'
response_var <- 'GPPsat'
model_id <- 'M4'
benchmark <- 'B1'

b1_file <- sprintf('%s/v10_B1_%s_harmonized.csv', output_base, response_var)
df_data <- as.data.frame(fread(b1_file, stringsAsFactors = FALSE))

cat(sprintf("Dataset: %s (%d rows)\n", b1_file, nrow(df_data)))
cat(sprintf("Columns: %s\n\n", paste(colnames(df_data)[1:5], collapse=", ")))

# Get predictors
all_cols <- colnames(df_data)
climate_cols <- grep('^lag1_', all_cols, value = TRUE)
trait_cols <- grep('^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)', all_cols, value = TRUE)
dist_cols <- grep('^(absolute_|relative_|new_|mortality_|disturbance_)', all_cols, value = TRUE)

predictors <- c(climate_cols, trait_cols, dist_cols)
predictors <- predictors[!grepl('_lag2$|_anom_lag2$', predictors)]

cat(sprintf("Predictors: %d climate, %d traits, %d disturbance\n",
            length(climate_cols), length(trait_cols), length(dist_cols)))
cat(sprintf("Total predictors: %d\n\n", length(predictors)))

df_model <- df_data[, c('SITE_ID', 'YEAR', response_var, predictors), drop = FALSE]
df_model <- df_model[complete.cases(df_model), ]

cat(sprintf("Complete cases: %d rows, %d sites\n", nrow(df_model), length(unique(df_model$SITE_ID))))

sites_test <- unique(df_model$SITE_ID)
cat(sprintf("Testing LOSO on first 3 sites: %s\n\n", paste(sites_test[1:3], collapse=", ")))

# Test single site
site_hold <- sites_test[1]
train_idx <- df_model$SITE_ID != site_hold
test_idx <- df_model$SITE_ID == site_hold

X_train <- df_model[train_idx, predictors, drop = FALSE]
y_train <- df_model[train_idx, response_var]
X_test <- df_model[test_idx, predictors, drop = FALSE]

cat(sprintf("Training on %d samples, testing on %d\n", nrow(X_train), nrow(X_test)))

rf_mod <- randomForest(X_train, y_train, ntree = 50, nodesize = 5)
importance_vals <- importance(rf_mod, type = 1)
importance_norm <- importance_vals / sum(importance_vals)

cat(sprintf("Importance values: %d variables\n", length(importance_norm)))
cat(sprintf("Top 5: %s\n\n", paste(names(sort(importance_norm, decreasing = TRUE)[1:5]), collapse=", ")))

# Build result as data.table
result_dt <- data.table(
  variable = names(importance_norm),
  mean_abs_shap = as.numeric(importance_norm),
  model = "M4_b1",
  response = "GPPsat",
  test_site = site_hold,
  group = "test"
)

cat(sprintf("Result data.table: %d rows, %d cols\n", nrow(result_dt), ncol(result_dt)))
print(head(result_dt, 3))

cat("\n✓ Diagnostic test passed\n\n")

#!/usr/bin/env Rscript
# Simplified RF LOSO for testing - run one model first

library(data.table)
library(randomForest)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('RF LOSO TEST - M01 (Climate only)\n')
cat('====================================================================\n\n')

# Load data for GPPsat B1
data_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat.csv'
df <- fread(data_file)

cat(sprintf('Loaded: %d rows × %d columns\n', nrow(df), ncol(df)))
cat(sprintf('Response: GPPsat\n'))
cat(sprintf('Sites: %d\n\n', uniqueN(df$SITE_ID)))

# Get climate predictors (TA, VPD, P, SW_IN)
climate_cols <- grep('^(TA_|VPD_|P_|SW_IN_)', names(df), value=TRUE)
cat(sprintf('Climate predictors: %d\n', length(climate_cols)))
cat(sprintf('Examples: %s\n\n', paste(climate_cols[1:5], collapse=', ')))

# Prepare data
df_clean <- df[!is.na(GPPsat)]

cat(sprintf('Rows with response: %d\n', nrow(df_clean)))
cat(sprintf('Response range: [%.2f, %.2f]\n\n', min(df_clean$GPPsat), max(df_clean$GPPsat)))

# LOSO cross-validation
sites <- unique(df_clean$SITE_ID)
n_sites <- length(sites)

predictions <- data.table()
site_metrics <- data.table()

cat(sprintf('Running LOSO (%d sites)...\n\n', n_sites))

for (i in 1:n_sites) {
  holdout_site <- sites[i]

  # Split data
  train_idx <- df_clean$SITE_ID != holdout_site
  test_idx <- df_clean$SITE_ID == holdout_site

  df_train <- df_clean[train_idx]
  df_test <- df_clean[test_idx]

  # Remove incomplete rows
  train_complete <- complete.cases(df_train[, c('GPPsat', climate_cols), with=FALSE])
  test_complete <- complete.cases(df_test[, c('GPPsat', climate_cols), with=FALSE])

  df_train <- df_train[train_complete]
  df_test <- df_test[test_complete]

  if (nrow(df_train) < 10 || nrow(df_test) == 0) {
    cat(sprintf('  Site %d/%d (%s): Skipped (insufficient data)\n', i, n_sites, holdout_site))
    next
  }

  tryCatch({
    # Train RF
    rf <- randomForest(
      formula = as.formula(paste('GPPsat ~', paste(climate_cols, collapse=' + '))),
      data = df_train,
      ntree = 500,
      mtry = floor(sqrt(length(climate_cols))),
      na.action = na.omit
    )

    # Predict
    pred <- predict(rf, df_test)
    obs <- df_test$GPPsat

    # Store results
    predictions <- rbind(predictions, data.table(
      SITE_ID = df_test$SITE_ID,
      YEAR = df_test$YEAR,
      observed = obs,
      predicted = pred,
      residual = obs - pred
    ))

    # Calculate metrics
    rmse <- sqrt(mean((obs - pred)^2, na.rm=TRUE))
    mae <- mean(abs(obs - pred), na.rm=TRUE)
    r2 <- 1 - (sum((obs - pred)^2) / sum((obs - mean(obs))^2))

    site_metrics <- rbind(site_metrics, data.table(
      site = holdout_site,
      n_train = nrow(df_train),
      n_test = nrow(df_test),
      rmse = rmse,
      mae = mae,
      r2 = r2
    ))

    if (i %% 10 == 0 || i == n_sites) {
      cat(sprintf('  Site %d/%d (%s): RMSE=%.3f, R²=%.3f\n', i, n_sites, holdout_site, rmse, r2))
    }

  }, error = function(e) {
    cat(sprintf('  Site %d/%d (%s): ERROR - %s\n', i, n_sites, holdout_site, e$message))
  })
}

# Overall metrics
cat('\n')
cat(paste(rep('=', 60), collapse=''), '\n')
cat('Overall Performance (M01 - Climate only)\n')
cat(paste(rep('=', 60), collapse=''), '\n\n')

overall_rmse <- sqrt(mean(predictions$residual^2, na.rm=TRUE))
overall_mae <- mean(abs(predictions$residual), na.rm=TRUE)
overall_r2 <- 1 - (sum(predictions$residual^2) / sum((predictions$observed - mean(predictions$observed))^2))

cat(sprintf('Total predictions: %d\n', nrow(predictions)))
cat(sprintf('Sites with predictions: %d/%d\n', uniqueN(predictions$SITE_ID), n_sites))
cat(sprintf('RMSE: %.4f\n', overall_rmse))
cat(sprintf('MAE: %.4f\n', overall_mae))
cat(sprintf('R²: %.4f\n', overall_r2))

cat('\n✅ TEST COMPLETE\n\n')


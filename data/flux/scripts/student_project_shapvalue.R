rm(list = ls())
## -------------------------------------------------------------
## 0. Packages
## -------------------------------------------------------------
# Install if needed:
# install.packages(c("data.table", "dplyr", "janitor", "ranger",
#                    "fastshap", "ggplot2", "purrr", "tidyr"))

library(data.table)
library(dplyr)
library(janitor)
library(ranger)
library(fastshap)
library(ggplot2)
library(purrr)
library(tidyr)
?fastshap::explain  
## -------------------------------------------------------------
## 1. Load and clean data
## -------------------------------------------------------------
traitmean_efp_Mirco <- fread("clean_data/traitmean_efp_Mirco.csv") |>
  clean_names()   # makes names like leaf_n_mass, leaf_delta_15_n, etc.

# Check column names once:
names(traitmean_efp_Mirco)

## -------------------------------------------------------------
## 2. Choose target EFP and predictor traits
## -------------------------------------------------------------
# Pick ONE ecosystem functional property to model:
target_var <- "ne_pmax"   # you can try "etmax", "gppsat", "uwue", etc.

# Choose a set of trait predictors (after clean_names())
# Adjust this vector if some names slightly differ in your data:
predictor_vars <- c(
  "sla",
  "leaf_n_mass",
  "leaf_width",
  "leaf_c_n_ratio",
  "leaf_p",
  "ssd",
  "leaf_thickness",
  "leaf_n_area",
  "leaf_dry_mass",
  "rooting_depth",
  "leaf_delta_15n"
)

# Optional: add climate drivers if you want
# predictor_vars <- c(predictor_vars, "tair", "vpd", "p")

## -------------------------------------------------------------
## 3. Prepare modelling dataset
## -------------------------------------------------------------
df_model <- traitmean_efp_Mirco |>
  select(site_id, pft, all_of(target_var), all_of(predictor_vars)) |>
  # remove rows with missing response or all-NA predictors
  filter(!is.na(.data[[target_var]]))

# Remove rows with too many NA predictors (optional threshold)
df_model <- df_model |>
  filter(rowSums(is.na(select(., all_of(predictor_vars)))) < length(predictor_vars))

# See how many sites per PFT
pft_counts <- df_model |>
  count(pft) |>
  arrange(desc(n))

print(pft_counts)

# Keep only PFT groups with >= 15 sites
min_n <- 15
selected_pfts <- pft_counts |>
  filter(n >= min_n) |>
  pull(pft)

selected_pfts
## -------------------------------------------------------------
## 4. Helper: function to fit RF + compute SHAP for one PFT
## -------------------------------------------------------------
fit_rf_and_shap_for_pft <- function(pft_name,
                                    data,
                                    target_var,
                                    predictor_vars,
                                    train_frac = 0.7,
                                    nsim_shap = 100) {
  message("Processing PFT: ", pft_name)
  
  dat <- data |>
    filter(pft == pft_name)
  
  if (nrow(dat) < 5) {
    warning("Too few rows for PFT = ", pft_name)
    return(NULL)
  }
  
  # Train/test split
  set.seed(123)
  n <- nrow(dat)
  train_idx <- sample(seq_len(n), size = floor(train_frac * n))
  train <- dat[train_idx, ]
  test  <- dat[-train_idx, ]
  
  # Build formula: target ~ predictor1 + predictor2 + ...
  formula_rf <- as.formula(
    paste(target_var, "~", paste(predictor_vars, collapse = " + "))
  )
  
  # Fit Random Forest
  rf_model <- ranger(
    formula = formula_rf,
    data = train,
    num.trees = 500,
    importance = "permutation",
    mtry = floor(sqrt(length(predictor_vars))), # typical choice
    min.node.size = 5
  )
  
  # Test performance
  y_test <- test[[target_var]]
  y_pred <- predict(rf_model, data = test)$predictions
  
  rmse <- sqrt(mean((y_pred - y_test)^2))
  r2   <- 1 - sum((y_pred - y_test)^2) / sum((mean(train[[target_var]]) - y_test)^2)
  
  # Define prediction wrapper for fastshap
  pred_fun <- function(object, newdata) {
    predict(object, data = newdata)$predictions
  }
  
  # Only the predictor matrix for SHAP
  x_test <- test |>
    select(all_of(predictor_vars))
  
  # Compute SHAP values (approximate)
  # Compute SHAP values (approximate)
  set.seed(123)
  shap_mat <- fastshap::explain(
    object = rf_model,
    X = x_test,
    pred_wrapper = pred_fun,
    nsim = nsim_shap
  )
  
  shap_df <- as.data.frame(shap_mat)
  shap_df$row_id <- seq_len(nrow(shap_df))
  
  # Long format with corresponding feature values
  shap_long <- shap_df |>
    pivot_longer(
      cols = all_of(predictor_vars),
      names_to = "feature",
      values_to = "shap_value"
    )
  
  feature_vals <- x_test |>
    mutate(row_id = dplyr::row_number()) |>
    pivot_longer(
      cols = all_of(predictor_vars),
      names_to = "feature",
      values_to = "feature_value"
    )
  
  shap_long <- shap_long |>
    left_join(feature_vals, by = c("row_id", "feature"))
  
  # A simple variable importance from SHAP
  shap_importance <- shap_long |>
    group_by(feature) |>
    summarise(mean_abs_shap = mean(abs(shap_value), na.rm = TRUE),
              .groups = "drop") |>
    arrange(desc(mean_abs_shap))
  
  list(
    pft             = pft_name,
    model           = rf_model,
    rmse            = rmse,
    r2              = r2,
    shap_long       = shap_long,
    shap_importance = shap_importance,
    test_data       = test
  )
}


## -------------------------------------------------------------
## 5. Run the function for all selected PFTs
## -------------------------------------------------------------
results_list <- map(
  selected_pfts,
  ~ fit_rf_and_shap_for_pft(
    pft_name       = .x,
    data           = df_model,
    target_var     = target_var,
    predictor_vars = predictor_vars,
    train_frac     = 0.7,
    nsim_shap      = 100  # can increase for smoother SHAP at higher cost
  )
)

names(results_list) <- selected_pfts

# Remove NULLs (in case)
results_list <- compact(results_list)

## -------------------------------------------------------------
## 6. Example: Inspect one PFT and plot SHAP
## -------------------------------------------------------------
# Pick one PFT to explore
chosen_pft <- selected_pfts[1]  # e.g. "ENF" or "DBF"
res <- results_list[[chosen_pft]]

cat("PFT:", res$pft, "\n")
cat("RMSE:", round(res$rmse, 3), "\n")
cat("R²:", round(res$r2, 3), "\n")

# View SHAP importance
res$shap_importance

## -------------------------------------------------------------
## 7. SHAP summary plot (violin / beeswarm style)
## -------------------------------------------------------------
shap_long <- res$shap_long

ggplot(shap_long, aes(
  x = reorder(feature, abs(shap_value), FUN = median),
  y = shap_value
)) +
  geom_violin(trim = TRUE) +
  geom_boxplot(width = 0.15, outlier.size = 0.5) +
  coord_flip() +
  labs(
    x = "Feature",
    y = "SHAP value",
    title = paste("SHAP summary for", target_var, "in PFT =", chosen_pft)
  ) +
  theme_bw()

## -------------------------------------------------------------
## 8. SHAP dependence plots for top 3 features
## -------------------------------------------------------------
top3_features <- res$shap_importance |>
  slice(1:3) |>
  pull(feature)

top3_features

# Loop over top3 and make scatter + smooth
for (feat in top3_features) {
  p <- shap_long |>
    filter(feature == feat) |>
    ggplot(aes(x = feature_value, y = shap_value)) +
    geom_point(alpha = 0.7) +
    geom_smooth(method = "loess", se = TRUE) +
    labs(
      x = feat,
      y = "SHAP value",
      title = paste("SHAP dependence:", feat,
                    "for", target_var, "in PFT =", chosen_pft)
    ) +
    theme_bw()
  
  print(p)
}

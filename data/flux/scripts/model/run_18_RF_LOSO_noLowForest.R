library(data.table)
library(ranger)

# =========================================================
# LEAVE-ONE-SITE-OUT RF — ALL LOW-FOREST SITES REMOVED
#
# Identical to run_18_RF_LOSO.R except ALL sites (any IGBP)
# whose mean forest cover (500 m buffer, averaged across all
# years) is < 20 % are excluded before model fitting.
#
# This extends the WET-only filter (RF_outputs_noWET/) to
# include low-forest DBF, ENF, OSH, CSH, SAV, WSA sites.
# Threshold: forest_mean_pct_500m site-mean < 20
# Output goes to RF_outputs_noLowForest/
# =========================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
cgs_file   <- "derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/RF_outputs_noLowForest"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE")
N_TREES       <- 500
SEED          <- 42

# =========================================================
# 1) Load and merge CGS
# =========================================================

dt  <- fread(model_file)
cgs <- fread(cgs_file)

if ("year" %in% names(cgs) && !"YEAR" %in% names(cgs)) setnames(cgs, "year", "YEAR")

cgs_keep <- c("SITE_ID", "YEAR", "CGS_weighted_doy", "CGS_midpoint_doy",
              "GS_start_doy", "GS_end_doy", "GS_length_days")
cgs_keep <- cgs_keep[cgs_keep %in% names(cgs)]
dt <- merge(dt, cgs[, ..cgs_keep], by = c("SITE_ID", "YEAR"), all.x = TRUE)

cat("Dataset (raw):", nrow(dt), "rows x", ncol(dt), "cols\n")
cat("Sites  (raw):", uniqueN(dt$SITE_ID), "\n")

# =========================================================
# FILTER: remove ALL sites (any IGBP) with mean forest
# cover (500 m buffer) < 20 % across all their site-years
# =========================================================

FOREST_COL    <- "forest_mean_pct_500m"
FOREST_THRESH <- 20.0

site_forest <- dt[, .(
  IGBP         = unique(IGBP)[1],
  mean_forest  = mean(get(FOREST_COL), na.rm = TRUE)
), by = SITE_ID]

sites_to_drop <- site_forest[mean_forest < FOREST_THRESH, SITE_ID]

cat(sprintf("\nAll sites with mean %s < %.0f%% → removed (%d sites):\n",
            FOREST_COL, FOREST_THRESH, length(sites_to_drop)))
print(site_forest[SITE_ID %in% sites_to_drop,
                  .(SITE_ID, IGBP, mean_forest = round(mean_forest, 1))
                  ][order(IGBP, mean_forest)])

dt <- dt[!(SITE_ID %in% sites_to_drop)]

cat(sprintf("\nDataset after filter: %d rows, %d sites\n",
            nrow(dt), uniqueN(dt$SITE_ID)))
cat("Years  :", min(dt$YEAR), "-", max(dt$YEAR), "\n")
cat("CGS available:", sum(!is.na(dt$CGS_weighted_doy)), "/", nrow(dt), "rows\n")

# =========================================================
# 2) Compute pre-CGS climate summaries for each year tier
# =========================================================

dt_rf <- copy(dt)

cgs_month_vec <- as.integer(ceiling(dt_rf$CGS_weighted_doy / (365.25 / 12)))
cgs_month_vec <- pmin(pmax(cgs_month_vec, 1L), 12L)
cgs_month_vec[is.na(cgs_month_vec)] <- 12L

climate_prefixes <- c(
  "TA_mean", "TA_p05", "TA_p95",
  "VPD_mean", "VPD_p05", "VPD_p95",
  "P_mean", "P_sum",
  "SW_IN_mean", "SW_IN_p05", "SW_IN_p95"
)

agg_months <- function(vals, is_sum) {
  if (all(is.na(vals))) return(NA_real_)
  if (is_sum) sum(vals, na.rm = TRUE) else mean(vals, na.rm = TRUE)
}

precgs_cols_created <- character(0)

get_month_mat <- function(prefix, lag_suffix) {
  mat <- matrix(NA_real_, nrow = nrow(dt_rf), ncol = 12)
  for (j in 1:12) {
    col <- sprintf("%s_M%02d%s", prefix, j, lag_suffix)
    if (col %in% names(dt_rf)) mat[, j] <- dt_rf[[col]]
  }
  mat
}

for (prefix in climate_prefixes) {
  is_sum_var <- grepl("_sum$", prefix)

  mat_cur  <- get_month_mat(prefix, "")
  mat_lag1 <- get_month_mat(prefix, "_lag1")
  mat_lag2 <- get_month_mat(prefix, "_lag2")

  # 12-month rolling window: (cgs_m+1:12 of T-1) + (1:cgs_m of T)
  new_12m <- paste0(prefix, "_CGS12m")
  dt_rf[[new_12m]] <- vapply(seq_len(nrow(dt_rf)), function(i) {
    m         <- cgs_month_vec[i]
    cur_vals  <- mat_cur[i,  1:m,          drop = TRUE]
    lag1_vals <- if (m < 12) mat_lag1[i, (m+1):12, drop = TRUE] else numeric(0)
    agg_months(c(lag1_vals, cur_vals), is_sum_var)
  }, numeric(1))
  precgs_cols_created <- c(precgs_cols_created, new_12m)

  # 24-month rolling window: (cgs_m+1:12 of T-2) + (1:12 of T-1) + (1:cgs_m of T)
  new_24m <- paste0(prefix, "_CGS24m")
  dt_rf[[new_24m]] <- vapply(seq_len(nrow(dt_rf)), function(i) {
    m         <- cgs_month_vec[i]
    cur_vals  <- mat_cur[i,  1:m,          drop = TRUE]
    lag1_vals <- mat_lag1[i, 1:12,         drop = TRUE]
    lag2_vals <- if (m < 12) mat_lag2[i, (m+1):12, drop = TRUE] else numeric(0)
    agg_months(c(lag2_vals, lag1_vals, cur_vals), is_sum_var)
  }, numeric(1))
  precgs_cols_created <- c(precgs_cols_created, new_24m)
}

cat("Rolling climate summary columns created:", length(precgs_cols_created), "\n")
cat("  12-month (CGS12m):", sum(grepl("_CGS12m$", precgs_cols_created)), "\n")
cat("  24-month (CGS24m):", sum(grepl("_CGS24m$", precgs_cols_created)), "\n")

# =========================================================
# 3) Define variable groups
# =========================================================

all_cols <- names(dt_rf)

meteo_12m <- grep("_CGS12m$", all_cols, value = TRUE)
meteo_24m <- grep("_CGS24m$", all_cols, value = TRUE)

dist_pattern <- paste0(
  "^(mortality_intensity_pct|deadwood_increase_sum_pp|",
  "deadwood_increase_area_frac|deadwood_increase_mean_pp|",
  "deadwood_mean_pct|loss_area_frac|loss_sum_pp|loss_mean_pp)_[0-9]+m"
)
dist_current <- grep(paste0(dist_pattern, "$"),      all_cols, value = TRUE)
dist_lag1    <- grep(paste0(dist_pattern, "_lag1$"), all_cols, value = TRUE)
dist_lag2    <- grep(paste0(dist_pattern, "_lag2$"), all_cols, value = TRUE)

dist_12m <- c(dist_current, dist_lag1)
dist_24m <- c(dist_current, dist_lag1, dist_lag2)

efp_mem_12m <- grep("_anom_lag1$",    all_cols, value = TRUE)
efp_mem_24m <- grep("_anom_lag[12]$", all_cols, value = TRUE)

trait_vars <- c(
  "gsmax_mean", "P12_mean", "P50_mean", "P88_mean", "rdmax_mean", "WUE_mean",
  "Leaf C", "Leaf N (mass)", "Leaf width", "Leaf C/N ratio", "Leaf P",
  "Stem conduit density", "Stem conduit diameter",
  "Leaf area (3114)", "SLA", "SSD", "Leaf thickness", "Leaf N (area)",
  "Leaf dry mass", "Rooting depth", "Leaf delta 15N"
)
trait_vars <- trait_vars[trait_vars %in% all_cols]

cat("\nVariable group sizes:\n")
cat(sprintf("  meteo_12m    : %d cols\n", length(meteo_12m)))
cat(sprintf("  meteo_24m    : %d cols\n", length(meteo_24m)))
cat(sprintf("  dist_12m     : %d  (%d current + %d lag1)\n",
            length(dist_12m), length(dist_current), length(dist_lag1)))
cat(sprintf("  dist_24m     : %d  (+ %d lag2)\n",
            length(dist_24m), length(dist_lag2)))
cat(sprintf("  efp_mem_12m  : %d  (lag1 anomalies)\n",      length(efp_mem_12m)))
cat(sprintf("  efp_mem_24m  : %d  (lag1+lag2 anomalies)\n", length(efp_mem_24m)))
cat(sprintf("  traits       : %d\n", length(trait_vars)))

writeLines(meteo_12m,   file.path(out_dir, "vars_meteo_12m.txt"))
writeLines(meteo_24m,   file.path(out_dir, "vars_meteo_24m.txt"))
writeLines(dist_12m,    file.path(out_dir, "vars_dist_12m.txt"))
writeLines(dist_24m,    file.path(out_dir, "vars_dist_24m.txt"))
writeLines(efp_mem_12m, file.path(out_dir, "vars_efp_mem_12m.txt"))
writeLines(efp_mem_24m, file.path(out_dir, "vars_efp_mem_24m.txt"))
writeLines(trait_vars,  file.path(out_dir, "vars_traits.txt"))

# =========================================================
# 4) Define predictor sets
# =========================================================

pred_sets <- list(
  M01_12m = meteo_12m,
  M01_24m = meteo_24m,
  M02_12m = c(meteo_12m, dist_12m),
  M02_24m = c(meteo_24m, dist_24m),
  M03_12m = c(meteo_12m, trait_vars),
  M03_24m = c(meteo_24m, trait_vars),
  M04_12m = c(meteo_12m, trait_vars, dist_12m),
  M04_24m = c(meteo_24m, trait_vars, dist_24m),
  M05_12m = c(meteo_12m, efp_mem_12m),
  M05_24m = c(meteo_24m, efp_mem_24m),
  M06_12m = c(meteo_12m, dist_12m, efp_mem_12m),
  M06_24m = c(meteo_24m, dist_24m, efp_mem_24m),
  M07_12m = c(meteo_12m, trait_vars, efp_mem_12m),
  M07_24m = c(meteo_24m, trait_vars, efp_mem_24m),
  M08_12m = c(meteo_12m, trait_vars, dist_12m, efp_mem_12m),
  M08_24m = c(meteo_24m, trait_vars, dist_24m, efp_mem_24m)
)

pred_sets <- lapply(pred_sets, function(x) unique(x[x %in% all_cols]))

cat("\nPredictor set sizes:\n")
for (nm in names(pred_sets))
  cat(sprintf("  %-10s  %d vars\n", nm, length(pred_sets[[nm]])))

# =========================================================
# 5) Build benchmark sets
#
# All models within a window tier are evaluated on the same
# site-years: the intersection of complete cases across ALL
# predictors used by any model in that tier.
#
# bench_12m = rows complete for every _12m predictor union
# bench_24m = rows complete for every _24m predictor union
# =========================================================

all_12m_vars <- unique(unlist(pred_sets[grep("_12m$", names(pred_sets))]))
all_24m_vars <- unique(unlist(pred_sets[grep("_24m$", names(pred_sets))]))

bench_12m_mask <- complete.cases(dt_rf[, ..all_12m_vars])
bench_24m_mask <- complete.cases(dt_rf[, ..all_24m_vars])

dt_bench_12m <- dt_rf[bench_12m_mask]
dt_bench_24m <- dt_rf[bench_24m_mask]

cat("\n--- Benchmark set sizes ---\n")
cat(sprintf("  12m benchmark: %d rows, %d sites\n",
            nrow(dt_bench_12m), uniqueN(dt_bench_12m$SITE_ID)))
cat(sprintf("  24m benchmark: %d rows, %d sites\n",
            nrow(dt_bench_24m), uniqueN(dt_bench_24m$SITE_ID)))

bench_summary <- data.table(
  benchmark    = c("12m", "24m"),
  n_rows       = c(nrow(dt_bench_12m), nrow(dt_bench_24m)),
  n_sites      = c(uniqueN(dt_bench_12m$SITE_ID), uniqueN(dt_bench_24m$SITE_ID)),
  years_range  = c(
    paste(min(dt_bench_12m$YEAR), max(dt_bench_12m$YEAR), sep = "-"),
    paste(min(dt_bench_24m$YEAR), max(dt_bench_24m$YEAR), sep = "-")
  )
)
print(bench_summary)
fwrite(bench_summary, file.path(out_dir, "benchmark_set_sizes.csv"))

# =========================================================
# 6) LOSO-RF function
# =========================================================

run_loso_rf <- function(data, response_var, predictor_vars, model_name,
                        num_trees = N_TREES, seed = SEED) {

  use_cols <- unique(c("SITE_ID", "YEAR", response_var, predictor_vars))
  use_cols <- use_cols[use_cols %in% names(data)]
  model_dt <- copy(data)[, ..use_cols]
  model_dt <- model_dt[!is.na(get(response_var))]

  site_ids  <- sort(unique(model_dt$SITE_ID))
  pred_list <- vector("list", length(site_ids))
  vimp_list <- vector("list", length(site_ids))

  for (i in seq_along(site_ids)) {
    test_site <- site_ids[i]
    cat(sprintf("[%s] fold %d/%d  site: %s\n",
                model_name, i, length(site_ids), test_site))

    train_dt <- model_dt[SITE_ID != test_site]
    test_dt  <- model_dt[SITE_ID == test_site]
    xvars    <- setdiff(names(model_dt), c("SITE_ID", "YEAR", response_var))

    train_cc <- train_dt[complete.cases(train_dt[, c(response_var, xvars), with = FALSE])]
    test_cc  <- test_dt[complete.cases(test_dt[, ..xvars])]

    base_pred <- data.table(
      model     = model_name,
      response  = response_var,
      SITE_ID   = test_site,
      YEAR      = test_dt$YEAR,
      observed  = as.numeric(test_dt[[response_var]]),
      predicted = NA_real_
    )

    if (nrow(train_cc) < 10 || nrow(test_cc) == 0) {
      pred_list[[i]] <- base_pred
      next
    }

    rf <- ranger(
      x                         = train_cc[, ..xvars],
      y                         = train_cc[[response_var]],
      num.trees                 = num_trees,
      importance                = "permutation",
      seed                      = seed,
      respect.unordered.factors = "order"
    )

    preds <- predict(rf, data = test_cc[, ..xvars])$predictions
    base_pred[YEAR %in% test_cc$YEAR, predicted := as.numeric(preds)]
    pred_list[[i]] <- base_pred

    vimp_list[[i]] <- data.table(
      model      = model_name,
      response   = response_var,
      variable   = names(rf$variable.importance),
      importance = as.numeric(rf$variable.importance)
    )
  }

  pred_dt <- rbindlist(pred_list, fill = TRUE)
  vimp_dt <- rbindlist(vimp_list, fill = TRUE)

  complete_pairs <- pred_dt[!is.na(observed) & !is.na(predicted)]
  rmse <- sqrt(mean((complete_pairs$observed - complete_pairs$predicted)^2))
  r2   <- if (nrow(complete_pairs) >= 2)
            cor(complete_pairs$observed, complete_pairs$predicted)^2
          else NA_real_

  metrics_dt <- data.table(
    model        = model_name,
    response     = response_var,
    n_predictors = length(predictor_vars),
    n_rows       = nrow(model_dt),
    n_sites      = uniqueN(model_dt$SITE_ID),
    n_pairs      = nrow(complete_pairs),
    RMSE         = rmse,
    R2           = r2
  )

  if (nrow(vimp_dt) == 0 || !all(c("model", "response", "variable") %in% names(vimp_dt))) {
    warning(sprintf("No variable importance computed for model: %s", model_name))
    vimp_mean <- data.table(model = model_name, response = response_var,
                            variable = NA_character_, mean_importance = NA_real_)
  } else {
    vimp_mean <- vimp_dt[, .(mean_importance = mean(importance, na.rm = TRUE)),
                         by = .(model, response, variable)]
    setorder(vimp_mean, -mean_importance)
  }

  list(metrics = metrics_dt, predictions = pred_dt, varimp = vimp_mean)
}

# =========================================================
# 7) Run all models on their benchmark set
# =========================================================

all_results <- list()

for (resp in RESPONSE_VARS) {
  cat("\n", strrep("=", 50), "\n", sep = "")
  cat("Response:", resp, "\n")
  cat(strrep("=", 50), "\n", sep = "")

  all_results[[resp]] <- lapply(names(pred_sets), function(ps) {
    bench_data <- if (grepl("_12m$", ps)) dt_bench_12m else dt_bench_24m
    run_loso_rf(
      data           = bench_data,
      response_var   = resp,
      predictor_vars = pred_sets[[ps]],
      model_name     = paste0(ps, "_", resp)
    )
  })
}

cat("\nAll models finished.\n")

# =========================================================
# 8) Collect and save outputs
# =========================================================

flatten <- function(field)
  rbindlist(lapply(all_results, function(r) rbindlist(lapply(r, `[[`, field), fill = TRUE)), fill = TRUE)

all_metrics     <- flatten("metrics")
all_predictions <- flatten("predictions")
all_varimp      <- flatten("varimp")

setorder(all_metrics, response, model)

fwrite(all_metrics,     file.path(out_dir, "RF_metrics_LOSO.csv"))
fwrite(all_predictions, file.path(out_dir, "RF_predictions_LOSO.csv"))
fwrite(all_varimp,      file.path(out_dir, "RF_varimp_LOSO.csv"))

cat("Saved to:", out_dir, "\n")

# =========================================================
# 9) Summary
# =========================================================

all_metrics[, window     := fifelse(grepl("_24m", model), "24m", "12m")]
all_metrics[, model_base := sub("_(12|24)m.*", "", model)]
all_metrics[, has_dist    := grepl("M02|M04|M06|M08", model_base)]
all_metrics[, has_traits  := grepl("M03|M04|M07|M08", model_base)]
all_metrics[, has_efp_mem := grepl("M05|M06|M07|M08", model_base)]

cat("\n--- Full results (all models on shared benchmark) ---\n")
print(all_metrics[, .(
  model, response, n_pairs,
  RMSE = round(RMSE, 4), R2 = round(R2, 3),
  window, has_traits, has_dist, has_efp_mem
)][order(response, model)])

cat("\n--- 12m vs 24m comparison (full model: M08) ---\n")
print(all_metrics[
  grepl("M08", model_base),
  .(model, response, n_pairs, RMSE = round(RMSE, 4), R2 = round(R2, 3), window)
][order(response, window)])

cat("\n--- Effect of adding disturbance (M01 vs M02, 12m) ---\n")
print(all_metrics[
  grepl("M01|M02", model_base) & window == "12m",
  .(model, response, RMSE = round(RMSE, 4), R2 = round(R2, 3))
][order(response, model)])

cat("\n--- Effect of adding EFP memory (M01 vs M05, 12m) ---\n")
print(all_metrics[
  grepl("M01|M05", model_base) & window == "12m",
  .(model, response, RMSE = round(RMSE, 4), R2 = round(R2, 3))
][order(response, model)])

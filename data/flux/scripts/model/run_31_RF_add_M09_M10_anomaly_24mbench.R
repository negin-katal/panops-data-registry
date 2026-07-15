library(data.table)
library(ranger)

# =========================================================
# LEAVE-ONE-SITE-OUT RF — ANOMALY EFP MEMORY
# v20: adds P_p05 / P_p95 monthly precipitation quantiles
# Bug-fixed: 31 sites with faulty mortality data excluded.
# =========================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
cgs_file   <- "derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

RESPONSE_VARS <- c("GPPsat", "NEPmax", "ETmax", "uWUE")
N_TREES       <- 500
SEED          <- 42

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# =========================================================
# 1) Load, merge CGS, exclude bug sites
# =========================================================

dt  <- fread(model_file)
cgs <- fread(cgs_file)

if ("year" %in% names(cgs) && !"YEAR" %in% names(cgs)) setnames(cgs, "year", "YEAR")

cgs_keep <- c("SITE_ID", "YEAR", "CGS_weighted_doy", "CGS_midpoint_doy",
              "GS_start_doy", "GS_end_doy", "GS_length_days")
cgs_keep <- cgs_keep[cgs_keep %in% names(cgs)]
dt <- merge(dt, cgs[, ..cgs_keep], by = c("SITE_ID", "YEAR"), all.x = TRUE)

n_before <- uniqueN(dt$SITE_ID)
dt <- dt[!SITE_ID %in% EXCLUDE_SITES]
n_after  <- uniqueN(dt$SITE_ID)
cat(sprintf("Excluded %d bug sites (%d -> %d sites)\n",
            n_before - n_after, n_before, n_after))

cat("Dataset:", nrow(dt), "rows x", ncol(dt), "cols\n")
cat("Sites  :", uniqueN(dt$SITE_ID), "\n")
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
  "P_mean", "P_sum", "P_p05", "P_p95",
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

  new_12m <- paste0(prefix, "_CGS12m")
  dt_rf[[new_12m]] <- vapply(seq_len(nrow(dt_rf)), function(i) {
    m         <- cgs_month_vec[i]
    cur_vals  <- mat_cur[i,  1:m,          drop = TRUE]
    lag1_vals <- if (m < 12) mat_lag1[i, (m+1):12, drop = TRUE] else numeric(0)
    agg_months(c(lag1_vals, cur_vals), is_sum_var)
  }, numeric(1))
  precgs_cols_created <- c(precgs_cols_created, new_12m)

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
cat(sprintf("  dist_12m     : %d\n", length(dist_12m)))
cat(sprintf("  dist_24m     : %d\n", length(dist_24m)))
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

# ============================================================
# NEW MODELS for this run:
#   M09 = Memory only (no Climate, no Traits, no Disturbance)
#   M10 = Memory + Disturbance (no Climate, no Traits)
#
# We still need the FULL predictor union (meteo/dist/efp_mem) to
# build the unified 24m benchmark identically to the original
# run_24 script, so all_12m_vars/all_24m_vars below still include
# M01-M08's predictors even though we only RUN M09/M10 here.
# ============================================================

pred_sets_full <- list(
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
  M08_24m = c(meteo_24m, trait_vars, dist_24m, efp_mem_24m),
  M09_12m = efp_mem_12m,
  M09_24m = efp_mem_24m,
  M10_12m = c(efp_mem_12m, dist_12m),
  M10_24m = c(efp_mem_24m, dist_24m)
)

pred_sets <- pred_sets_full[c("M09_12m", "M09_24m", "M10_12m", "M10_24m")]

pred_sets <- lapply(pred_sets, function(x) unique(x[x %in% all_cols]))

cat("\nPredictor set sizes:\n")
for (nm in names(pred_sets))
  cat(sprintf("  %-10s  %d vars\n", nm, length(pred_sets[[nm]])))

# =========================================================
# 5) Build benchmark sets
# =========================================================

all_12m_vars <- unique(unlist(pred_sets_full[grep("_12m$", names(pred_sets_full))]))
all_24m_vars <- unique(unlist(pred_sets_full[grep("_24m$", names(pred_sets_full))]))

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
    bench_data <- dt_bench_24m  # unified 24m benchmark for fair 12m vs 24m comparison
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

# Append to existing M01-M08 result files (do not overwrite)
append_or_write <- function(new_dt, path) {
  if (file.exists(path)) {
    old_dt <- fread(path)
    combined <- rbindlist(list(old_dt, new_dt), fill = TRUE)
    combined <- unique(combined, by = setdiff(names(combined), character(0)))
    fwrite(combined, path)
    cat(sprintf("  Appended %d new rows to %s (now %d rows)\n",
                nrow(new_dt), path, nrow(combined)))
  } else {
    fwrite(new_dt, path)
    cat(sprintf("  Created %s (%d rows)\n", path, nrow(new_dt)))
  }
}

append_or_write(all_metrics,     file.path(out_dir, "RF_metrics_LOSO.csv"))
append_or_write(all_predictions, file.path(out_dir, "RF_predictions_LOSO.csv"))
append_or_write(all_varimp,      file.path(out_dir, "RF_varimp_LOSO.csv"))

cat("Appended M09/M10 results to:", out_dir, "\n")

# =========================================================
# 9) Summary
# =========================================================

all_metrics[, window     := fifelse(grepl("_24m", model), "24m", "12m")]
all_metrics[, model_base := sub("_(12|24)m.*", "", model)]
all_metrics[, has_dist    := grepl("M02|M04|M06|M08", model_base)]
all_metrics[, has_traits  := grepl("M03|M04|M07|M08", model_base)]
all_metrics[, has_efp_mem := grepl("M05|M06|M07|M08", model_base)]

cat("\n--- Full results ---\n")
print(all_metrics[, .(
  model, response, n_pairs,
  RMSE = round(RMSE, 4), R2 = round(R2, 3),
  window, has_traits, has_dist, has_efp_mem
)][order(response, model)])

cat("\n--- v20: includes P_p05 and P_p95 precipitation quantiles ---\n")
cat("  Anomaly results saved in RF_outputs_anomaly_24mbench/\n")

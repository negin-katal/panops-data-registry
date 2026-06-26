library(data.table)
library(ranger)

# ============================================================
# RUN 21: Per-fold variable importance for M04 and M08 (12m)
#
# Records, for each LOSO fold:
#   test_site — the held-out site (prediction target)
#   variable  — predictor name
#   importance — permutation importance from that fold's RF
#
# This gives "site-level" importance: the variable importances
# from the model trained without that site.
#
# Output: RF_outputs_fixed/RF_per_fold_varimp_M04_M08.csv
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
cgs_file   <- "derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/RF_outputs_fixed"

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

# ============================================================
# 1) Load and prepare data (same as run_19_RF_LOSO_fixed.R)
# ============================================================

dt  <- fread(model_file)
cgs <- fread(cgs_file)

if ("year" %in% names(cgs) && !"YEAR" %in% names(cgs)) setnames(cgs, "year", "YEAR")
cgs_keep <- c("SITE_ID", "YEAR", "CGS_weighted_doy", "CGS_midpoint_doy",
              "GS_start_doy", "GS_end_doy", "GS_length_days")
cgs_keep <- cgs_keep[cgs_keep %in% names(cgs)]
dt <- merge(dt, cgs[, ..cgs_keep], by = c("SITE_ID", "YEAR"), all.x = TRUE)

dt <- dt[!SITE_ID %in% EXCLUDE_SITES]
cat("Dataset:", nrow(dt), "rows |", uniqueN(dt$SITE_ID), "sites\n")

dt_rf <- copy(dt)

cgs_month_vec <- as.integer(ceiling(dt_rf$CGS_weighted_doy / (365.25 / 12)))
cgs_month_vec <- pmin(pmax(cgs_month_vec, 1L), 12L)
cgs_month_vec[is.na(cgs_month_vec)] <- 12L

climate_prefixes <- c(
  "TA_mean", "TA_p05", "TA_p95",
  "VPD_mean", "VPD_p05", "VPD_p95",
  "P_mean", "P_sum","P_p05", "P_p95",
  "SW_IN_mean", "SW_IN_p05", "SW_IN_p95"
)

agg_months <- function(vals, is_sum) {
  if (all(is.na(vals))) return(NA_real_)
  if (is_sum) sum(vals, na.rm = TRUE) else mean(vals, na.rm = TRUE)
}

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

  dt_rf[[paste0(prefix, "_CGS12m")]] <- vapply(seq_len(nrow(dt_rf)), function(i) {
    m <- cgs_month_vec[i]
    agg_months(c(if (m < 12) mat_lag1[i, (m+1):12] else numeric(0),
                 mat_cur[i, 1:m]), is_sum_var)
  }, numeric(1))
}

all_cols <- names(dt_rf)
meteo_12m <- grep("_CGS12m$", all_cols, value = TRUE)

dist_pattern <- paste0(
  "^(mortality_intensity_pct|deadwood_increase_sum_pp|",
  "deadwood_increase_area_frac|deadwood_increase_mean_pp|",
  "deadwood_mean_pct|loss_area_frac|loss_sum_pp|loss_mean_pp)_[0-9]+m"
)
dist_current <- grep(paste0(dist_pattern, "$"),      all_cols, value = TRUE)
dist_lag1    <- grep(paste0(dist_pattern, "_lag1$"), all_cols, value = TRUE)
dist_12m <- c(dist_current, dist_lag1)

efp_mem_12m <- grep("_anom_lag1$", all_cols, value = TRUE)

trait_vars <- c(
  "gsmax_mean", "P12_mean", "P50_mean", "P88_mean", "rdmax_mean", "WUE_mean",
  "Leaf C", "Leaf N (mass)", "Leaf width", "Leaf C/N ratio", "Leaf P",
  "Stem conduit density", "Stem conduit diameter",
  "Leaf area (3114)", "SLA", "SSD", "Leaf thickness", "Leaf N (area)",
  "Leaf dry mass", "Rooting depth", "Leaf delta 15N"
)
trait_vars <- trait_vars[trait_vars %in% all_cols]

# ============================================================
# 2) Build benchmark set (complete cases across M04 + M08)
# ============================================================

all_M04_M08_vars <- unique(c(meteo_12m, trait_vars, dist_12m, efp_mem_12m))
bench_mask   <- complete.cases(dt_rf[, ..all_M04_M08_vars])
dt_bench_12m <- dt_rf[bench_mask]
cat("12m benchmark:", nrow(dt_bench_12m), "rows,",
    uniqueN(dt_bench_12m$SITE_ID), "sites\n")

# ============================================================
# 3) Variable group labels for each predictor
# ============================================================

make_group_table <- function() {
  rbind(
    data.table(variable = meteo_12m,    group = "Climate"),
    data.table(variable = trait_vars,   group = "Traits"),
    data.table(variable = dist_12m,     group = "Disturbance"),
    data.table(variable = efp_mem_12m,  group = "Memory")
  )
}
group_lut <- make_group_table()

# ============================================================
# 4) LOSO loop — M04 and M08 only
# ============================================================

model_specs <- list(
  M04_12m = list(preds = unique(c(meteo_12m, trait_vars, dist_12m)),       label = "M04"),
  M08_12m = list(preds = unique(c(meteo_12m, trait_vars, dist_12m, efp_mem_12m)), label = "M08")
)
model_specs <- lapply(model_specs, function(x) {
  x$preds <- x$preds[x$preds %in% all_cols]; x
})

cat("\nModel specs:\n")
for (nm in names(model_specs))
  cat(sprintf("  %-10s  %d predictors\n", nm, length(model_specs[[nm]]$preds)))

all_vimp_list <- list()

for (resp in RESPONSE_VARS) {
  for (spec_name in names(model_specs)) {
    spec     <- model_specs[[spec_name]]
    xvars    <- spec$preds
    model_nm <- paste0(spec_name, "_", resp)

    data_dt <- dt_bench_12m
    use_cols <- unique(c("SITE_ID", "YEAR", resp, xvars))
    use_cols <- use_cols[use_cols %in% names(data_dt)]
    model_dt <- data_dt[, ..use_cols]
    model_dt <- model_dt[!is.na(get(resp))]

    site_ids <- sort(unique(model_dt$SITE_ID))
    cat(sprintf("\n[%s] %d folds\n", model_nm, length(site_ids)))

    fold_list <- vector("list", length(site_ids))

    for (i in seq_along(site_ids)) {
      test_site <- site_ids[i]
      train_dt  <- model_dt[SITE_ID != test_site]
      xvars_ok  <- setdiff(names(model_dt), c("SITE_ID", "YEAR", resp))
      train_cc  <- train_dt[complete.cases(train_dt[, c(resp, xvars_ok), with = FALSE])]

      if (nrow(train_cc) < 10) {
        cat(sprintf("  Skip fold %d (%s): only %d train rows\n",
                    i, test_site, nrow(train_cc)))
        next
      }

      cat(sprintf("  fold %d/%d  site: %s\n", i, length(site_ids), test_site))

      rf <- ranger(
        x                         = train_cc[, ..xvars_ok],
        y                         = train_cc[[resp]],
        num.trees                 = N_TREES,
        importance                = "permutation",
        seed                      = SEED,
        respect.unordered.factors = "order"
      )

      fold_list[[i]] <- data.table(
        model     = model_nm,
        response  = resp,
        test_site = test_site,
        variable  = names(rf$variable.importance),
        importance = as.numeric(rf$variable.importance)
      )
    }

    all_vimp_list[[model_nm]] <- rbindlist(fold_list, fill = TRUE)
    cat(sprintf("  [%s] done. %d fold-variable rows saved.\n",
                model_nm, nrow(all_vimp_list[[model_nm]])))
  }
}

vimp_dt <- rbindlist(all_vimp_list, fill = TRUE)
vimp_dt <- merge(vimp_dt, group_lut, by = "variable", all.x = TRUE)
vimp_dt[is.na(group), group := "Other"]

out_path <- file.path(out_dir, "RF_per_fold_varimp_M04_M08.csv")
fwrite(vimp_dt, out_path)
cat("\nSaved:", out_path, "\n")
cat("Rows:", nrow(vimp_dt), "\n")
cat("Sites with data:", uniqueN(vimp_dt$test_site), "\n")

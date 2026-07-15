library(data.table)
library(ranger)
library(treeshap)

# ============================================================
# RUN 25b: TreeSHAP for M04/M08 x 12m/24m — RAW-LAG MEMORY
#          Unified 24m benchmark (same rows for 12m and 24m)
#
# Models: M04_12m, M04_24m, M08_12m, M08_24m
# Output: RF_outputs_rawmem_24mbench_noWET/RF_site_shap_M04_M08.csv
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
cgs_file   <- "derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv"
out_dir    <- "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_noWET"
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

# ============================================================
# 1) Load and prepare (same pipeline as run_24)
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

n_before_wet <- uniqueN(dt$SITE_ID)
dt <- dt[IGBP != "WET"]
n_after_wet  <- uniqueN(dt$SITE_ID)
cat(sprintf("Excluded WET IGBP sites (%d -> %d sites)\n", n_before_wet, n_after_wet))


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

  dt_rf[[paste0(prefix, "_CGS24m")]] <- vapply(seq_len(nrow(dt_rf)), function(i) {
    m <- cgs_month_vec[i]
    agg_months(c(if (m < 12) mat_lag2[i, (m+1):12] else numeric(0),
                 mat_lag1[i, 1:12],
                 mat_cur[i, 1:m]), is_sum_var)
  }, numeric(1))
}

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
dist_12m     <- c(dist_current, dist_lag1)
dist_24m     <- c(dist_current, dist_lag1, dist_lag2)

# Compute raw lagged EFP columns
efp_vars <- c("GPPsat", "NEPmax", "ETmax", "uWUE")
efp_lookup <- unique(dt_rf[, c("SITE_ID", "YEAR", efp_vars), with = FALSE])
for (efp in efp_vars) {
  lag1_col <- paste0(efp, "_lag1_raw")
  lag1_lut  <- copy(efp_lookup)[, YEAR := YEAR + 1L]
  setnames(lag1_lut, efp, lag1_col)
  dt_rf <- merge(dt_rf, lag1_lut[, c("SITE_ID", "YEAR", lag1_col), with = FALSE],
                 by = c("SITE_ID", "YEAR"), all.x = TRUE)
  lag2_col <- paste0(efp, "_lag2_raw")
  lag2_lut  <- copy(efp_lookup)[, YEAR := YEAR + 2L]
  setnames(lag2_lut, efp, lag2_col)
  dt_rf <- merge(dt_rf, lag2_lut[, c("SITE_ID", "YEAR", lag2_col), with = FALSE],
                 by = c("SITE_ID", "YEAR"), all.x = TRUE)
}
efp_mem_12m <- paste0(efp_vars, "_lag1_raw")
efp_mem_24m <- c(paste0(efp_vars, "_lag1_raw"), paste0(efp_vars, "_lag2_raw"))

trait_vars <- c(
  "gsmax_mean", "P12_mean", "P50_mean", "P88_mean", "rdmax_mean", "WUE_mean",
  "Leaf C", "Leaf N (mass)", "Leaf width", "Leaf C/N ratio", "Leaf P",
  "Stem conduit density", "Stem conduit diameter",
  "Leaf area (3114)", "SLA", "SSD", "Leaf thickness", "Leaf N (area)",
  "Leaf dry mass", "Rooting depth", "Leaf delta 15N"
)
trait_vars <- trait_vars[trait_vars %in% all_cols]

# ============================================================
# 2) Unified 24m benchmark
# ============================================================

all_24m_vars <- unique(c(meteo_24m, trait_vars, dist_24m, efp_mem_24m))
bench_mask   <- complete.cases(dt_rf[, ..all_24m_vars])
dt_bench     <- dt_rf[bench_mask]
cat("Unified 24m benchmark:", nrow(dt_bench), "rows,",
    uniqueN(dt_bench$SITE_ID), "sites\n")

# ============================================================
# 3) Group lookup (covers all windows)
# ============================================================

group_lut <- rbind(
  data.table(variable = c(meteo_12m, meteo_24m), group = "Climate"),
  data.table(variable = trait_vars,               group = "Traits"),
  data.table(variable = c(dist_12m, dist_24m),    group = "Disturbance"),
  data.table(variable = c(efp_mem_12m, efp_mem_24m), group = "Memory")
)
group_lut <- unique(group_lut)

# ============================================================
# 4) Model specs: M04 and M08, both windows
# ============================================================

model_specs <- list(
  M04_12m = unique(c(meteo_12m, trait_vars, dist_12m)),
  M04_24m = unique(c(meteo_24m, trait_vars, dist_24m)),
  M08_12m = unique(c(meteo_12m, trait_vars, dist_12m, efp_mem_12m)),
  M08_24m = unique(c(meteo_24m, trait_vars, dist_24m, efp_mem_24m))
)
model_specs <- lapply(model_specs, function(x) x[x %in% all_cols])

cat("\nModel predictor counts:\n")
for (nm in names(model_specs))
  cat(sprintf("  %-10s  %d\n", nm, length(model_specs[[nm]])))

# ============================================================
# 5) LOSO TreeSHAP loop
# ============================================================

shap_list <- list()
run_idx   <- 0

for (resp in RESPONSE_VARS) {
  for (spec_name in names(model_specs)) {
    xvars    <- model_specs[[spec_name]]
    model_nm <- paste0(spec_name, "_", resp)

    use_cols <- unique(c("SITE_ID", "YEAR", resp, xvars))
    use_cols <- use_cols[use_cols %in% names(dt_bench)]
    model_dt <- dt_bench[, ..use_cols]
    model_dt <- model_dt[!is.na(get(resp))]

    site_ids <- sort(unique(model_dt$SITE_ID))
    cat(sprintf("\n[%s]  %d sites\n", model_nm, length(site_ids)))

    fold_shap <- vector("list", length(site_ids))

    for (i in seq_along(site_ids)) {
      test_site <- site_ids[i]
      train_dt  <- model_dt[SITE_ID != test_site]
      test_dt   <- model_dt[SITE_ID == test_site]
      xvars_ok  <- setdiff(names(model_dt), c("SITE_ID", "YEAR", resp))

      train_cc <- train_dt[complete.cases(train_dt[, c(resp, xvars_ok), with = FALSE])]
      test_cc  <- test_dt[complete.cases(test_dt[, ..xvars_ok])]

      if (nrow(train_cc) < 10 || nrow(test_cc) == 0) {
        cat(sprintf("  Skip fold %d (%s)\n", i, test_site)); next
      }

      cat(sprintf("  fold %d/%d  site: %s  (train=%d, test=%d)\n",
                  i, length(site_ids), test_site, nrow(train_cc), nrow(test_cc)))

      rf <- ranger(
        x                         = train_cc[, ..xvars_ok],
        y                         = train_cc[[resp]],
        num.trees                 = N_TREES,
        seed                      = SEED,
        respect.unordered.factors = "order"
      )

      shap_result <- tryCatch({
        unified <- ranger.unify(rf, as.data.frame(train_cc[, ..xvars_ok]))
        treeshap(unified, as.data.frame(test_cc[, ..xvars_ok]), verbose = FALSE)
      }, error = function(e) {
        cat("    TreeSHAP failed:", e$message, "\n"); NULL
      })

      if (is.null(shap_result)) next

      shap_mat <- as.data.table(shap_result$shaps)
      mean_abs_shap <- shap_mat[, lapply(.SD, function(x) mean(abs(x), na.rm = TRUE))]
      shap_long <- melt(mean_abs_shap, measure.vars = names(mean_abs_shap),
                        variable.name = "variable", value.name = "mean_abs_shap")
      shap_long[, `:=`(model = model_nm, response = resp, test_site = test_site)]
      fold_shap[[i]] <- shap_long
    }

    run_idx <- run_idx + 1
    shap_list[[run_idx]] <- rbindlist(fold_shap, fill = TRUE)
    cat(sprintf("  [%s] done.\n", model_nm))
  }
}

# ============================================================
# 6) Save
# ============================================================

shap_dt <- rbindlist(shap_list, fill = TRUE)
shap_dt[, variable := as.character(variable)]
shap_dt <- merge(shap_dt, group_lut, by = "variable", all.x = TRUE)
shap_dt[is.na(group), group := "Other"]

out_path <- file.path(out_dir, "RF_site_shap_M04_M08.csv")
fwrite(shap_dt, out_path)
cat("\nSaved:", out_path, "\n")
cat("Rows:", nrow(shap_dt), "| Sites:", uniqueN(shap_dt$test_site), "\n")

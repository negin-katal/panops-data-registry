library(data.table)
library(readr)
library(stringr)
library(lubridate)

# ============================================================
# PATCH: Add P_p05 and P_p95 monthly precipitation quantiles
#
# Steps:
#   1) Read HH zip files for all 184 model sites
#   2) Compute P_p05 / P_p95 per (SITE_ID, YEAR, MONTH)
#   3) Pivot wide and join to EFPanom_memory dataset
#   4) Re-run lag1/lag2 creation (notebook-19 equivalent)
#   5) Save updated final model dataset
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

zip_index_path <- "fluxnet_2017_2025_V02/EFP_outputs_corrected/logs/fluxmet_hh_zip_index.csv"
efpanom_file   <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_EFPanom_memory.csv"
out_file       <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

START_YEAR <- 2015   # include 2015-2016 for lag2 coverage
END_YEAR   <- 2025

# ============================================================
# 1) Load zip index and model dataset; get target sites
# ============================================================

zip_index <- fread(zip_index_path)
dt_model  <- fread(efpanom_file)

model_sites <- unique(dt_model$SITE_ID)
cat("Model sites:", length(model_sites), "\n")

# Only process sites present in both zip index and model dataset
sites_to_run <- zip_index[site_id %in% model_sites, .SD[1], by = site_id]
cat("Sites with zip files:", nrow(sites_to_run), "\n")

# ============================================================
# 2) Extract P_p05 / P_p95 per (SITE_ID, YEAR, MONTH)
# ============================================================

q_safe <- function(x, prob) {
  x <- x[is.finite(x) & x >= 0]
  if (!length(x)) return(NA_real_)
  as.numeric(quantile(x, probs = prob, na.rm = TRUE, names = FALSE))
}

precip_long_list <- vector("list", nrow(sites_to_run))

for (i in seq_len(nrow(sites_to_run))) {
  site_i <- sites_to_run$site_id[i]
  cat(sprintf("[%d/%d] Reading P for %s\n", i, nrow(sites_to_run), site_i))

  tryCatch({
    dat <- suppressMessages(
      readr::read_csv(
        unz(sites_to_run$zip_path[i], sites_to_run$hh_file[i]),
        show_col_types = FALSE, progress = FALSE,
        col_select = c("TIMESTAMP_START", "P_F")
      )
    )

    dat_dt <- as.data.table(dat)
    dat_dt[, P_F := as.numeric(P_F)]
    dat_dt[P_F == -9999, P_F := NA_real_]

    dat_dt[, TIMESTAMP_START := lubridate::ymd_hm(
      as.character(TIMESTAMP_START), tz = "UTC"
    )]
    dat_dt[, YEAR  := lubridate::year(TIMESTAMP_START)]
    dat_dt[, MONTH := lubridate::month(TIMESTAMP_START)]
    dat_dt[, SITE_ID := site_i]

    dat_dt <- dat_dt[YEAR >= START_YEAR & YEAR <= END_YEAR]

    agg <- dat_dt[, .(
      P_p05 = q_safe(P_F, 0.05),
      P_p95 = q_safe(P_F, 0.95)
    ), by = .(SITE_ID, YEAR, MONTH)]

    precip_long_list[[i]] <- agg

  }, error = function(e) {
    cat("  WARNING: failed for", site_i, ":", e$message, "\n")
  })
}

precip_long <- rbindlist(precip_long_list, fill = TRUE)
cat("\nPrecip quantile rows computed:", nrow(precip_long), "\n")

# ============================================================
# 3) Pivot to wide format: P_p05_M01 ... P_p95_M12
# ============================================================

p05_wide <- dcast(precip_long, SITE_ID + YEAR ~ paste0("P_p05_M", sprintf("%02d", MONTH)),
                  value.var = "P_p05")
p95_wide <- dcast(precip_long, SITE_ID + YEAR ~ paste0("P_p95_M", sprintf("%02d", MONTH)),
                  value.var = "P_p95")

precip_wide <- merge(p05_wide, p95_wide, by = c("SITE_ID", "YEAR"), all = TRUE)
cat("Wide precip cols:", ncol(precip_wide) - 2, "\n")   # should be 24

# ============================================================
# 4) Join new precip columns to EFPanom_memory dataset
# ============================================================

# Drop any existing P_p05/P_p95 columns (shouldn't exist but be safe)
existing_pp_cols <- grep("^P_p0[59]", names(dt_model), value = TRUE)
if (length(existing_pp_cols) > 0) {
  dt_model[, (existing_pp_cols) := NULL]
  cat("Removed", length(existing_pp_cols), "old P_p05/P_p95 columns\n")
}

dt_patched <- merge(dt_model, precip_wide, by = c("SITE_ID", "YEAR"), all.x = TRUE)
cat("Patched dataset:", nrow(dt_patched), "rows x", ncol(dt_patched), "cols\n")

# Verify new columns present
new_cols_check <- grep("^P_p05_M", names(dt_patched), value = TRUE)
cat("New P_p05 columns:", length(new_cols_check), "\n")
cat("NA rate in P_p05_M06:",
    round(mean(is.na(dt_patched$P_p05_M06)) * 100, 1), "%\n")

# ============================================================
# 5) Re-run lagging (equivalent to notebook 19)
# ============================================================

all_cols <- names(dt_patched)

# All monthly climate columns (now includes P_p05 and P_p95)
meteo_cols <- grep("_(mean|p05|p95|sum)_M[0-9]{2}$", all_cols, value = TRUE)

dist_cols <- grep(
  paste0(
    "^(mortality_intensity_pct|deadwood_increase_sum_pp|",
    "deadwood_increase_area_frac|deadwood_increase_mean_pp|",
    "deadwood_mean_pct|loss_area_frac|loss_sum_pp|loss_mean_pp)_[0-9]+m$"
  ),
  all_cols, value = TRUE
)

cols_to_lag <- c(meteo_cols, dist_cols)

cat("\nMonthly climate cols to lag:", length(meteo_cols), "\n")
cat("Disturbance cols to lag    :", length(dist_cols), "\n")

# Remove only meteo/disturbance lag columns (NOT EFP anomaly lags like _anom_lag1)
existing_lags <- grep("_(mean|p05|p95|sum)_M[0-9]{2}_(lag1|lag2)$|_[0-9]+m_(lag1|lag2)$",
                      names(dt_patched), value = TRUE)
if (length(existing_lags) > 0) {
  dt_patched[, (existing_lags) := NULL]
  cat("Removed", length(existing_lags), "existing lag columns\n")
}

dt_out <- copy(dt_patched)

for (lag in 1:2) {
  shifted <- dt_patched[, c("SITE_ID", "YEAR", cols_to_lag), with = FALSE]
  shifted[, YEAR := YEAR + lag]
  lag_names <- paste0(cols_to_lag, "_lag", lag)
  setnames(shifted, cols_to_lag, lag_names)
  dt_out <- merge(dt_out, shifted, by = c("SITE_ID", "YEAR"), all.x = TRUE)
  cat("Lag", lag, "merged. Cols now:", ncol(dt_out), "\n")
}

cat("\nFinal dataset:", nrow(dt_out), "rows x", ncol(dt_out), "cols\n")

# Verify P_p05 lag columns
new_lag_check <- grep("^P_p05_M06_lag1$", names(dt_out), value = TRUE)
cat("P_p05_M06_lag1 present:", length(new_lag_check) > 0, "\n")

# ============================================================
# 6) Save
# ============================================================

fwrite(dt_out, out_file)
cat("\nSaved:", out_file, "\n")
cat("Rows:", nrow(dt_out), "| Cols:", ncol(dt_out), "\n")

# Column manifest
col_manifest <- data.table(
  column   = names(dt_out),
  category = fcase(
    names(dt_out) %in% paste0(meteo_cols, "_lag2"), "meteo_lag2",
    names(dt_out) %in% paste0(meteo_cols, "_lag1"), "meteo_lag1",
    names(dt_out) %in% meteo_cols,                   "meteo_current",
    names(dt_out) %in% paste0(dist_cols, "_lag2"),   "disturbance_lag2",
    names(dt_out) %in% paste0(dist_cols, "_lag1"),   "disturbance_lag1",
    names(dt_out) %in% dist_cols,                    "disturbance_current",
    grepl("_anom_lag", names(dt_out)),               "efp_anomaly_memory",
    default = "other"
  )
)
fwrite(col_manifest,
       "derived_tables/outputs_afterEGU_results/lagged_dataset_column_manifest.csv")
print(col_manifest[, .N, by = category][order(category)])

cat("\nDone. New P_p05/P_p95 monthly columns added (current + lag1 + lag2).\n")
cat("Next: rerun run_20_RF_LOSO_fixed.R and run_20_RF_LOSO_rawmem_fixed.R\n")

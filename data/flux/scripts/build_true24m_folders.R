#!/usr/bin/env Rscript
# ============================================================================
# Build the "true 24m" combined derived_tables folders: 12m rows taken
# verbatim from the PRODUCTION Optuna outputs, 24m rows taken from the
# lag2-corrected retrain (predictions) and the lag2 24m-only TreeSHAP.
#
# These are the folders the true-24m plot scripts read from - a physically
# separate output tree so the production XGB_v10_optuna / RF_v10_optuna /
# LGB_v10_optuna folders (and their repCV counterparts) are never touched.
#
#   Rscript build_true24m_folders.R <RF|XGB|LGB> <tc30|tc50>
# ============================================================================
suppressMessages(library(data.table))
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B <- "derived_tables/outputs_afterEGU_results"

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("Usage: Rscript build_true24m_folders.R <RF|XGB|LGB> <tc30|tc50>")
fam <- args[1]; ds <- args[2]
stopifnot(fam %in% c("RF","XGB","LGB"), ds %in% c("tc30","tc50"))

if (ds == "tc30") {
  prod_loso <- sprintf("%s/%s_v10_optuna", B, fam)
  prod_rep  <- sprintf("%s/%s_optuna_repCV", B, fam)
  lag2_loso <- sprintf("%s/%s_v10_lag2_optuna", B, fam)
  lag2_rep  <- sprintf("%s/%s_optuna_repCV_lag2", B, fam)
  out_loso  <- sprintf("%s/%s_v10_true24m_optuna", B, fam)
  out_rep   <- sprintf("%s/%s_optuna_repCV_true24m", B, fam)
} else {
  prod_loso <- sprintf("%s/%s_v10_tc50_optuna", B, fam)
  prod_rep  <- sprintf("%s/%s_optuna_repCV_tc50", B, fam)
  lag2_loso <- sprintf("%s/%s_v10_tc50_lag2_optuna", B, fam)
  lag2_rep  <- sprintf("%s/%s_optuna_repCV_tc50_lag2", B, fam)
  out_loso  <- sprintf("%s/%s_v10_tc50_true24m_optuna", B, fam)
  out_rep   <- sprintf("%s/%s_optuna_repCV_tc50_true24m", B, fam)
}
dir.create(out_loso, showWarnings = FALSE, recursive = TRUE)
dir.create(out_rep,  showWarnings = FALSE, recursive = TRUE)

M24 <- c("M1_24m","M2_24m","M3_24m","M4_24m","M5_raw_24m","M5_anom_24m",
         "M6_raw_24m","M6_anom_24m","M7_raw_24m","M7_anom_24m","M8_raw_24m","M8_anom_24m")
M24_SHAP <- c("M4_24m","M6_raw_24m","M6_anom_24m","M8_raw_24m","M8_anom_24m")

combine_predictions <- function(prod_dir, lag2_dir, out_dir, label) {
  pf <- sprintf("%s/%s_predictions_LOSO.csv", prod_dir, fam)
  lf <- sprintf("%s/%s_predictions_LOSO.csv", lag2_dir, fam)
  stopifnot(file.exists(pf), file.exists(lf))
  prod <- fread(pf); lag2 <- fread(lf)

  stopifnot(all(unique(lag2$model) %in% M24))          # lag2 file must be 24m-only
  n_prod12 <- prod[!(model %in% M24)]                   # keep production's 12m rows
  # sanity: production file's 24m rows are being REPLACED, not appended to
  n_prod24 <- prod[model %in% M24]
  combined <- rbindlist(list(n_prod12, lag2), fill = TRUE)

  fwrite(combined, sprintf("%s/%s_predictions_LOSO.csv", out_dir, fam))
  cat(sprintf("  [%s] predictions: kept %d 12m rows (prod), replaced %d->%d 24m rows (lag2) -> %d total\n",
              label, nrow(n_prod12), nrow(n_prod24), nrow(lag2), nrow(combined)))
  invisible(combined)
}

combine_shap <- function(prod_dir, lag2_dir, out_dir) {
  pf <- sprintf("%s/%s_site_shap_M04_M08.csv", prod_dir, fam)
  lf <- sprintf("%s/%s_site_shap_M04_M08_24m.csv", lag2_dir, fam)
  stopifnot(file.exists(pf), file.exists(lf))
  prod <- fread(pf); lag2 <- fread(lf)

  stopifnot(all(unique(lag2$model) %in% M24_SHAP))
  n_prod12 <- prod[!(model %in% M24_SHAP)]
  n_prod24 <- prod[model %in% M24_SHAP]
  combined <- rbindlist(list(n_prod12, lag2), fill = TRUE)

  fwrite(combined, sprintf("%s/%s_site_shap_M04_M08.csv", out_dir, fam))
  cat(sprintf("  [LOSO]     SHAP:        kept %d 12m rows (prod), replaced %d->%d 24m rows (lag2) -> %d total\n",
              nrow(n_prod12), nrow(n_prod24), nrow(lag2), nrow(combined)))
}

cat(sprintf("\n=== %s / %s ===\n", fam, ds))
combine_predictions(prod_loso, lag2_loso, out_loso, "LOSO")
combine_shap(prod_loso, lag2_loso, out_loso)
combine_predictions(prod_rep,  lag2_rep,  out_rep,  "repCV")
cat("TRUE24M_BUILD_DONE:", fam, ds, "\n")

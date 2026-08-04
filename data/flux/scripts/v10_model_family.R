#!/usr/bin/env Rscript
# ============================================================================
# Optional model-family path override for the V10 plot scripts.
#
# By default this is a NO-OP: with no environment variables set, every plot
# script keeps reading the RF outputs and writing to plots/V10/<dataset>/,
# exactly as before. Setting the variables below retargets the same scripts at
# another learner's outputs (e.g. XGBoost) without duplicating any plot code.
#
#   V10_IN_DIR    directory holding the predictions / SHAP CSVs
#                 e.g. derived_tables/outputs_afterEGU_results/XGB_v10_all_sites
#   V10_PREFIX    filename prefix replacing "RF_"  (e.g. "XGB")
#   V10_OUT_ROOT  output root replacing "plots/V10" (e.g. plots/V10/XGBoost)
#
# Usage inside a plot script, after the dataset_type path block:
#   source("scripts/v10_model_family.R"); v10_apply_override()
# ============================================================================

v10_apply_override <- function(env = parent.frame()) {
  in_dir   <- Sys.getenv("V10_IN_DIR")
  prefix   <- Sys.getenv("V10_PREFIX")
  out_root <- Sys.getenv("V10_OUT_ROOT")

  # --- inputs: repoint directory and/or swap the RF_ filename prefix ---------
  if (nzchar(in_dir) || nzchar(prefix)) {
    for (v in c("pred_file", "shap_file")) {
      if (exists(v, envir = env, inherits = FALSE)) {
        p    <- get(v, envir = env)
        base <- basename(p)
        if (nzchar(prefix)) base <- sub("^RF_", paste0(prefix, "_"), base)
        dir  <- if (nzchar(in_dir)) in_dir else dirname(p)
        assign(v, file.path(dir, base), envir = env)
      }
    }
  }

  # --- outputs: repoint the plots/V10 root ----------------------------------
  if (nzchar(out_root)) {
    for (v in c("base_out", "out_dir", "output_dir", "out_igbp", "out_tc")) {
      if (exists(v, envir = env, inherits = FALSE)) {
        assign(v, sub("^plots/V10", out_root, get(v, envir = env)), envir = env)
      }
    }
  }

  invisible(NULL)
}

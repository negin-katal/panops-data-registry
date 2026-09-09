#!/usr/bin/env bash
# ============================================================================
# Every V10 figure for the "true 24m" combined data (12m rows verbatim from
# production, 24m rows lag2-corrected), for one Optuna-tuned learner.
#
# Same plot scripts as production; only input/output paths are redirected via
# scripts/v10_model_family.R's env-var override, so production figures under
# plots/V10/{XGB,RF,LGB}_optuna/ are never touched.
#
#   bash scripts/run_true24m_plots.sh <RF|XGB|LGB> <tc30|tc50>
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
FAM=$1; DS_ARG=$2

if [ "$DS_ARG" = "tc30" ]; then
  DATASET_TYPE=filtered
  IN_LOSO="derived_tables/outputs_afterEGU_results/${FAM}_v10_true24m_optuna"
  IN_REP="derived_tables/outputs_afterEGU_results/${FAM}_optuna_repCV_true24m"
else
  DATASET_TYPE=tc50
  IN_LOSO="derived_tables/outputs_afterEGU_results/${FAM}_v10_tc50_true24m_optuna"
  IN_REP="derived_tables/outputs_afterEGU_results/${FAM}_optuna_repCV_tc50_true24m"
fi
OUT_LOSO="plots/V10/true_24m/${FAM}_optuna"
OUT_REP="plots/V10/true_24m/repeatedCV/${FAM}_optuna"

echo "############ true_24m LOSO figures: $FAM $DS_ARG ############"
export V10_IN_DIR="$IN_LOSO" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT_LOSO"
$RS scripts/plot_v10_RMSE_paired_violin.R     "$DATASET_TYPE"        2>&1 | tail -2
$RS scripts/plot_v10_RMSE_delta_bars.R        "$DATASET_TYPE"        2>&1 | tail -2
$RS scripts/plot_v10_delta_RMSE_by_category.R "$DATASET_TYPE"        2>&1 | tail -2
$RS scripts/plot_v10_delta_RMSE_by_category.R "$DATASET_TYPE" merge  2>&1 | tail -2
$RS scripts/plot_v10_IGBP_delta_RMSE.R        "$DATASET_TYPE"        2>&1 | tail -2
$RS scripts/plot_v10_SHAP_percent_disturbance.R "$DATASET_TYPE"       2>&1 | tail -2
$RS scripts/plot_v10_SHAP_percent_disturbance.R "$DATASET_TYPE" merge 2>&1 | tail -2
$RS scripts/plot_v10_IGBP_SHAP.R              "$DATASET_TYPE"        2>&1 | tail -2
$RS scripts/plot_v10_site_shap_distmetrics.R  "$DATASET_TYPE"        2>&1 | tail -2
$RS scripts/plot_v10_IGBP_board.R             "$DATASET_TYPE"        2>&1 | tail -2

echo "############ true_24m repeated-CV figures: $FAM $DS_ARG ############"
export V10_IN_DIR="$IN_REP" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT_REP"
$RS scripts/plot_v10_RMSE_paired_violin.R     "$DATASET_TYPE"       2>&1 | tail -2
$RS scripts/plot_v10_RMSE_delta_bars.R        "$DATASET_TYPE"       2>&1 | tail -2
$RS scripts/plot_v10_delta_RMSE_by_category.R "$DATASET_TYPE"       2>&1 | tail -2
$RS scripts/plot_v10_delta_RMSE_by_category.R "$DATASET_TYPE" merge 2>&1 | tail -2
$RS scripts/plot_v10_IGBP_delta_RMSE.R        "$DATASET_TYPE"       2>&1 | tail -2

echo
DSDIR=$([ "$DS_ARG" = "tc30" ] && echo sites_with_high_Tcover || echo sites_tc50)
echo "=== true_24m figure counts: $FAM $DS_ARG ==="
echo "  LOSO: $(find "$OUT_LOSO/$DSDIR" -name '*.png' 2>/dev/null | wc -l) png"
echo "  repCV: $(find "$OUT_REP/$DSDIR" -name '*.png' 2>/dev/null | wc -l) png"
echo "TRUE24M_PLOTS_DONE: $FAM $DS_ARG"

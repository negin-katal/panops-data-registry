#!/usr/bin/env bash
# ============================================================================
# Regenerate every RF-dependent V10 figure from the LightGBM outputs.
# Reuses the SAME plot scripts as the RF pipeline; only the input/output paths
# are redirected via the env vars read by scripts/v10_model_family.R.
# RF outputs and plots/V10/<dataset>/ are never touched.
#
#   bash scripts/run_v10_LGB_plots.sh [all_sites|filtered]   (default: both)
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux

RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export V10_PREFIX="RF"
export V10_OUT_ROOT="plots/V10/RF_optuna"

DATASETS=${1:-"all_sites filtered"}

for DS in $DATASETS; do
  if [ "$DS" = "all_sites" ]; then
    export V10_IN_DIR="derived_tables/outputs_afterEGU_results/RF_v10_all_sites_optuna"
  else
    export V10_IN_DIR="derived_tables/outputs_afterEGU_results/RF_v10_optuna"
  fi

  echo "############ LightGBM plots: $DS ############"
  echo "  in : $V10_IN_DIR"
  echo "  out: $V10_OUT_ROOT/<dataset>/"

  # RMSE family
  $RSCRIPT scripts/plot_v10_RMSE_paired_violin.R    "$DS" 2>&1 | tail -2
  $RSCRIPT scripts/plot_v10_RMSE_delta_bars.R       "$DS" 2>&1 | tail -2
  $RSCRIPT scripts/plot_v10_delta_RMSE_by_category.R "$DS"       2>&1 | tail -2
  $RSCRIPT scripts/plot_v10_delta_RMSE_by_category.R "$DS" merge 2>&1 | tail -2
  $RSCRIPT scripts/plot_v10_IGBP_delta_RMSE.R       "$DS" 2>&1 | tail -2

  # SHAP family
  $RSCRIPT scripts/plot_v10_SHAP_percent_disturbance.R "$DS"       2>&1 | tail -2
  $RSCRIPT scripts/plot_v10_SHAP_percent_disturbance.R "$DS" merge 2>&1 | tail -2
  $RSCRIPT scripts/plot_v10_IGBP_SHAP.R             "$DS" 2>&1 | tail -2
  $RSCRIPT scripts/plot_v10_site_shap_distmetrics.R "$DS" 2>&1 | tail -2

  # combined boards
  $RSCRIPT scripts/plot_v10_IGBP_board.R            "$DS" 2>&1 | tail -2
done

echo
echo "=== LightGBM figure counts ==="
for DS in all_sites sites_with_high_Tcover; do
  d="$V10_OUT_ROOT/$DS"
  [ -d "$d" ] && echo "  $DS: $(find "$d" -name '*.png' | wc -l) png"
done
echo "RF_OPTUNA_PLOTS_DONE"

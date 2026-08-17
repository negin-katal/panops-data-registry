#!/usr/bin/env bash
# ============================================================================
# Every V10 figure for the tc50 subsample (tree cover >=50% at 500 m).
#
# Same plot scripts as the other two datasets; only the input/output paths are
# redirected through the env vars read by scripts/v10_model_family.R, so the
# 93- and 112-site figures are never touched.
#
# LOO gets the full figure set. Repeated CV gets only the RMSE/prediction
# figures - SHAP comes from a full-data model, so it is identical under both
# resampling structures and the report falls back to the LOO SHAP figures.
#
#   bash scripts/run_tc50_plots.sh [concurrent_jobs]
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
JOBS=${1:-9}

# variant | family prefix | LOO input dir | output root
LOO_SPECS=(
  "RF_base|RF|RF_v10_tc50|plots/V10"
  "RF_exp02|RF|RF_v10_tc50_exp02|plots/V10/tuned_exp02"
  "RF_optuna|RF|RF_v10_tc50_optuna|plots/V10/RF_optuna"
  "XGB_base|XGB|XGB_v10_tc50|plots/V10/XGBoost"
  "XGB_tuned|XGB|XGB_v10_tc50_tuned|plots/V10/XGBoost_tuned"
  "XGB_optuna|XGB|XGB_v10_tc50_optuna|plots/V10/XGB_optuna"
  "LGB_base|LGB|LGB_v10_tc50|plots/V10/LightGBM"
  "LGB_tuned|LGB|LGB_v10_tc50_tuned|plots/V10/LightGBM_tuned"
  "LGB_optuna|LGB|LGB_v10_tc50_optuna|plots/V10/LGB_optuna"
)

loo_one () {
  IFS='|' read -r V FAM IN OUT <<< "$1"
  # bash arrays cannot cross into an xargs subshell - define the list here.
  local SCRIPTS=(plot_v10_RMSE_paired_violin plot_v10_RMSE_delta_bars
                 plot_v10_delta_RMSE_by_category plot_v10_IGBP_delta_RMSE
                 plot_v10_SHAP_percent_disturbance plot_v10_IGBP_SHAP
                 plot_v10_site_shap_distmetrics plot_v10_IGBP_board)
  local E="derived_tables/outputs_afterEGU_results/$IN"
  for S in "${SCRIPTS[@]}"; do
    V10_IN_DIR="$E" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT" \
      $RS "scripts/${S}.R" tc50 > "logs/tc50plot_${V}_${S}.log" 2>&1
  done
  for S in plot_v10_delta_RMSE_by_category plot_v10_SHAP_percent_disturbance; do
    V10_IN_DIR="$E" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT" \
      $RS "scripts/${S}.R" tc50 merge > "logs/tc50plot_${V}_${S}_merge.log" 2>&1
  done
  echo "  done LOO ${V}"
}

rep_one () {
  IFS='|' read -r V FAM <<< "$1"
  local SCRIPTS=(plot_v10_RMSE_paired_violin plot_v10_RMSE_delta_bars
                 plot_v10_delta_RMSE_by_category plot_v10_IGBP_delta_RMSE)
  local E="derived_tables/outputs_afterEGU_results/${V}_repCV_tc50"
  local OUT="plots/V10/repeatedCV/${V}"
  for S in "${SCRIPTS[@]}"; do
    V10_IN_DIR="$E" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT" \
      $RS "scripts/${S}.R" tc50 > "logs/tc50plot_rep_${V}_${S}.log" 2>&1
  done
  V10_IN_DIR="$E" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT" \
    $RS scripts/plot_v10_delta_RMSE_by_category.R tc50 merge \
    > "logs/tc50plot_rep_${V}_merged.log" 2>&1
  echo "  done repCV ${V}"
}
export -f loo_one rep_one; export RS

echo "############ tc50 LOO figures (9 variants) ############"
printf '%s\n' "${LOO_SPECS[@]}" | xargs -P "$JOBS" -I{} bash -c 'loo_one "$@"' _ {}

echo "############ tc50 repeated-CV figures (10 variants) ############"
printf '%s\n' RF_base\|RF RF_exp01\|RF RF_exp02\|RF RF_optuna\|RF \
              XGB_base\|XGB XGB_tuned\|XGB XGB_optuna\|XGB \
              LGB_base\|LGB LGB_tuned\|LGB LGB_optuna\|LGB \
  | xargs -P "$JOBS" -I{} bash -c 'rep_one "$@"' _ {}

echo
echo "=== tc50 figure counts ==="
for R in plots/V10 plots/V10/tuned_exp02 plots/V10/RF_optuna plots/V10/XGBoost \
         plots/V10/XGBoost_tuned plots/V10/XGB_optuna plots/V10/LightGBM \
         plots/V10/LightGBM_tuned plots/V10/LGB_optuna; do
  n=$(find "$R/sites_tc50" -name '*.png' 2>/dev/null | wc -l)
  printf "  %-34s %4d png\n" "$R/sites_tc50" "$n"
done
echo "  repeatedCV: $(find plots/V10/repeatedCV -path '*sites_tc50*' -name '*.png' 2>/dev/null | wc -l) png"
echo "TC50_PLOTS_DONE"

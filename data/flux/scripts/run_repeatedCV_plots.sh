#!/usr/bin/env bash
# ============================================================================
# Figures for the repeated-CV variants.
#
# ONLY the RMSE / prediction-based figures are regenerated. SHAP figures are
# computed from a FULL-DATA model (trained on every site), not from the CV
# folds, so they are identical under LOO and repeated CV - regenerating them
# would just duplicate bytes. The CV toggle therefore falls back to the LOO
# SHAP figures, which is the correct treatment: resampling structure changes
# how a model is VALIDATED, not what it learns from the complete dataset.
#
#   bash scripts/run_repeatedCV_plots.sh [concurrent] [cores]
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
JOBS=${1:-10}
VARIANTS=(RF_base RF_exp01 RF_exp02 RF_optuna XGB_base XGB_tuned XGB_optuna
          LGB_base LGB_tuned LGB_optuna)
SCRIPTS=(plot_v10_RMSE_paired_violin plot_v10_RMSE_delta_bars
         plot_v10_delta_RMSE_by_category plot_v10_IGBP_delta_RMSE)

one () {
  local V=$1 DS=$2
  local FAM=${V%%_*}
  # NOTE: bash arrays cannot be exported into an xargs subshell, so the script
  # list must be defined INSIDE the function. Defining it outside silently left
  # ${SCRIPTS[@]} empty here and only the merged call ran.
  local SCRIPTS=(plot_v10_RMSE_paired_violin plot_v10_RMSE_delta_bars
                 plot_v10_delta_RMSE_by_category plot_v10_IGBP_delta_RMSE)
  local SUF=""; [ "$DS" = "all_sites" ] && SUF="_all_sites"
  local IN="derived_tables/outputs_afterEGU_results/${V}_repCV${SUF}"
  local OUT="plots/V10/repeatedCV/${V}"
  for S in "${SCRIPTS[@]}"; do
    V10_IN_DIR="$IN" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT" \
      $RS "scripts/${S}.R" "$DS" > "logs/repcvplot_${V}_${DS}_${S}.log" 2>&1
  done
  V10_IN_DIR="$IN" V10_PREFIX="$FAM" V10_OUT_ROOT="$OUT" \
    $RS scripts/plot_v10_delta_RMSE_by_category.R "$DS" merge \
    > "logs/repcvplot_${V}_${DS}_merged.log" 2>&1
  echo "  done ${V}/${DS}"
}
export -f one; export RS
for V in "${VARIANTS[@]}"; do for DS in all_sites filtered; do echo "$V $DS"; done; done \
  | xargs -P "$JOBS" -n 2 bash -c 'one "$0" "$1"'
echo
echo "=== verification ==="
for V in "${VARIANTS[@]}"; do
  printf "  %-12s %3d + %3d png\n" "$V" \
    "$(find plots/V10/repeatedCV/$V/all_sites/RMSE -name '*.png' 2>/dev/null | wc -l)" \
    "$(find plots/V10/repeatedCV/$V/sites_with_high_Tcover/RMSE -name '*.png' 2>/dev/null | wc -l)"
done
echo "  logs with errors: $(grep -lciE '^error' logs/repcvplot_*.log 2>/dev/null | wc -l)"
echo "REPCV_PLOTS_DONE"

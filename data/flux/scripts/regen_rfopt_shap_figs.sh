#!/usr/bin/env bash
# Regenerate every RF-Optuna SHAP figure after the variable-name fix.
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
one () {
  IFS='|' read -r DS IN <<< "$1"
  export V10_IN_DIR="derived_tables/outputs_afterEGU_results/$IN" V10_PREFIX="RF" V10_OUT_ROOT="plots/V10/RF_optuna"
  for S in plot_v10_site_shap_distmetrics plot_v10_IGBP_SHAP plot_v10_IGBP_board; do
    $RS "scripts/${S}.R" "$DS" > "logs/rfoptfig_${DS}_${S}.log" 2>&1
  done
  $RS scripts/plot_v10_SHAP_percent_disturbance.R "$DS"       > "logs/rfoptfig_${DS}_shappct.log" 2>&1
  $RS scripts/plot_v10_SHAP_percent_disturbance.R "$DS" merge > "logs/rfoptfig_${DS}_shappct_merge.log" 2>&1
  echo "  done $DS"
}
export -f one; export RS
printf '%s\n' "filtered|RF_v10_optuna" "all_sites|RF_v10_all_sites_optuna" "tc50|RF_v10_tc50_optuna" \
  | xargs -P 3 -I{} bash -c 'one "$@"' _ {}
echo "RFOPT_FIGS_DONE"

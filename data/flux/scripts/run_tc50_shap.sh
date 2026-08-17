#!/usr/bin/env bash
# TreeSHAP extraction for every tc50 learner variant.
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
JOBS=${1:-4}; CORES=${2:-16}
one () {
  V10_CORES=$CORES V10_LGB_CORES=$CORES \
    $RS "scripts/$1" tc50 > "logs/tc50_shap_$2.log" 2>&1 \
    && echo "  OK      $2" || echo "  FAILED  $2"
}
export -f one; export RS CORES
cat <<'J' | xargs -P "$JOBS" -n 2 bash -c 'one "$0" "$1"'
run_v10_extract_SHAP_from_ranger.R RF_base
run_v10_RF_optuna_SHAP.R RF_optuna
run_v10_XGB_SHAP.R XGB_base
run_v10_XGB_tuned_SHAP.R XGB_tuned
run_v10_XGB_optuna_SHAP.R XGB_optuna
run_v10_LGB_SHAP.R LGB_base
run_v10_LGB_tuned_SHAP.R LGB_tuned
run_v10_LGB_optuna_SHAP.R LGB_optuna
J
echo "=== verification ==="
for d in RF_v10_tc50 RF_v10_tc50_optuna XGB_v10_tc50 XGB_v10_tc50_tuned XGB_v10_tc50_optuna \
         LGB_v10_tc50 LGB_v10_tc50_tuned LGB_v10_tc50_optuna; do
  F=$(ls derived_tables/outputs_afterEGU_results/$d/*site_shap_M04_M08.csv 2>/dev/null | head -1)
  printf "  %-24s %s\n" "$d" "$([ -n "$F" ] && echo "$(( $(wc -l < "$F") - 1 )) rows" || echo MISSING)"
done
echo "TC50_SHAP_DONE"

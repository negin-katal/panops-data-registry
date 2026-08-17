#!/usr/bin/env bash
# The 4 SHAP jobs left queued when the first driver was capped at -P 4.
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
CORES=${1:-24}
one () {
  V10_CORES=$CORES V10_LGB_CORES=$CORES \
    $RS "scripts/$1" tc50 > "logs/tc50_shap_$2.log" 2>&1 \
    && echo "  OK      $2" || echo "  FAILED  $2"
}
export -f one; export RS CORES
cat <<'J' | xargs -P 4 -n 2 bash -c 'one "$0" "$1"'
run_v10_XGB_optuna_SHAP.R XGB_optuna
run_v10_LGB_SHAP.R LGB_base
run_v10_LGB_tuned_SHAP.R LGB_tuned
run_v10_LGB_optuna_SHAP.R LGB_optuna
J
echo "TC50_SHAP_REST_DONE"

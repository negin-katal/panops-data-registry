#!/usr/bin/env bash
# Remaining 6 LOSO variants on the tc50 subsample, bounded pool (shared machine).
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
JOBS=${1:-3}; CORES=${2:-20}
one () {
  local SCRIPT=$1 TAG=$2
  V10_CORES=$CORES V10_LGB_CORES=$CORES \
    $RS "scripts/$SCRIPT" tc50 > "logs/tc50_${TAG}.log" 2>&1 \
    && echo "  OK      $TAG" || echo "  FAILED  $TAG"
}
export -f one; export RS CORES
cat <<'JOBS_EOF' | xargs -P "$JOBS" -n 2 bash -c 'one "$0" "$1"'
run_v10_RF_ranger_exp02.R RF_exp02
run_v10_RF_optuna.R RF_optuna
run_v10_XGB_tuned.R XGB_tuned
run_v10_XGB_optuna.R XGB_optuna
run_v10_LGB_tuned.R LGB_tuned
run_v10_LGB_optuna.R LGB_optuna
JOBS_EOF
echo "TC50_VARIANTS_DONE"

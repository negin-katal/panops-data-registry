#!/usr/bin/env bash
# Repeated LOSO-CV (3 reps x 80% of sites) for all variants on the tc50 subsample.
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
JOBS=${1:-4}; CORES=${2:-16}
one () {
  V10_CORES=$CORES V10_REPS=3 V10_SUBSAMP=0.8 \
    $RS scripts/run_v10_repeatedCV.R "$1" tc50 > "logs/repcv_tc50_$1.log" 2>&1 \
    && echo "  OK      $1" || echo "  FAILED  $1"
}
export -f one; export RS CORES
printf '%s\n' RF_base RF_exp01 RF_exp02 RF_optuna XGB_base XGB_tuned XGB_optuna \
              LGB_base LGB_tuned LGB_optuna | xargs -P "$JOBS" -n 1 bash -c 'one "$0"'
echo "=== verification ==="
for V in RF_base RF_exp01 RF_exp02 RF_optuna XGB_base XGB_tuned XGB_optuna LGB_base LGB_tuned LGB_optuna; do
  F="derived_tables/outputs_afterEGU_results/${V}_repCV_tc50/$(echo "$V" | sed 's/_.*//')_metrics_LOSO.csv"
  N=$([ -f "$F" ] && echo $(( $(wc -l < "$F") - 1 )) || echo 0)
  printf "  %-12s %3d rows\n" "$V" "$N"
done
echo "REPCV_TC50_DONE"

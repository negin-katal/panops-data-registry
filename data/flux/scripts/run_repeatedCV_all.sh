#!/usr/bin/env bash
# ============================================================================
# Repeated LOSO-CV for all ten variants x both datasets.
#
# 20 jobs run through a bounded pool. Cores are budgeted against what is
# actually free (the machine is shared), and the RF variants get the larger
# share because the Optuna/exp01 configs use mtry ~0.7-0.9*p, which is an order
# of magnitude more work per split than the sqrt(p) default.
#
#   bash scripts/run_repeatedCV_all.sh [concurrent_jobs] [cores_per_job]
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1

JOBS=${1:-8}
CORES=${2:-10}
VARIANTS=(RF_base RF_exp01 RF_exp02 RF_optuna XGB_base XGB_tuned XGB_optuna
          LGB_base LGB_tuned LGB_optuna)

echo "Repeated CV | 3 reps x 80% of sites | ${JOBS} concurrent jobs x ${CORES} cores"
echo "start: $(date +%H:%M)"; echo
S=$(date +%s)

run_one () {
  local V=$1 DS=$2
  V10_CORES=$CORES V10_REPS=3 V10_SUBSAMP=0.8 \
    $RS scripts/run_v10_repeatedCV.R "$V" "$DS" > "logs/repcv_${V}_${DS}.log" 2>&1
  if [ $? -eq 0 ]; then echo "  OK      ${V}/${DS}"; else echo "  FAILED  ${V}/${DS}"; fi
}
export -f run_one; export RS CORES

for V in "${VARIANTS[@]}"; do
  for DS in all_sites filtered; do echo "$V $DS"; done
done | xargs -P "$JOBS" -n 2 bash -c 'run_one "$0" "$1"'

echo
echo "  elapsed: $(( ($(date +%s)-S)/60 )) min"
echo
echo "=== verification ==="
for V in "${VARIANTS[@]}"; do
  for SUF in "_all_sites" ""; do
    D="derived_tables/outputs_afterEGU_results/${V}_repCV${SUF}"
    F="$D/$(echo "$V" | sed 's/_.*//')_metrics_LOSO.csv"
    N=$([ -f "$F" ] && echo $(( $(wc -l < "$F") - 1 )) || echo 0)
    printf "  %-12s %-10s %3d metric rows\n" "$V" "${SUF:-filtered}" "$N"
  done
done
echo "  logs with errors: $(grep -lciE '^error' logs/repcv_*.log 2>/dev/null | wc -l)"
echo "REPCV_ALL_DONE"

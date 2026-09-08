#!/usr/bin/env bash
# Full lag2 24m training: 3 learners x 2 CV modes x 2 datasets = 12 runs.
# tc30 runs FIRST (priority), tc50 second. Each run is internally parallel
# over LOSO folds (mclapply), so runs within a priority group are sequential
# to avoid oversubscribing cores; V10_CORES controls per-run parallelism.
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export V10_CORES=${V10_CORES:-40}
export V10_REPS=3 V10_SUBSAMP=0.8

run_one () {
  local FAM=$1 DS=$2 MODE=$3
  echo ">>> START $FAM $DS $MODE $(date +%H:%M:%S)"
  $RS scripts/run_v10_lag2_optuna.R "$FAM" "$DS" "$MODE" \
    > "logs/lag2train_${FAM}_${DS}_${MODE}.log" 2>&1
  echo ">>> DONE  $FAM $DS $MODE $(date +%H:%M:%S)"
}

echo "########## PRIORITY: tc30 ##########"
for FAM in XGB LGB RF; do
  for MODE in loso repeated; do
    run_one "$FAM" tc30 "$MODE"
  done
done
echo "TC30_LAG2_TRAINING_DONE"

echo "########## tc50 ##########"
for FAM in XGB LGB RF; do
  for MODE in loso repeated; do
    run_one "$FAM" tc50 "$MODE"
  done
done
echo "TC50_LAG2_TRAINING_DONE"
echo "ALL_LAG2_TRAINING_DONE"

#!/usr/bin/env bash
# Optuna retune for the lag2-enabled 24m models.
# 3 learners x 5 responses x 2 datasets, 50 trials each, scored by the same
# grouped 5-fold CV objective as the original tuning but on B2 / 24m / lag2.
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
export OMP_NUM_THREADS=1
# optuna lives in the base miniconda python, not in clean_r_env
PY=/home/nk1125/miniconda3/bin/python3
"$PY" -c "import optuna" 2>/dev/null || { echo "FATAL: optuna missing in $PY"; exit 1; }
TRIALS=${TRIALS:-50}
NJOBS=${NJOBS:-6}
CONC=${CONC:-8}

tune_one () {
  IFS='|' read -r DS DDIR PFX LRN RSP <<< "$1"
  V10_TUNE_OBJ="$PWD/scripts/optuna_cv_objective_lag2.R" \
  V10_TUNE_OUT="$PWD/plots/V10/Optuna_lag2/$DS" \
  V10_TUNE_DATADIR="$DDIR" V10_TUNE_PREFIX="$PFX" \
    $PY scripts/optuna_tune.py "$LRN" "$RSP" "$TRIALS" "$NJOBS" \
    > "logs/optuna_lag2_${DS}_${LRN}_${RSP}.log" 2>&1
  echo "  done ${DS} ${LRN} ${RSP}"
}
export -f tune_one; export PY TRIALS NJOBS

for SPEC in "tc30|derived_tables/outputs_afterEGU_results/v10_lag2|v10_lag2" \
            "tc50|derived_tables/outputs_afterEGU_results/v10_tc50_lag2|v10_tc50_lag2"; do
  IFS='|' read -r DS DDIR PFX <<< "$SPEC"
  echo "############ Optuna retune: $DS ############"
  for L in XGB LGB RF; do for R in GPPsat NEPmax ETmax WUE uWUE; do
    echo "${DS}|${DDIR}|${PFX}|${L}|${R}"
  done; done | xargs -P "$CONC" -I{} bash -c 'tune_one "$@"' _ {}
  echo "TUNING_DONE_${DS}"
done
echo "ALL_LAG2_TUNING_DONE"

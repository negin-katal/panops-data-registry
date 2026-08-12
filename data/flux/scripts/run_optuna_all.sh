#!/usr/bin/env bash
# ============================================================================
# Optuna (TPE) search for all three learners x five responses.
#
# Responses run in parallel; trials within a study run in parallel via n_jobs.
# Learners run sequentially so the machine is never oversubscribed.
#   5 responses x N_JOBS concurrent R processes, each pinned to 1 thread.
#
#   bash scripts/run_optuna_all.sh [n_trials] [n_jobs]
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
OPY=/home/nk1125/miniconda3/bin/python3          # base env - the one with optuna
export OMP_NUM_THREADS=1

N_TRIALS=${1:-50}
N_JOBS=${2:-6}
RESPONSES=(GPPsat NEPmax ETmax uWUE WUE)
mkdir -p plots/V10/Optuna logs

echo "Optuna TPE | ${N_TRIALS} trials x ${N_JOBS} parallel | 5 responses in parallel per learner"
echo

for L in LGB RF XGB; do          # fastest first, so failures surface early
  echo "══════ $L ══════"
  S=$(date +%s)
  for R in "${RESPONSES[@]}"; do
    $OPY scripts/optuna_tune.py "$L" "$R" "$N_TRIALS" "$N_JOBS" \
      > "logs/optuna_${L}_${R}.log" 2>&1 &
  done
  wait
  for R in "${RESPONSES[@]}"; do
    tail -1 "logs/optuna_${L}_${R}.log" 2>/dev/null | sed 's/^/  /'
  done
  echo "  elapsed: $(( ($(date +%s)-S)/60 )) min"
  echo
done

echo "=== collecting best configs ==="
$OPY - <<'PY'
import json, glob, os, csv
OUT="/mnt/gsdata/projects/panops/panops-data-registry/data/flux/plots/V10/Optuna"
rows=[]
for f in sorted(glob.glob(os.path.join(OUT,"*_best.json"))):
    b=json.load(open(f))
    r={"learner":b["learner"],"response":b["response"],
       "best_cv":round(b["best_value"],6),"n_trials":b["n_trials"]}
    r.update(b["params"]); rows.append(r)
if rows:
    keys=sorted({k for r in rows for k in r})
    keys=["learner","response","best_cv","n_trials"]+[k for k in keys if k not in
          ("learner","response","best_cv","n_trials")]
    with open(os.path.join(OUT,"optuna_best_configs.csv"),"w",newline="") as fh:
        w=csv.DictWriter(fh,fieldnames=keys); w.writeheader(); w.writerows(rows)
    print(f"  wrote optuna_best_configs.csv ({len(rows)} configs)")
else:
    print("  NO CONFIGS FOUND")
PY
echo "OPTUNA_ALL_DONE"

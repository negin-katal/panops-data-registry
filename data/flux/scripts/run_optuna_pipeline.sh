#!/usr/bin/env bash
# ============================================================================
# Full pipeline for the three Optuna-tuned variants, run in PARALLEL.
#
# 128-core machine, ~50 cores used by other users, so this budgets ~70:
#   RF  is the expensive learner (Optuna picked mtry ~0.78*p, i.e. ~14x the
#       default work per split) -> 40 cores
#   XGB / LGB                                                   -> 15 cores each
# Datasets run sequentially within a learner, learners run concurrently.
#
# Stage 1 training -> stage 2 SHAP -> stage 3 plots, each stage fully parallel.
# Nothing existing is overwritten: everything lands in *_optuna paths.
#
#   bash scripts/run_optuna_pipeline.sh
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1

train_one () {   # learner cores
  local L=$1 C=$2
  for DS in all_sites filtered; do
    V10_CORES=$C V10_LGB_CORES=$C V10_XGB_CORES=$C \
      $RS "scripts/run_v10_${L}_optuna.R" "$DS" > "logs/optuna_train_${L}_${DS}.log" 2>&1
    echo "  train ${L}/${DS}: $([ $? -eq 0 ] && echo OK || echo FAILED)"
  done
}
shap_one () {
  local L=$1 C=$2
  for DS in all_sites filtered; do
    V10_SHAP_CORES=$C V10_CORES=$C \
      $RS "scripts/run_v10_${L}_optuna_SHAP.R" "$DS" > "logs/optuna_shap_${L}_${DS}.log" 2>&1
    echo "  shap ${L}/${DS}: $([ $? -eq 0 ] && echo OK || echo FAILED)"
  done
}

echo "═════ STAGE 1: LOSO training ═════"; S=$(date +%s)
train_one RF 40 & train_one XGB 15 & train_one LGB 15 &
wait
echo "  stage 1 elapsed: $(( ($(date +%s)-S)/60 )) min"; echo

echo "═════ STAGE 2: SHAP ═════"; S=$(date +%s)
shap_one RF 40 & shap_one XGB 15 & shap_one LGB 15 &
wait
echo "  stage 2 elapsed: $(( ($(date +%s)-S)/60 )) min"; echo

echo "═════ STAGE 3: figures ═════"; S=$(date +%s)
for L in RF XGB LGB; do
  bash "scripts/run_v10_${L}_optuna_plots.sh" > "logs/optuna_plots_${L}.log" 2>&1 &
done
wait
echo "  stage 3 elapsed: $(( ($(date +%s)-S)/60 )) min"; echo

echo "═════ verification ═════"
for L in RF XGB LGB; do
  for DSD in all_sites sites_with_high_Tcover; do
    N=$(find "plots/V10/${L}_optuna/${DSD}" -name '*.png' 2>/dev/null | wc -l)
    printf "  %-4s %-22s %3d png\n" "$L" "$DSD" "$N"
  done
done
echo "  logs with errors: $(grep -lciE '^error' logs/optuna_*.log 2>/dev/null | wc -l)"
echo "OPTUNA_PIPELINE_DONE"

#!/usr/bin/env bash
# Regenerate the Section-3 paired-violin figure everywhere after the layout fix
# (duplicate memory-free panels removed; y axis zoomed to p95 via oob_keep).
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
S=scripts/plot_v10_RMSE_paired_violin.R

one () {
  IFS='|' read -r IN PREFIX OUT DS <<< "$1"
  V10_IN_DIR="$IN" V10_PREFIX="$PREFIX" V10_OUT_ROOT="$OUT" \
    $RS "$S" "$DS" > "logs/violin_$(echo "$OUT$DS" | tr '/' '_').log" 2>&1 \
    && echo "  OK   $OUT [$DS]" || echo "  FAIL $OUT [$DS]"
}
export -f one; export RS S

B=derived_tables/outputs_afterEGU_results
{
# --- LOO: 9 learner roots x 3 datasets ---
for DS in filtered all_sites tc50; do
  case $DS in filtered) L="";  R="";;
              all_sites) L="_all_sites"; R="";;
              tc50) L="_tc50"; R="";; esac
  echo "$B/RF_v10$L|RF|plots/V10|$DS"
  echo "$B/RF_v10${L}_exp02|RF|plots/V10/tuned_exp02|$DS"
  echo "$B/RF_v10${L}_optuna|RF|plots/V10/RF_optuna|$DS"
  echo "$B/XGB_v10$L|XGB|plots/V10/XGBoost|$DS"
  echo "$B/XGB_v10${L}_tuned|XGB|plots/V10/XGBoost_tuned|$DS"
  echo "$B/XGB_v10${L}_optuna|XGB|plots/V10/XGB_optuna|$DS"
  echo "$B/LGB_v10$L|LGB|plots/V10/LightGBM|$DS"
  echo "$B/LGB_v10${L}_tuned|LGB|plots/V10/LightGBM_tuned|$DS"
  echo "$B/LGB_v10${L}_optuna|LGB|plots/V10/LGB_optuna|$DS"
done
# --- repeated CV: 10 variants x 3 datasets ---
for DS in filtered all_sites tc50; do
  case $DS in filtered) SUF="";; all_sites) SUF="_all_sites";; tc50) SUF="_tc50";; esac
  for V in RF_base RF_exp01 RF_exp02 RF_optuna XGB_base XGB_tuned XGB_optuna LGB_base LGB_tuned LGB_optuna; do
    echo "$B/${V}_repCV${SUF}|${V%%_*}|plots/V10/repeatedCV/$V|$DS"
  done
done
} | xargs -P 8 -I{} bash -c 'one "$@"' _ {}
echo "VIOLIN_REGEN_DONE"

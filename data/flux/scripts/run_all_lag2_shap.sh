#!/usr/bin/env bash
# TreeSHAP for the 5 D-containing 24m models, lag2-corrected, all 3 Optuna
# learners. tc30 first (priority), then tc50.
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export V10_SHAP_CORES=${V10_SHAP_CORES:-60}

run_one () {
  local FAM=$1 DS=$2
  echo ">>> START SHAP $FAM $DS $(date +%H:%M:%S)"
  $RS scripts/run_v10_lag2_optuna_SHAP.R "$FAM" "$DS" > "logs/lag2shap_${FAM}_${DS}.log" 2>&1
  echo ">>> DONE  SHAP $FAM $DS $(date +%H:%M:%S)"
}

echo "########## PRIORITY: tc30 SHAP ##########"
for FAM in XGB LGB RF; do run_one "$FAM" tc30; done
echo "TC30_LAG2_SHAP_DONE"

echo "########## tc50 SHAP ##########"
for FAM in XGB LGB RF; do run_one "$FAM" tc50; done
echo "TC50_LAG2_SHAP_DONE"
echo "ALL_LAG2_SHAP_DONE"

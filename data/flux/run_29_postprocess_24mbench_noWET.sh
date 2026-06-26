#!/bin/bash
# ============================================================
# POST-PROCESSING for 24m benchmark, WET sites excluded
# Run this AFTER run_27_RF_LOSO_anomaly_24mbench_noWET.R and
#              run_27_RF_LOSO_rawmem_24mbench_noWET.R are done.
#
# Executes: SHAP (anomaly) -> SHAP (rawmem)
# ============================================================

set -e
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
LOG=logs

echo "=== $(date) : Starting 24mbench_noWET SHAP post-processing ==="

echo "--- SHAP: anomaly 24mbench noWET ---"
$RSCRIPT run_28_RF_shap_anomaly_24mbench_noWET.R 2>&1 | tee $LOG/run_28a_shap_anomaly_noWET.log

echo "--- SHAP: rawmem 24mbench noWET ---"
$RSCRIPT run_28_RF_shap_rawmem_24mbench_noWET.R 2>&1 | tee $LOG/run_28b_shap_rawmem_noWET.log

echo "=== $(date) : 24mbench_noWET post-processing DONE ==="
echo "Outputs in:"
echo "  derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_noWET/"
echo "  derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_noWET/"

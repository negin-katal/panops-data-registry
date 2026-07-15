#!/bin/bash
# ============================================================
# POST-PROCESSING for 24m benchmark runs
# Run this AFTER run_24_RF_LOSO_anomaly_24mbench.R and
#              run_24_RF_LOSO_rawmem_24mbench.R are done.
#
# Executes: SHAP (anomaly) -> SHAP (rawmem) -> all 6 plots
# ============================================================

set -e
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
LOG=logs

echo "=== $(date) : Starting 24mbench post-processing ==="

echo "--- SHAP: anomaly 24mbench ---"
$RSCRIPT run_25_RF_shap_anomaly_24mbench.R 2>&1 | tee $LOG/run_25a_shap_anomaly.log

echo "--- SHAP: rawmem 24mbench ---"
$RSCRIPT run_25_RF_shap_rawmem_24mbench.R 2>&1 | tee $LOG/run_25b_shap_rawmem.log

echo "--- Plots ---"
$RSCRIPT plot_03_site_shap_24mbench.R        2>&1 | tee $LOG/plot_03_24mbench.log
$RSCRIPT plot_04_site_shap_rawmem_24mbench.R 2>&1 | tee $LOG/plot_04_24mbench.log
$RSCRIPT plot_05_disturbance_shap_scatter_24mbench.R 2>&1 | tee $LOG/plot_05_24mbench.log
$RSCRIPT plot_06_site_overview_24mbench.R    2>&1 | tee $LOG/plot_06_24mbench.log
$RSCRIPT plot_07_R2_24mbench.R               2>&1 | tee $LOG/plot_07_24mbench.log

echo "=== $(date) : 24mbench post-processing DONE ==="
echo "Outputs in:"
echo "  derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/"
echo "  derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench/"
echo "  plots/disturbance_effects/24mbench/"

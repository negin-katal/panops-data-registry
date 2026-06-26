#!/bin/bash
# Wait for precip patch to finish, then launch both RF v20 runs.

LOGDIR=/mnt/gsdata/projects/panops/panops-data-registry/data/flux/logs
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
BASE=/mnt/gsdata/projects/panops/panops-data-registry/data/flux

PATCH_LOG="$LOGDIR/run_20_patch_precip_quantiles.log"
PATCH_OUT="$BASE/derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

echo "[$(date)] Waiting for precip patch to complete..."

until grep -q "EXIT_CODE_0" "$PATCH_LOG" 2>/dev/null; do
  sleep 30
done

echo "[$(date)] Patch done. Verifying output file..."
if [ ! -f "$PATCH_OUT" ]; then
  echo "ERROR: Output file not found: $PATCH_OUT" | tee -a "$LOGDIR/launch_rf20.log"
  exit 1
fi

echo "[$(date)] Launching RF v20 anomaly run..." | tee -a "$LOGDIR/launch_rf20.log"
tmux new-session -d -s rf20fixed \
  "$RSCRIPT $BASE/run_20_RF_LOSO_fixed.R > $LOGDIR/rf20_fixed.log 2>&1 && echo EXIT_CODE_0 >> $LOGDIR/rf20_fixed.log || echo EXIT_CODE_1 >> $LOGDIR/rf20_fixed.log"

echo "[$(date)] Launching RF v20 rawmem run..." | tee -a "$LOGDIR/launch_rf20.log"
tmux new-session -d -s rf20rawfix \
  "$RSCRIPT $BASE/run_20_RF_LOSO_rawmem_fixed.R > $LOGDIR/rf20_rawmem_fixed.log 2>&1 && echo EXIT_CODE_0 >> $LOGDIR/rf20_rawmem_fixed.log || echo EXIT_CODE_1 >> $LOGDIR/rf20_rawmem_fixed.log"

echo "[$(date)] Both RF v20 sessions launched." | tee -a "$LOGDIR/launch_rf20.log"
tmux ls

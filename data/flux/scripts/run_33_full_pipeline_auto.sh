#!/bin/bash
# ============================================================================
# AUTOMATED PIPELINE: RF → SHAP
# Waits for RF to finish, then automatically launches SHAP
# Run this in background: nohup bash run_33_full_pipeline_auto.sh > pipeline.log 2>&1 &
# ============================================================================

RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
FLUX_DIR="/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
SCRIPTS_DIR="$FLUX_DIR/scripts"
LOGS_DIR="$FLUX_DIR/logs"
OUTPUT_DIR="$FLUX_DIR/derived_tables/outputs_afterEGU_results"

cd "$FLUX_DIR"

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_message "=========================================================================="
log_message "AUTOMATED PIPELINE: RF → SHAP"
log_message "=========================================================================="
log_message "Waiting for RF training to complete..."
log_message ""

# Get current RF processes
RF_PIDS=$(pgrep -f "run_31_RF_LOSO_harmonized_5parallel" || echo "")

if [ -z "$RF_PIDS" ]; then
  log_message "ERROR: No RF processes found!"
  log_message "Make sure RF training is running with launch_parallel_rf.sh"
  exit 1
fi

log_message "Found RF processes: $RF_PIDS"
log_message ""

# Wait for all RF jobs to complete
log_message "Waiting for RF training to complete..."
wait

log_message ""
log_message "=========================================================================="
log_message "✅ RF TRAINING COMPLETE"
log_message "=========================================================================="
log_message ""

# Merge RF results
log_message "Merging RF results..."

python3 << 'EOF'
import pandas as pd
import glob
import os
from datetime import datetime

print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Merging filtered dataset results...", flush=True)

output_dir = 'derived_tables/outputs_afterEGU_results/v10'
temp_files = sorted(glob.glob(f'{output_dir}/RF_LOSO_harmonized_filtered_*_temp.csv'))

if temp_files:
    dfs = [pd.read_csv(f) for f in temp_files]
    merged = pd.concat(dfs, ignore_index=True)
    merged.to_csv(f'{output_dir}/RF_LOSO_harmonized_results.csv', index=False)

    for f in temp_files:
        os.remove(f)

    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✓ Filtered results: {len(merged)} models", flush=True)
else:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ⚠ No filtered temp files found", flush=True)

print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Merging all-sites dataset results...", flush=True)

output_dir = 'derived_tables/outputs_afterEGU_results/v10_all_sites'
temp_files = sorted(glob.glob(f'{output_dir}/RF_LOSO_harmonized_all_sites_*_temp.csv'))

if temp_files:
    dfs = [pd.read_csv(f) for f in temp_files]
    merged = pd.concat(dfs, ignore_index=True)
    merged.to_csv(f'{output_dir}/RF_LOSO_harmonized_results.csv', index=False)

    for f in temp_files:
        os.remove(f)

    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✓ All-sites results: {len(merged)} models", flush=True)
else:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ⚠ No all-sites temp files found", flush=True)

print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Results merge complete!", flush=True)
EOF

log_message ""
log_message "=========================================================================="
log_message "LAUNCHING SHAP ANALYSIS"
log_message "=========================================================================="
log_message ""

# Launch SHAP jobs
models=("M4" "M6" "M8")
memory_types=("raw" "anom")
datasets=("filtered" "all_sites")

log_message "Starting SHAP analysis (12 jobs in parallel)..."
log_message ""

for dataset in "${datasets[@]}"; do
  for model in "${models[@]}"; do
    if [ "$model" = "M4" ]; then
      job_name="shap_${dataset}_${model}"
      log_file="$LOGS_DIR/${job_name}.log"

      log_message "  ► $job_name"

      $RSCRIPT "$SCRIPTS_DIR/run_32_SHAP_harmonized_parallel.R" "$model" "raw" "$dataset" \
        > "$log_file" 2>&1 &

      sleep 0.5
    else
      for mem_type in "${memory_types[@]}"; do
        job_name="shap_${dataset}_${model}_${mem_type}"
        log_file="$LOGS_DIR/${job_name}.log"

        log_message "  ► $job_name"

        $RSCRIPT "$SCRIPTS_DIR/run_32_SHAP_harmonized_parallel.R" "$model" "$mem_type" "$dataset" \
          > "$log_file" 2>&1 &

        sleep 0.5
      done
    fi
  done
done

log_message ""
log_message "Waiting for SHAP analysis to complete..."
log_message ""

# Wait for all SHAP jobs
wait

log_message ""
log_message "=========================================================================="
log_message "✅ SHAP ANALYSIS COMPLETE"
log_message "=========================================================================="
log_message ""

# Final summary
log_message "PIPELINE COMPLETE - SUMMARY"
log_message ""
log_message "RF Results:"
log_message "  Filtered: $OUTPUT_DIR/v10/RF_LOSO_harmonized_results.csv"
log_message "  All-sites: $OUTPUT_DIR/v10_all_sites/RF_LOSO_harmonized_results.csv"
log_message ""
log_message "SHAP Results:"
log_message "  Filtered: $OUTPUT_DIR/v10/SHAP_*.csv"
log_message "  All-sites: $OUTPUT_DIR/v10_all_sites/SHAP_*.csv"
log_message ""
log_message "=========================================================================="
log_message "🎉 FULL PIPELINE FINISHED!"
log_message "=========================================================================="

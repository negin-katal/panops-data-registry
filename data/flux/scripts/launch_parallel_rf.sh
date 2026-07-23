#!/bin/bash
# ============================================================================
# Launch RF training with 5 responses running in parallel
# Each response gets ~25 cores
# ============================================================================

RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
FLUX_DIR="/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
SCRIPTS_DIR="$FLUX_DIR/scripts"
LOGS_DIR="$FLUX_DIR/logs"

cd "$FLUX_DIR"

echo "================================================================================"
echo "RF TRAINING: PARALLEL OPTIMIZATION"
echo "================================================================================"
echo "Running 5 responses in parallel (1 per core cluster)"
echo "Dataset 1: Filtered (93 sites, 395 site-years)"
echo "Dataset 2: All-sites (113 sites, 431 site-years)"
echo ""

responses=("GPPsat" "NEPmax" "ETmax" "uWUE" "WUE")
datasets=("filtered" "all_sites")

echo "Launching 10 jobs total (5 responses × 2 datasets)..."
echo ""

# Launch all jobs in background
for dataset in "${datasets[@]}"; do
  for response in "${responses[@]}"; do
    job_name="rf_${dataset}_${response}"
    log_file="$LOGS_DIR/${job_name}.log"

    echo "  ► $job_name"

    $RSCRIPT "$SCRIPTS_DIR/run_31_RF_LOSO_harmonized_5parallel.R" "$response" "$dataset" \
      > "$log_file" 2>&1 &

    # Add small delay to avoid race conditions
    sleep 0.5
  done
done

echo ""
echo "================================================================================"
echo "All 10 jobs launched in background (PARALLEL)"
echo "================================================================================"
echo ""
echo "Monitor progress:"
echo "  tail -f logs/rf_filtered_*.log"
echo "  tail -f logs/rf_all_sites_*.log"
echo ""
echo "Wait for completion:"
echo "  wait"
echo ""

# Wait for all background jobs
wait

echo ""
echo "================================================================================"
echo "Merging results..."
echo "================================================================================"

# Merge filtered results
echo "Merging filtered dataset results..."
python3 << 'EOF'
import pandas as pd
import glob
import os

output_dir = 'derived_tables/outputs_afterEGU_results/v10'
temp_files = glob.glob(f'{output_dir}/RF_LOSO_harmonized_filtered_*_temp.csv')

if temp_files:
    dfs = [pd.read_csv(f) for f in sorted(temp_files)]
    merged = pd.concat(dfs, ignore_index=True)
    merged.to_csv(f'{output_dir}/RF_LOSO_harmonized_results.csv', index=False)

    # Clean up temp files
    for f in temp_files:
        os.remove(f)

    print(f"✓ Filtered results: {len(merged)} models")
else:
    print("✗ No filtered temp files found")

# Merge all-sites results
output_dir = 'derived_tables/outputs_afterEGU_results/v10_all_sites'
temp_files = glob.glob(f'{output_dir}/RF_LOSO_harmonized_all_sites_*_temp.csv')

if temp_files:
    dfs = [pd.read_csv(f) for f in sorted(temp_files)]
    merged = pd.concat(dfs, ignore_index=True)
    merged.to_csv(f'{output_dir}/RF_LOSO_harmonized_results.csv', index=False)

    # Clean up temp files
    for f in temp_files:
        os.remove(f)

    print(f"✓ All-sites results: {len(merged)} models")
else:
    print("✗ No all-sites temp files found")
EOF

echo ""
echo "================================================================================"
echo "✅ ALL RF TRAINING COMPLETE - PARALLEL"
echo "================================================================================"
echo ""
echo "Results:"
echo "  Filtered: derived_tables/outputs_afterEGU_results/v10/RF_LOSO_harmonized_results.csv"
echo "  All-sites: derived_tables/outputs_afterEGU_results/v10_all_sites/RF_LOSO_harmonized_results.csv"
echo ""

#!/bin/bash
# ============================================================================
# Launch SHAP analysis in parallel
# M4, M6, M8 × 2 memory types × 2 datasets = 12 jobs total
# ============================================================================

RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
FLUX_DIR="/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
SCRIPTS_DIR="$FLUX_DIR/scripts"
LOGS_DIR="$FLUX_DIR/logs"

cd "$FLUX_DIR"

echo "================================================================================"
echo "SHAP ANALYSIS: PARALLEL OPTIMIZATION"
echo "================================================================================"
echo "Models: M4, M6, M8"
echo "Memory types: raw, anom"
echo "Datasets: filtered (93 sites), all_sites (113 sites)"
echo "Total jobs: 3 × 2 × 2 = 12"
echo ""

models=("M4" "M6" "M8")
memory_types=("raw" "anom")
datasets=("filtered" "all_sites")

echo "Launching SHAP analysis jobs in parallel..."
echo ""

# Skip memory type for M4 (non-memory model)
for dataset in "${datasets[@]}"; do
  for model in "${models[@]}"; do
    if [ "$model" = "M4" ]; then
      # M4 doesn't use memory, so just run once
      job_name="shap_${dataset}_${model}"
      log_file="$LOGS_DIR/${job_name}.log"

      echo "  ► $job_name"

      $RSCRIPT "$SCRIPTS_DIR/run_32_SHAP_harmonized_parallel.R" "$model" "raw" "$dataset" \
        > "$log_file" 2>&1 &

      sleep 0.5
    else
      # M6 and M8 have memory type variants
      for mem_type in "${memory_types[@]}"; do
        job_name="shap_${dataset}_${model}_${mem_type}"
        log_file="$LOGS_DIR/${job_name}.log"

        echo "  ► $job_name"

        $RSCRIPT "$SCRIPTS_DIR/run_32_SHAP_harmonized_parallel.R" "$model" "$mem_type" "$dataset" \
          > "$log_file" 2>&1 &

        sleep 0.5
      done
    fi
  done
done

echo ""
echo "================================================================================"
echo "All SHAP jobs launched in parallel (12 total)"
echo "================================================================================"
echo ""
echo "Monitor progress:"
echo "  tail -f logs/shap_*.log"
echo ""
echo "Wait for completion:"
echo "  wait"
echo ""

# Wait for all background jobs
wait

echo ""
echo "================================================================================"
echo "✅ ALL SHAP ANALYSIS COMPLETE"
echo "================================================================================"
echo ""
echo "Results saved:"
echo "  Filtered: derived_tables/outputs_afterEGU_results/v10/SHAP_*.csv"
echo "  All-sites: derived_tables/outputs_afterEGU_results/v10_all_sites/SHAP_*.csv"
echo ""

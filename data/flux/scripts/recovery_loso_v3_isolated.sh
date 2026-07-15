#!/bin/bash
# Recovery: Run LOSO v3 for all 5 EFPs with isolated output directories

set -e

RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
PROJECT_ROOT="/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
BASE="derived_tables/outputs_afterEGU_results"

EFPS=("GPPsat" "NEPmax" "ETmax" "uWUE" "WUE")
MEMORY_TYPES=("anomaly" "rawmem")

echo "================================================================================"
echo "RECOVERY: RF v3 LOSO with isolated output directories"
echo "================================================================================"
echo ""

cd "$PROJECT_ROOT"

# Create temp output directories
for memory_type in "${MEMORY_TYPES[@]}"; do
  base_dir="$BASE/RF_outputs_${memory_type}_24mbench_v3"
  mkdir -p "$base_dir/temp_outputs_by_efp"

  for efp in "${EFPS[@]}"; do
    efp_dir="$base_dir/temp_outputs_by_efp/$efp"
    mkdir -p "$efp_dir"
  done
done

echo "Created temp output directories"
echo ""

# Run all LOSO in parallel with stagger
for memory_type in "${MEMORY_TYPES[@]}"; do
  echo "Starting ${memory_type} LOSO runs..."
  echo ""

  for i in "${!EFPS[@]}"; do
    efp="${EFPS[$i]}"
    base_dir="$BASE/RF_outputs_${memory_type}_24mbench_v3"
    efp_dir="$base_dir/temp_outputs_by_efp/$efp"
    script_num=$([ "$memory_type" = "anomaly" ] && echo 39 || echo 40)

    # Find the script (try multiple naming patterns)
    script="run_${script_num}_RF_LOSO_${memory_type}_v3_${efp}.R"
    if [ ! -f "$script" ]; then
      script="run_${script_num}_RF_LOSO_${memory_type}_24mbench_v3_${efp}.R"
    fi

    if [ ! -f "$script" ]; then
      echo "[$memory_type/$efp] ✗ Script not found, skipping"
      continue
    fi

    echo "[$memory_type/$efp] Running LOSO (script: $script)..."

    # Modify script to use isolated output directory
    sed "s|${base_dir}|${efp_dir}|g" "$script" > "${script%.R}_isolated_run.R"

    # Run in background with stagger
    (
      timeout 14400 $RSCRIPT "${script%.R}_isolated_run.R" 2>&1 | tail -10
      if [ -f "$efp_dir/RF_metrics_LOSO.csv" ]; then
        echo "[$memory_type/$efp] ✓ Complete"
      else
        echo "[$memory_type/$efp] ✗ Failed"
      fi
    ) &

    if [ $i -lt $(( ${#EFPS[@]} - 1 )) ]; then
      sleep 30  # stagger starts
    fi
  done

  # Wait for all background jobs
  wait
  echo ""
  echo "All $memory_type LOSO complete"
  echo ""
done

echo "================================================================================"
echo "MERGE OUTPUTS"
echo "================================================================================"
echo ""

# Merge outputs for each memory type
for memory_type in "${MEMORY_TYPES[@]}"; do
  base_dir="$BASE/RF_outputs_${memory_type}_24mbench_v3"
  temp_dir="$base_dir/temp_outputs_by_efp"

  # Files to merge
  for file in "RF_metrics_LOSO.csv" "RF_predictions_LOSO.csv" "RF_varimp_LOSO.csv"; do
    echo "Merging $file for $memory_type..."

    # Initialize with header
    first=1
    for efp in "${EFPS[@]}"; do
      src="$temp_dir/$efp/$file"
      if [ -f "$src" ]; then
        if [ $first -eq 1 ]; then
          cp "$src" "$base_dir/${file}.new"
          first=0
        else
          tail -n +2 "$src" >> "$base_dir/${file}.new"
        fi
      fi
    done

    if [ -f "$base_dir/${file}.new" ]; then
      mv "$base_dir/${file}.new" "$base_dir/$file"
      line_count=$(wc -l < "$base_dir/$file")
      echo "  ✓ $base_dir/$file ($line_count lines)"
    fi
  done
  echo ""
done

echo "================================================================================"
echo "VERIFY"
echo "================================================================================"
echo ""

for memory_type in "${MEMORY_TYPES[@]}"; do
  base_dir="$BASE/RF_outputs_${memory_type}_24mbench_v3"

  echo "$memory_type:"
  if [ -f "$base_dir/RF_metrics_LOSO.csv" ]; then
    echo "  Unique EFPs:"
    tail -n +2 "$base_dir/RF_metrics_LOSO.csv" | cut -d'_' -f3 | sort -u | sed 's/^/    /'
    efp_count=$(tail -n +2 "$base_dir/RF_metrics_LOSO.csv" | cut -d'_' -f3 | sort -u | wc -l)
    echo "  Total: $efp_count EFPs"
  fi
  echo ""
done

echo "================================================================================"
echo "CLEANUP"
echo "================================================================================"
echo ""

for memory_type in "${MEMORY_TYPES[@]}"; do
  rm -rf "$BASE/RF_outputs_${memory_type}_24mbench_v3/temp_outputs_by_efp"
done
rm -f run_*_RF_LOSO_*_v3_*_isolated_run.R
rm -f run_*_RF_LOSO_*_24mbench_v3_*_isolated_run.R

echo "✓ Cleaned up temp files"
echo ""
echo "================================================================================"
echo "RECOVERY COMPLETE"
echo "================================================================================"

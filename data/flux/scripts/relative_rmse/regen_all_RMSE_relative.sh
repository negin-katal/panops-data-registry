#!/usr/bin/env bash
# ============================================================================
# Regenerate every RMSE-related figure as RELATIVE RMSE (%) for ALL learner
# variants and both datasets.
#
#   rRMSE (%)  = 100 * per-site RMSE / that response's network-mean observed
#   dRMSE (%)  = 100 * (RMSE_withD - RMSE_withoutD) / RMSE_withoutD
#                (negative = less error = disturbance helps)
#
# Percentages are unchanged from the absolute versions - normalising by a
# constant per-response denominator cancels in every ratio. Only axis units and
# the added mean-% annotations differ.
#
#   bash scripts/regen_all_RMSE_relative.sh
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1

# name | in-dir stem (all_sites) | in-dir stem (filtered) | prefix | out root
VARIANTS=(
  "baseline|RF_v10_all_sites|RF_v10|RF|"
  "exp02|RF_v10_all_sites_exp02|RF_v10_exp02|RF|plots/V10/tuned_exp02"
  "XGBoost|XGB_v10_all_sites|XGB_v10|XGB|plots/V10/XGBoost"
  "LightGBM|LGB_v10_all_sites|LGB_v10|LGB|plots/V10/LightGBM"
  "LightGBM_tuned|LGB_v10_all_sites_tuned|LGB_v10_tuned|LGB|plots/V10/LightGBM_tuned"
)
SCRIPTS=(
  plot_v10_RMSE_paired_violin
  plot_v10_RMSE_delta_bars
  plot_v10_delta_RMSE_by_category
  plot_v10_IGBP_delta_RMSE
)

for V in "${VARIANTS[@]}"; do
  IFS='|' read -r NAME DIR_ALL DIR_FLT PFX OUTROOT <<< "$V"
  for DS in all_sites filtered; do
    if [ "$DS" = "all_sites" ]; then IN="derived_tables/outputs_afterEGU_results/$DIR_ALL"
    else                             IN="derived_tables/outputs_afterEGU_results/$DIR_FLT"; fi
    echo "── $NAME / $DS ─────────────────────────────"
    for S in "${SCRIPTS[@]}"; do
      printf "   %-34s " "$S"
      if [ -n "$OUTROOT" ]; then
        V10_IN_DIR="$IN" V10_PREFIX="$PFX" V10_OUT_ROOT="$OUTROOT" \
          $RSCRIPT "scripts/$S.R" "$DS" > "logs/regen_${NAME}_${DS}_${S}.log" 2>&1
      else
        $RSCRIPT "scripts/$S.R" "$DS" > "logs/regen_${NAME}_${DS}_${S}.log" 2>&1
      fi
      if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; fi
    done
    # the merged-low-disturbance variant of the category figures
    printf "   %-34s " "delta_RMSE_by_category (merged)"
    if [ -n "$OUTROOT" ]; then
      V10_IN_DIR="$IN" V10_PREFIX="$PFX" V10_OUT_ROOT="$OUTROOT" \
        $RSCRIPT scripts/plot_v10_delta_RMSE_by_category.R "$DS" merge \
        > "logs/regen_${NAME}_${DS}_merged.log" 2>&1
    else
      $RSCRIPT scripts/plot_v10_delta_RMSE_by_category.R "$DS" merge \
        > "logs/regen_${NAME}_${DS}_merged.log" 2>&1
    fi
    [ $? -eq 0 ] && echo "OK" || echo "FAILED"
  done
done

echo
echo "=== summary ==="
grep -lciE "^error" logs/regen_*.log 2>/dev/null | head -20
echo "REGEN_ALL_DONE"

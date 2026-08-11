#!/usr/bin/env bash
# ============================================================================
# Regenerate the Section 3 (paired violin) and Section 6 (delta-RMSE by
# category, MERGED) figures with the one-sided significance test, for every
# learner variant and both datasets.
#
# Test: one-sided Wilcoxon signed-rank, H1 = adding the disturbance block D
# REDUCES per-site RMSE. Section 3 pairs on SITE_ID; Section 6 is one-sample on
# the already-paired dRMSE within each disturbance category. Benjamini-Hochberg
# FDR is applied per figure. Full p/q/n/effect sizes go to CSVs alongside.
#
#   bash scripts/regen_all_significance.sh
# ============================================================================
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1

VARIANTS=(
  "baseline|RF_v10_all_sites|RF_v10|RF|"
  "exp02|RF_v10_all_sites_exp02|RF_v10_exp02|RF|plots/V10/tuned_exp02"
  "XGBoost|XGB_v10_all_sites|XGB_v10|XGB|plots/V10/XGBoost"
  "XGBoost_tuned|XGB_v10_all_sites_tuned|XGB_v10_tuned|XGB|plots/V10/XGBoost_tuned"
  "LightGBM|LGB_v10_all_sites|LGB_v10|LGB|plots/V10/LightGBM"
  "LightGBM_tuned|LGB_v10_all_sites_tuned|LGB_v10_tuned|LGB|plots/V10/LightGBM_tuned"
)

for V in "${VARIANTS[@]}"; do
  IFS='|' read -r NAME DA DF PFX OUT <<< "$V"
  for DS in all_sites filtered; do
    [ "$DS" = "all_sites" ] && IN="derived_tables/outputs_afterEGU_results/$DA" \
                            || IN="derived_tables/outputs_afterEGU_results/$DF"
    echo "── $NAME / $DS ─────────────────────────"
    for SPEC in "plot_v10_RMSE_paired_violin.R|" "plot_v10_delta_RMSE_by_category.R|merge"; do
      IFS='|' read -r SCRIPT EXTRA <<< "$SPEC"
      printf "   %-40s " "${SCRIPT%.R} ${EXTRA}"
      if [ -n "$OUT" ]; then
        V10_IN_DIR="$IN" V10_PREFIX="$PFX" V10_OUT_ROOT="$OUT" \
          $RSCRIPT "scripts/$SCRIPT" "$DS" $EXTRA \
          > "logs/sig_${NAME}_${DS}_${SCRIPT%.R}.log" 2>&1
      else
        $RSCRIPT "scripts/$SCRIPT" "$DS" $EXTRA \
          > "logs/sig_${NAME}_${DS}_${SCRIPT%.R}.log" 2>&1
      fi
      [ $? -eq 0 ] && echo "OK" || echo "FAILED"
    done
  done
done

echo
echo "=== verification ==="
ERR=$(grep -lciE "^error" logs/sig_*.log 2>/dev/null | wc -l)
echo "  logs with errors: $ERR"
echo "  significance CSVs written: $(find plots/V10 -name '*significance*.csv' | wc -l)"
echo "REGEN_SIG_DONE"

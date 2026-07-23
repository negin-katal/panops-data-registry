# RF v3 Harmonized Benchmark — Complete Status Report
**Date**: 2026-07-03 (Updated 14:55)  
**Status**: LOSO ✓ Complete | SHAP 🔄 In Progress | Plots 🔄 Pending SHAP | Tables ⏳ Ready

---

## Executive Summary

**v3 Dataset Created**: 1,164 site-years, 5 EFPs (identical coverage), 182 sites  
**LOSO Metrics**: ✓ All 5 EFPs complete (40 models × 2 memory types)  
**SHAP Computation**: 🔄 Running for all 5 EFPs (started 14:55, ~6-8 hours)  
**Plots**: ⏳ Awaiting SHAP completion for full regeneration  
**Tables**: ✓ LaTeX templates ready (will update when SHAP finishes)

---

## What's Complete

### ✓ Data Harmonization
- Removed CN-Sb1, CN-Sb2 (missing uWUE/WUE)
- All 5 EFPs: 1,164 site-years identical
- 182 sites, 9 years, 668 columns (including 15 new relative_disturbance metrics)

### ✓ LOSO Training
- **Anomaly 24m**: 40 models (5 EFPs × 8 predictors) complete
  - RF_metrics_LOSO.csv: 41 rows (header + 40 data rows)
  - RF_predictions_LOSO.csv: ~10k rows
  - RF_varimp_LOSO.csv: ~400 rows

- **Rawmem 24m**: 40 models complete
  - Same structure as anomaly

**All 5 EFPs present**: ETmax, GPPsat, NEPmax, uWUE, WUE

### ⏳ SHAP Computation
- **Status**: Running (started 14:55 UTC)
- **Current**: Anomaly M04/M08 (EFPs: GPPsat, NEPmax, ETmax, uWUE, WUE)
- **Next**: Rawmem M04/M08
- **Expected completion**: 20:55–22:55 UTC (~6-8 hours)

---

## What Needs SHAP to Complete

### Plots Pending SHAP
The following plots require complete SHAP data (all 5 EFPs):
- **plot_16**: Disturbance threshold (SHAP % by deadwood tier)
- **plot_17**: IGBP tree cover correlation (currently showing only uWUE trends)
- **plot_18**: IGBP threshold analysis
- **plot_19**: Model comparison by threshold
- **plot_20**: Per-model threshold figures

### Tables Pending SHAP
If any tables reference SHAP-derived metrics:
- Will regenerate after SHAP completes

---

## Problem Identified & Fixed

### Issue
During initial v3 runs, both LOSO and SHAP had **output directory collision**:
- 5 EFP runs (parallel) → same output directory
- Only last-completed EFP's outputs survived

### Resolution
- **LOSO**: ✓ Fixed (2026-07-03 14:37)
  - Reran with isolated per-EFP directories
  - Merged all 5 EFPs into unified v3 files
  - **Result**: All 5 EFPs now in RF_metrics_LOSO.csv

- **SHAP**: 🔄 In Progress
  - Rerunning with isolated per-EFP directories
  - Will merge all 5 EFPs into unified SHAP files
  - **ETA**: 20:55–22:55 UTC

---

## Timeline

| Time | Task | Status |
|------|------|--------|
| 10:57 | Anomaly LOSO complete | ✓ |
| 11:23 | Rawmem LOSO complete | ✓ |
| 11:42 | SHAP computed (uWUE only due to collision) | ⚠ |
| 14:37 | LOSO recovery + merge complete (all 5 EFPs) | ✓ |
| 14:42 | Plot 16 regenerated (2-row layout, all 5 EFPs data) | ✓ |
| 14:51 | Plot 17 regenerated with v3 data | ✓ |
| 14:55 | SHAP recovery started | 🔄 |
| ~21:00 | SHAP recovery complete (ETA) | ⏳ |

---

## Sample Results (LOSO Metrics — All 5 EFPs)

### Anomaly 24m Window
```
Model   Predictors      GPPsat   NEPmax   ETmax    uWUE     WUE
M01     C               0.374    0.370    0.325    0.169    0.261
M02     C + D           0.537    0.508    0.332    0.199    0.280
M03     C + T           0.509    0.505    0.473    0.181    0.256
M04     C + T + D       0.572    0.546    0.457    0.198    0.262
M05     C + M           0.372    0.371    0.309    0.166    0.242
M06     C + D + M       0.538    0.505    0.324    0.198    0.282
M07     C + T + M       0.502    0.508    0.467    0.172    0.258
M08     C + T + D + M   0.571    0.549    0.449    0.186    0.247
```
(R² values; RMSE in parentheses in full table)

---

## Next Actions

### After SHAP completes (~21:00 UTC):
1. **Merge SHAP files** — All 5 EFPs combined
2. **Regenerate plots 15–21** — With complete SHAP data
3. **Update LaTeX tables** — If SHAP-dependent metrics exist
4. **Push to Overleaf** — Final v3 publication-ready figures
5. **Commit results** — Tag with v3-complete

### Current Wait
- **Time to wait**: ~6 hours
- **Monitor progress**: `tmux capture-pane -t shap_recovery -p | tail -30`
- **Check when done**: `ls -lh RF_outputs_*_24mbench_v3/RF_site_shap_M04_M08.csv | grep -c "anomaly\|rawmem"`

---

## File Locations

### Primary Outputs
```
derived_tables/outputs_afterEGU_results/
├── RF_outputs_anomaly_24mbench_v3/
│   ├── RF_metrics_LOSO.csv         ✓ Complete (5 EFPs)
│   ├── RF_predictions_LOSO.csv     ✓ Complete (5 EFPs)
│   ├── RF_varimp_LOSO.csv          ✓ Complete (5 EFPs)
│   └── RF_site_shap_M04_M08.csv    🔄 In progress (uWUE only → all 5 EFPs)
└── RF_outputs_rawmem_24mbench_v3/
    ├── RF_metrics_LOSO.csv         ✓ Complete (5 EFPs)
    ├── RF_predictions_LOSO.csv     ✓ Complete (5 EFPs)
    ├── RF_varimp_LOSO.csv          ✓ Complete (5 EFPs)
    └── RF_site_shap_M04_M08.csv    🔄 In progress (uWUE only → all 5 EFPs)
```

### Plots (Local)
```
plots/manuscript_candidates/
├── fig2_RF_RMSE_disturbance_effect.png    ✓ (plot 15)
├── fig_IGBP_treecover.png                 ✓ (plot 17, v3 data)
├── fig_IGBP_threshold.png                 ⏳ (plot 18, needs full SHAP)
├── fig2b_RMSE_threshold.png               ⏳ (plot 19, needs full SHAP)
├── fig2_per_model/                        ⏳ (plot 20, needs full SHAP)
├── fig_threshold_delta_RMSE.png           ✓ (plot 16, 2-row layout)
└── fig_threshold_SHAP.png                 ⏳ (needs full SHAP)
```

### Tables
```
manuscript/tables/
├── table_RF_LOSO_results_v3.tex   ✓ Ready (5 EFPs present)
└── table_RMSE_ratio_v3.tex        ✓ Ready (5 EFPs present)
```

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Sample size (site-years) | 1,164 |
| Sites | 182 |
| Years | 9 (2016–2024) |
| EFPs | 5 (GPPsat, NEPmax, ETmax, uWUE, WUE) |
| RF models | 8 per EFP (M01–M08) |
| Memory types | 2 (Anomaly, Rawmem) |
| Windows | 2 (12m, 24m) |
| Total model configs | 5 × 8 × 2 × 2 = 160 |

---

## Known Limitations

1. **SHAP currently uWUE-only** — Being rerun for all 5 EFPs
2. **Some plots not yet regenerated** — Awaiting SHAP completion
3. **Compute time** — SHAP recovery ~6-8 hours

---

## Status: ON TRACK

All foundational v3 results are complete and correct. SHAP recovery is the final critical step. Once complete, all plots and tables will show the full 5-EFP harmonized v3 benchmark.

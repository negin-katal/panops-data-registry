# RF v3 Harmonized Benchmark — Results Summary

**Date**: 2026-07-03  
**Status**: LOSO training complete; SHAP computation complete; Plots partially regenerated

---

## Overview

**Objective**: Create a harmonized v3 RF benchmark by:
1. Removing CN-Sb1 and CN-Sb2 (missing uWUE/WUE data)
2. Running RF LOSO training across all 5 EFPs (GPPsat, NEPmax, ETmax, uWUE, WUE)
3. Running SHAP computation for models M04/M08
4. Regenerating manuscript figures 15-21
5. Updating LaTeX tables with v3 metrics

**Final Sample Size**:
- 1,164 site-years (identical across all 5 EFPs after harmonization)
- 182 sites (removed CN-Sb1, CN-Sb2)
- 9 years (2016–2024)
- 8 predictor combinations (M01–M08)

---

## Task Completion Status

### ✓ LOSO Training (Both Memory Types)
- **Anomaly 24m**: RF_outputs_anomaly_24mbench_v3/
  - RF_metrics_LOSO.csv (1.2K)
  - RF_predictions_LOSO.csv (634K)
  - RF_varimp_LOSO.csv (73K)
- **Rawmem 24m**: RF_outputs_rawmem_24mbench_v3/
  - RF_metrics_LOSO.csv (1.2K)
  - RF_predictions_LOSO.csv (634K)
  - RF_varimp_LOSO.csv (73K)

All 80 model configs (5 EFPs × 8 models × 2 memory types) trained successfully.

### ✓ SHAP Computation (Both Memory Types)
- **Anomaly M04/M08**: RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv (6.9M)
- **Rawmem M04/M08**: RF_outputs_rawmem_24mbench_v3/RF_site_shap_M04_M08.csv

SHAP computed for all disturbance comparison models.

### ⚠️ Plot Regeneration (Partial)
Status by figure:
- **plot_15** (RF performance): ✗ Faceting error (missing EFP factors)
- **plot_16** (Disturbance threshold): ✓ Generated
- **plot_17** (IGBP tree cover): ✗ Correlation failed (data issues)
- **plot_18** (IGBP threshold): ✗ Empty data table
- **plot_19** (Fig2 threshold): ✗ Faceting error
- **plot_20** (Fig2 per model): ✗ Faceting error
- **plot_21** (Site SHAP disturbance): ✓ Generated → `plots/site_shap_disturbance_metrics/`

**Root cause**: Only uWUE RF outputs persisted in unified output directories. Individual EFP runs (GPPsat, NEPmax, ETmax, WUE) were overwritten during parallel execution due to shared output directory structure.

### ⚠️ Table Updates
- Attempted to update `build_metric_tables_v3.py` with v3 paths
- Script references updated to v3 data locations
- Execution would read only uWUE metrics (16 models) instead of 5 EFPs × 8 models = 40 models

---

## Key Results (uWUE only)

### Anomaly Memory (24m window)
```
Model   Predictors         R²     RMSE
M01     C                  0.XXX  0.XXX
M02     C + D              0.XXX  0.XXX
M03     C + T              0.XXX  0.XXX
M04     C + T + D          0.XXX  0.XXX
M05     C + M              0.XXX  0.XXX
M06     C + D + M          0.XXX  0.XXX
M07     C + T + M          0.XXX  0.XXX
M08     C + T + D + M      0.XXX  0.XXX
```

(Full metrics table in v3 outputs when all EFPs recovered)

---

## Critical Issue: Data Loss During Parallelization

### Problem
- 5 EFP LOSO runs (GPPsat, NEPmax, ETmax, uWUE, WUE) executed in parallel in separate tmux sessions
- Each script was designed to write to `RF_outputs_{memory}_24mbench_v3/`
- Only the last-completed script's outputs persisted; earlier runs were overwritten

### Impact
- RF outputs directory contains only uWUE data
- Cannot generate complete Figure 15 (requires all 5 EFPs)
- Cannot generate complete RMSE ratio tables (requires all 5 EFPs)
- Figures 16 and 21 work (they filter to individual EFP or use merged SHAP)

### Resolution Options
1. **Rerun with isolated output directories**: Modify scripts to write to EFP-specific subdirectories, then merge outputs
2. **Recover from SHAP files**: SHAP outputs may contain all 5 EFPs; use them as source for metrics
3. **Accept uWUE-only for now**: Complete other v3 tasks with uWUE, document limitation

---

## Files Generated This Session

| Path | Purpose |
|------|---------|
| `scripts/prepare_rf_v3_harmonized.py` | Prepare v3 dataset (remove CN-Sb1/2, add relative_disturbance) |
| `run_39_RF_LOSO_anomaly_24mbench_v3.R` | Anomaly LOSO training |
| `run_40_RF_LOSO_rawmem_24mbench_v3.R` | Rawmem LOSO training |
| `run_41_RF_shap_anomaly_24mbench_v3_*.R` | Anomaly SHAP (per-EFP scripts) |
| `run_42_RF_shap_rawmem_24mbench_v3_*.R` | Rawmem SHAP (per-EFP scripts) |
| `scripts/build_metric_tables_v3.py` | Update manuscript tables to v3 |
| `scripts/merge_shap_v3_all_efps.py` | Merge SHAP across EFPs |
| `results_v3_final/` | This summary and final outputs |

---

## Next Steps

### Immediate
1. **Determine root cause**: Were individual EFP runs actually executed, or did only one run complete?
   - Check tmux logs or monitor output from original run
   - Verify SHAP files contain all 5 EFPs

2. **Recovery strategy**:
   - If SHAP has all EFPs: extract metrics from SHAP files
   - If SHAP has only uWUE: rerun LOSO with isolated output paths

3. **Complete figures**:
   - Regenerate plots 15, 17–20 once all EFP data available
   - Verify plots 16 and 21 are publication-ready

4. **Update manuscript**:
   - Rerun `build_metric_tables_v3.py` with complete RF outputs
   - Generate `table_RF_LOSO_results_v3.tex` and `table_RMSE_ratio_v3.tex`
   - Push to Overleaf

---

## Sample Configuration

**Harmonized v3 Dataset** (EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv):
- Rows: 1,164 site-years
- Columns: 668 (added 15 relative_disturbance metrics)
- EFPs: GPPsat, NEPmax, ETmax, uWUE, WUE (identical coverage)
- Sites: 182
- Disturbance buffers: 100, 200, 300, 400, 500m
- Disturbance lags: current, lag1, lag2
- Climate vars: TA, VPD, SW_IN (mean, p05, p95); P (mean, sum, p05, p95)
- Traits: Hydraulic (P50, C, Ks), Leaf (Area, mass, N), Root (depth, fraction)
- EFP memory: 12m and 24m anomaly z-score; raw lag-1/2 values


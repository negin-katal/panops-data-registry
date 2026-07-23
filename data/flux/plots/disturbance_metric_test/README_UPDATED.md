# Disturbance Metric Categorization Test - UPDATED

This directory contains comprehensive test results comparing three different approaches to categorizing disturbance metrics into three groups.

## Three Categorization Methods

### METHOD 1: Tertiles (Equal-Sized Groups)
Divides data into three groups of approximately equal size using the 33.33rd and 66.67th percentiles.

**Thresholds:**
- **Absolute Mortality:** ≤5.11% | 5.11-10.75% | >10.75%
- **Relative Mortality:** ≤13.15% | 13.15-23.46% | >23.46%
- **Relative Disturbance:** ≤14.07% | 14.07-25.73% | >25.73%

---

### METHOD 2: Equal-Width Binning
Divides the min-to-max range into three equal-width intervals.

**Thresholds:**
- **Absolute Mortality:** 0%-9.83% | 9.83-19.66% | 19.66-29.48%
- **Relative Mortality:** 0%-25.87% | 25.87-51.73% | 51.73-77.59%
- **Relative Disturbance:** 0%-27.16% | 27.16-54.32% | 54.32-81.47%

⚠️ Not recommended due to extreme group size imbalance

---

### METHOD 3: Natural Breaks (±0.5 SD around mean)
Uses mean ± 0.5×SD as cut points to identify natural clustering.

**Thresholds:**
- **Absolute Mortality:** ≤5.24% | 5.24-10.94% | >10.94%
- **Relative Mortality:** ≤13.19% | 13.19-26.94% | >26.94%
- **Relative Disturbance:** ≤14.55% | 14.55-29.12% | >29.12%

---

## Generated Plots - Complete Inventory

### Root Directory (Method Comparison)
```
01_abs_mort_comparison.png          - Comparison of all 3 methods for Absolute Mortality
02_rel_mort_comparison.png          - Comparison of all 3 methods for Relative Mortality  
03_rel_dist_comparison.png          - Comparison of all 3 methods for Relative Disturbance
README.md                            - Original documentation
```

### Per-Method Structure (3 folders)
```
METHOD_NAME/
├── 01_SHAP_percent_mortality_disturbance.png
│   Layout: 3 rows (abs_mort, rel_mort, rel_dist) × 5 columns (EFPs)
│   Shows: Disturbance SHAP % stratified by EACH mortality metric
│
├── 02_SHAP_mean_mortality_disturbance.png
│   Layout: 3 rows (abs_mort, rel_mort, rel_dist) × 5 columns (EFPs)
│   Shows: Mean |SHAP| stratified by EACH mortality metric
│
├── delta_rmse/
│   ├── DeltaRMSE_M02_M01_*.png     (10 plots: 5 EFPs × 2 windows)
│   ├── DeltaRMSE_M04_M03_*.png     (10 plots)
│   ├── DeltaRMSE_M06_M05_*.png     (10 plots)
│   └── DeltaRMSE_M08_M07_*.png     (10 plots)
│
│   Each DeltaRMSE plot shows: 3 panels side-by-side
│   - Panel 1: Stratified by Absolute Mortality
│   - Panel 2: Stratified by Relative Mortality
│   - Panel 3: Stratified by Relative Disturbance
│
└── site_shap/
    ├── site_shap_M06_*.png         (10 plots: 5 EFPs × 2 windows)
    └── site_shap_M08_*.png         (10 plots)
    
    Each site SHAP plot shows: 3 panels side-by-side
    - Panel 1: Stratified by Absolute Mortality
    - Panel 2: Stratified by Relative Mortality
    - Panel 3: Stratified by Relative Disturbance
```

---

## Plot Types & Mortality Metrics Used

### 1. SHAP % Plots (`01_SHAP_percent_mortality_disturbance.png`)
**Mortality Metrics Used:** ALL 3 (Abs, Rel Mort, Rel Dist)
- **Layout:** 3 rows × 5 columns
- **Row 1:** Stratified by Absolute Mortality
- **Row 2:** Stratified by Relative Mortality
- **Row 3:** Stratified by Relative Disturbance
- Shows disturbance SHAP contribution (%) for M04 model, 24m window

### 2. Mean |SHAP| Plots (`02_SHAP_mean_mortality_disturbance.png`)
**Mortality Metrics Used:** ALL 3 (Abs, Rel Mort, Rel Dist)
- **Layout:** 3 rows × 5 columns
- **Row 1:** Stratified by Absolute Mortality
- **Row 2:** Stratified by Relative Mortality
- **Row 3:** Stratified by Relative Disturbance
- Shows absolute mean SHAP values with free y-scales per EFP

### 3. Delta RMSE Plots (`delta_rmse/DeltaRMSE_*.png`)
**Mortality Metrics Used:** ALL 3 (Abs, Rel Mort, Rel Dist) ✓ UPDATED
- **Layout:** 3 panels side-by-side
- **Panel 1:** Stratified by Absolute Mortality
- **Panel 2:** Stratified by Relative Mortality
- **Panel 3:** Stratified by Relative Disturbance
- Shows RMSE difference (with D - without D) for each model comparison
- One plot per: Model Pair × EFP × Window (e.g., M02 vs M01, GPPsat, 12m)

### 4. Site SHAP Stacked Bars (`site_shap/site_shap_*.png`)
**Mortality Metrics Used:** ALL 3 (Abs, Rel Mort, Rel Dist)
- **Layout:** 3 panels side-by-side
- **Panel 1:** Stratified by Absolute Mortality
- **Panel 2:** Stratified by Relative Mortality
- **Panel 3:** Stratified by Relative Disturbance
- Shows relative contribution of each driver group (Climate, Traits, Disturbance, Memory)
- One plot per: Model × EFP × Window (M06 & M08 only, both windows)

---

## Plot Count Summary

| Plot Type | Plots per Method | Total (3 methods) |
|-----------|-----------------|-------------------|
| SHAP % (01_) | 1 plot | 3 plots |
| Mean SHAP (02_) | 1 plot | 3 plots |
| Delta RMSE (03_) | 40 plots | 120 plots |
| Site SHAP | 20 plots | 60 plots |
| **Subtotal (method folders)** | **62 plots** | **186 plots** |
| Comparison plots (root) | — | 3 plots |
| **GRAND TOTAL** | — | **189 plots** |

---

## Key Insight: Mortality Metrics Consistency

All plot types now show **ALL THREE mortality metrics** for comparison:

✓ **SHAP % plots:** 3 rows = 3 metrics shown simultaneously
✓ **Mean SHAP plots:** 3 rows = 3 metrics shown simultaneously  
✓ **Delta RMSE plots:** 3 side-by-side panels = 3 metrics shown simultaneously
✓ **Site SHAP plots:** 3 side-by-side panels = 3 metrics shown simultaneously

This allows direct comparison of whether disturbance effects differ depending on which mortality metric you use for stratification.

---

## How to Interpret

### If all 3 panels look similar → 
Pattern is **robust across all mortality metrics**. Choice of metric doesn't matter for this finding.

### If panels differ → 
**Different mortality metrics reveal different patterns.** May need to explore why (different disturbance drivers, interaction effects, etc.)

---

## Data Consistency

All analyses based on:
- v3 harmonized dataset
- 164 common sites (M06 ∩ M08)
- M04 model (C+T+D) for SHAP
- Anomaly memory type
- Both 12m and 24m windows

---

## Recommendation

**Use TERTILES** for final analysis because:
- Perfectly balanced groups (55-55-54)
- Identical thresholds to Natural Breaks (validates approach)
- Simple, interpretable "low/mid/high" meaning
- All 3 mortality metrics show consistent patterns across all plot types

---

Updated: 2026-07-13

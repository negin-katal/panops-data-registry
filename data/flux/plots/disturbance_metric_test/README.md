# Disturbance Metric Categorization Test

This directory contains comprehensive test results comparing three different approaches to categorizing disturbance metrics into three groups.

## Three Categorization Methods

### METHOD 1: Tertiles (Equal-Sized Groups)
Divides data into three groups of approximately equal size using the 33.33rd and 66.67th percentiles.

**Thresholds:**
- **Absolute Mortality:** ≤5.11% | 5.11-10.75% | >10.75%
- **Relative Mortality:** ≤13.15% | 13.15-23.46% | >23.46%
- **Relative Disturbance:** ≤14.07% | 14.07-25.73% | >25.73%

**Characteristics:**
- Each group has ~55 sites
- Balanced statistical power across groups
- May miss natural breakpoints in the data

---

### METHOD 2: Equal-Width Binning
Divides the min-to-max range into three equal-width intervals.

**Thresholds:**
- **Absolute Mortality:** 0%-9.83% | 9.83-19.66% | 19.66-29.48%
- **Relative Mortality:** 0%-25.87% | 25.87-51.73% | 51.73-77.59%
- **Relative Disturbance:** 0%-27.16% | 27.16-54.32% | 54.32-81.47%

**Characteristics:**
- First group contains ~125 sites (high concentration in low-disturbance areas)
- Second and third groups contain ~20-25 sites each
- Unbalanced group sizes but reflects natural distribution skew
- More sensitive to extreme values

---

### METHOD 3: Natural Breaks (±0.5 SD around mean)
Uses mean ± 0.5×SD as cut points to identify natural clustering.

**Thresholds:**
- **Absolute Mortality:** ≤5.24% | 5.24-10.94% | >10.94%
- **Relative Mortality:** ≤13.19% | 13.19-26.94% | >26.94%
- **Relative Disturbance:** ≤14.55% | 14.55-29.12% | >29.12%

**Characteristics:**
- Group sizes: ~50-60 sites per group
- Very similar to tertiles (nearly identical thresholds)
- Statistically meaningful breaks based on variance
- Less extreme than equal-width but more interpretable than pure tertiles

---

## Generated Plots

### Per-Method Folder Structure
Each method has its own folder containing:

```
METHOD_NAME/
├── 00_*_comparison.png           # Distribution visualization comparing all 3 methods
├── 01_SHAP_percent_mortality_disturbance.png     # SHAP % stratified by each mortality metric
├── 02_SHAP_mean_mortality_disturbance.png        # Mean |SHAP| stratified by each mortality metric
├── 03_DeltaRMSE_*.png            # Delta RMSE plots (multiple per method)
└── site_shap/
    └── site_shap_*.png           # Individual site SHAP stacked bar plots
```

### Plot Types

1. **Distribution Comparisons** (`00_*_comparison.png`)
   - Side-by-side histograms showing how each method categorizes the three disturbance metrics
   - Allows visual comparison of grouping strategies

2. **SHAP % Plots** (`01_SHAP_percent_mortality_disturbance.png`)
   - Disturbance SHAP contribution (%) stratified by each categorization
   - Shows how disturbance importance varies across categories
   - Format: 3 rows (one per mortality metric) × 5 columns (one per EFP)

3. **Mean |SHAP| Plots** (`02_SHAP_mean_mortality_disturbance.png`)
   - Absolute mean SHAP values for disturbance variables
   - Free y-axis scales per EFP for optimal visualization
   - Same 3×5 layout as SHAP % plots

4. **Delta RMSE Plots** (`03_DeltaRMSE_*.png`)
   - Model comparison showing RMSE difference (with disturbance - without disturbance)
   - Stratified by each categorization method
   - One plot per model pair × EFP × window combination

5. **Site SHAP Stacked Bars** (`site_shap/site_shap_*.png`)
   - Relative contribution of each driver group (Climate, Traits, Disturbance, Memory) per site
   - Sites ordered by disturbance contribution
   - Three panels showing stratification by each mortality metric

---

## How to Use This Folder

1. **Quick Comparison:** Look at `00_*_comparison.png` files in the root to visually compare how methods differ

2. **SHAP Interpretation:** 
   - Compare `01_SHAP_percent_*` across methods to see if patterns are stable
   - Use `02_SHAP_mean_*` for absolute effect sizes

3. **Model Performance:**
   - Review `03_DeltaRMSE_*.png` to see if delta RMSE patterns differ across categorization methods
   - Look for consistency in which sites benefit most from disturbance data

4. **Site-Level Detail:**
   - Browse `site_shap/` folder for individual site breakdowns
   - Useful for understanding outliers or specific site behaviors

---

## Key Findings & Recommendations

### Distribution Characteristics
- All three metrics show **right-skewed distributions** with most sites at low-to-moderate disturbance
- Natural breaks method yields thresholds nearly identical to tertiles (±0.1-0.2%)
- Equal-width method creates highly imbalanced groups due to skewness

### Statistical Trade-offs

| Method | Pros | Cons |
|--------|------|------|
| **Tertiles** | Balanced power, simple interpretation | Ignores natural clustering |
| **Equal-Width** | Reflects distribution shape | Highly unbalanced groups |
| **Natural Breaks** | Statistically grounded, balanced groups | Requires distributional assumptions |

### Recommendation
**Tertiles or Natural Breaks** are recommended:
- Tertiles: if you want equal sample sizes for comparing low/mid/high disturbance effects
- Natural Breaks: if you want statistically meaningful breaks reflecting natural variance structure

Equal-width is **not recommended** due to extreme group size imbalance (125 vs 20-25 sites).

---

## Data Files Used

- `derived_tables/disturbance_metric_test/tertiles_method.csv`
- `derived_tables/disturbance_metric_test/equal_width_method.csv`
- `derived_tables/disturbance_metric_test/natural_breaks_method.csv`

All categorizations applied to the **164 common sites** (M06 ∩ M08 sites) to ensure consistency with RF model analysis.

---

Generated: 2026-07-13

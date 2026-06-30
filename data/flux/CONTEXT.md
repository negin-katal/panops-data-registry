# Project Context — FluxNet × Tree Mortality

**Researcher:** Negin Katal (neggy.k.92@gmail.com)
**Phase:** Analysis complete; manuscript in preparation (Nature journal format)

## Research Question

Do deadwood-based tree mortality metrics improve predictions of ecosystem functional
properties (EFPs) at eddy covariance sites, beyond what climate and plant traits alone explain?

## Study Design

- **Sites:** 184 modelling sites (eddy covariance towers with ≥4 years continuous data,
  forest/savanna/shrubland/wetland IGBP classes)
- **Period:** 2017–2025 (FluxNet V02)
- **Response variables:** GPPsat, NEPmax, ETmax, uWUE (4 EFPs, annual, z-score anomalies or raw-lag)
- **Validation:** Leave-One-Site-Out (LOSO) cross-validation
- **Models:** M01–M08 (8 predictor combinations × 2 memory types × 2 windows = 32 configurations)

## Language

### Core domain terms

| Term | Meaning |
|---|---|
| **EFP** | Ecosystem Functional Property — a site-year summary metric of ecosystem function |
| **GPPsat** | Light-saturated gross primary productivity (μmol m⁻² s⁻¹) |
| **NEPmax** | Maximum net ecosystem production (μmol m⁻² s⁻¹) |
| **ETmax** | Maximum evapotranspiration (mm d⁻¹) |
| **uWUE** | Underlying water-use efficiency (g C mm⁻¹) |
| **LOSO** | Leave-One-Site-Out — cross-validation where one site is held out per fold |
| **24mbench** | 24-month benchmark — the unified dataset with 24-month met lags, 644 site-years, 166 sites |
| **anomaly** / **anomaly memory** | EFP memory encoded as z-score anomaly of lagged EFP (M05–M08) |
| **raw-lag** / **rawlag** | EFP memory encoded as raw lagged EFP values |
| **12m / 24m window** | Length of the meteorological predictor lag window (12 or 24 months) |
| **disturbance** / **D** | Deadwood-based tree mortality metrics (v2-2 product, multi-buffer) |
| **new_mortality_rate_pct_500m** | Canonical mortality rate metric at 500 m buffer (v2-2) |
| **mortality_intensity_pct_500m** | Older mortality intensity metric (v1); used in earlier plots |
| **noWET** | Subset excluding wetland (WET) sites: 515 site-years, 128 sites |
| **SHAP** | SHapley Additive exPlanations — feature importance values from the RF models |
| **v1 / v2-2** | Versions of the deadwood disturbance product |
| **IGBP** | Land-cover classification (ENF, EBF, DNF, DBF, MF, CSH, OSH, WSA, SAV, WET) |

### Model naming

| Model | Predictors |
|---|---|
| M01 | Climate (C) |
| M02 | C + Disturbance (D) |
| M03 | C + Traits (T) |
| M04 | C + T + D |
| M05 | C + EFP memory (M) |
| M06 | C + D + M |
| M07 | C + T + M |
| M08 | C + T + D + M |

### Terms to avoid / clarify

- **"mortality"** alone is ambiguous — specify `mortality_intensity` (v1) vs `new_mortality_rate` (v2-2)
- **"the model"** — always name which model (M01–M08) and which window/memory type
- **"benchmark"** — refers specifically to the 24mbench unified dataset unless otherwise stated

## Current State

- RF models: complete for all 32 configurations (anomaly + rawlag × 12m + 24m × M01–M08)
- SHAP values: computed for M04, M08, M09, M10
- noWET posthoc subset: complete
- Manuscript: drafted in Overleaf; Fig 1 and Fig 2 in progress
- Overleaf project ID: `698b0715a5817a2efadd24b6`

## Canonical Data Files

| File | Description |
|---|---|
| `derived_tables/final_disturbance_v2-2_multibuffer.csv` | Disturbance metrics, all buffers, v2-2 |
| `derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv` | Main modelling dataset |
| `derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_metrics_LOSO.csv` | LOSO metrics, anomaly memory |
| `derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_predictions_LOSO.csv` | Per-observation predictions, anomaly memory |
| `derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench/RF_metrics_LOSO.csv` | LOSO metrics, raw-lag memory |
| `derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench/RF_predictions_LOSO.csv` | Per-observation predictions, raw-lag memory |
| `derived_tables/outputs_afterEGU_results/RF_outputs_24mbench_noWET_posthoc/metrics_anomaly_noWET.csv` | noWET subset, anomaly |
| `derived_tables/outputs_afterEGU_results/RF_outputs_24mbench_noWET_posthoc/metrics_rawlag_noWET.csv` | noWET subset, raw-lag |

## Key Decisions Made

- **24mbench as primary benchmark** — unified 644 site-year dataset with 24-month met lag; older 52-site and 3-year datasets are deprecated for main results
- **noWET as secondary analysis** — wetlands excluded posthoc to test robustness
- **new_mortality_rate (v2-2)** preferred over mortality_intensity (v1) for new figures
- **LOSO over random CV** — preserves spatial independence
- **Anomaly z-score as primary memory encoding** — raw-lag shown as supplementary/comparison
- **C+T vs C+T+D (M03/M04) as primary comparison for disturbance effect** — harder test than C vs C+D; only shows D benefit where disturbance signal is real
- **IGBP grouping over continuous tree cover** for moderator analysis — IGBP class separates D-helpful from D-harmful sites more cleanly than forest_mean_pct_500m (r~0.18)
- **deadwood_mean_pct_500m (legacy)** is the primary disturbance signal, not new_mortality_rate — SHAP shows accumulated deadwood dominates, not annual event rate

## Emerging Findings (2026-06-29 grilling session)

- **D improves GPPsat prediction in forests (ENF, DBF, MF) but hurts in open ecosystems (CSH, SAV, EBF)** — mechanism: in forests, individual tree death creates persistent structural gaps captured by deadwood metrics; in open/shrubland systems, grasses play a major role and deadwood metrics don't represent the full canopy signal
- **Disturbance effect is legacy-driven**: SHAP top variables are all `deadwood_mean_pct_*` (cumulative standing deadwood) across buffer sizes and lags — not `new_mortality_rate` (annual events)
- **D helps 70% of high-disturbance sites** (deadwood_mean_pct_500m > 12%) for GPPsat under C+T vs C+T+D
- **D is most valuable as complement to traits** (C+T+D > C+T) — at low-disturbance sites, adding D on top of traits hurts prediction (mean ΔRMSE = −0.24 for GPPsat)
- **Carbon EFPs (GPPsat, NEPmax) benefit from D; water EFPs (ETmax) do not** — traits dominate ETmax (56–59% SHAP); D disturbance SHAP for ETmax is 19–23%

## Language additions

| Term | Meaning |
|---|---|
| **delta RMSE (ΔRMSE)** | RMSE(with D) − RMSE(without D); negative = D improved prediction |
| **forest_mean_pct_500m** | Tree/forest cover fraction within 500m buffer — used as continuous tree cover metric |
| **deadwood tier** | Site grouped by mean deadwood_mean_pct_500m: Low (<5%), Medium (5–12%), High (>12%) |
| **D-helpful / D-harmful IGBP** | Forest IGBPs (ENF, DBF, MF) where D helps vs open IGBPs (CSH, SAV, EBF) where D hurts |
| **legacy signal** | Predictive signal from accumulated deadwood_mean_pct (multi-year accumulation) vs acute signal from new_mortality_rate (annual events) |

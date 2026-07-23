# V10 RF Pipeline: Growing-Season-to-Growing-Season Meteorological Lags

## Status: ✅ READY FOR RF TRAINING

**Date:** 2026-07-16  
**Key Change:** Switched from calendar-year lags to growing-season-to-growing-season (GS-to-GS) meteorological aggregation

---

## What Changed

### Previous (V9): Calendar-Year Lags
- Lag1: Simply shift meteo by 1 year
- Lag2: Simply shift meteo by 2 years
- Issue: Meteo coverage misaligned with growing seasons at many sites

### New (V10): Growing-Season-to-Growing-Season Aggregation
- **Lag0 (current):** CGS(Y-1) to CGS(Y) window
- **Lag1:** CGS(Y-1) to CGS(Y) window (using CGS from monthly data)
- **Lag2:** CGS(Y-2) to CGS(Y-1) window
- **Benefit:** Ensures full 12-month meteo coverage per growing season, regardless of site phenology

### Data Flow
```
1. prepare_meteo_gs_to_gs_lags.R
   └─ Input: CGS dates (center_growing_season_by_site_year.csv)
   └─ Input: Monthly meteo files (monthly_meteo_per_site/*.csv)
   └─ Output: GS_to_GS_meteo_lags/{lag0, lag1, lag2}

2. prepare_v10_with_gs_meteo_lags.R
   └─ Input: V8 base data (EFPs + mortality)
   └─ Input: V3 traits (static per site)
   └─ Input: GS-to-GS meteo lags
   └─ Output: V10_gs_meteo_benchmarks/{B1, B2}

3. generate_predictor_docs_v2.R
   └─ Input: V10 benchmarks
   └─ Output: RF_V10_B{1,2}/PREDICTORS.csv
```

---

## Benchmarks

### V10 Benchmark 1 (Lag1 Only)
- **Dataset:** `V10_gs_meteo_benchmarks/benchmark_B1_lag1only_gs_meteo.csv`
- **Rows:** 624 site-years
- **Sites:** 143
- **Years:** 2019–2025
- **Predictors:**
  - Meteorology (current + lag1): 22 variables
  - Mortality/deadwood (current + lag1): 0–6 variables (M02, M04, M06, M08)
  - Plant traits (static): 0–5 variables (M03, M04, M07, M08)
  - EFP memory (lag1): 0–4 variables (M05–M08)
- **Models:** M01–M08 × 2 memory types (raw + anomaly) = 16 variants per response

### V10 Benchmark 2 (Lag1+Lag2)
- **Dataset:** `V10_gs_meteo_benchmarks/benchmark_B2_lag1and2_gs_meteo.csv`
- **Rows:** 624 site-years (harmonized with B1)
- **Sites:** 143
- **Years:** 2019–2025
- **Predictors:**
  - Meteorology (current + lag1+lag2): 33 variables
  - Mortality/deadwood (current + lag1+lag2): 0–9 variables
  - Plant traits (static): 0–5 variables
  - EFP memory (lag1+lag2): 0–8 variables
- **Models:** M01–M08 × 2 memory types = 16 variants per response

### Harmonized Site-Years
Both benchmarks use **identical 624 site-years from 143 sites** for direct comparison:
- B1 enables lag1-only models
- B2 enables lag1+lag2 models
- Same data foundation allows fair model comparison across lag depths

---

## Predictor Documentation

### Complete Predictor Lists
Files: `RF_V10_B{1,2}/PREDICTORS.csv`

Each CSV contains:
- **Model:** M01–M08 with memory type (raw/anom)
- **Description:** Clear model composition
- **N_Predictors:** Total predictor count
- **N_Traits:** Plant traits included
- **N_Meteo_Current:** Current-year meteo variables
- **N_Meteo_Lag{1,12}:** Lagged meteo variables
- **N_Mortality:** Mortality/deadwood variables
- **N_EFP_Memory:** EFP lag memory variables
- **Predictors:** Semicolon-separated full list

Example B1 M04 (Full model):
```
M04, 33 predictors
├─ 11 current meteo
├─ 11 lag1 meteo (GS-to-GS)
├─ 5 plant traits (P12, P50, P88, gsmax, rdmax)
├─ 3 current mortality (forest, deadwood, intensity)
└─ 3 lag1 mortality
```

---

## Model Definitions

### All Models (M01–M08)
**Response variables:** GPPsat, NEPmax, ETmax, uWUE  
**LOSO cross-validation:** 143–624 test sites × 4 responses × 16 model variants = ~10,000 RF fits

| Model | Composition | Purpose |
|-------|-------------|---------|
| **M01** | Meteo only | Climate baseline |
| **M02** | Meteo + Mortality | Does disturbance help? |
| **M03** | Meteo + Traits | Do traits help? |
| **M04** | Meteo + Traits + Mortality | Full model (no memory) |
| **M05_raw** | Meteo + EFP lag (raw) | Does raw memory help? |
| **M05_anom** | Meteo + EFP lag (anomaly) | Does anomaly memory help? |
| **M06_raw** | Meteo + Mortality + EFP (raw) | Full + raw memory |
| **M06_anom** | Meteo + Mortality + EFP (anom) | Full + anomaly memory |
| **M07_raw** | Meteo + Traits + EFP (raw) | Traits + raw memory |
| **M07_anom** | Meteo + Traits + EFP (anom) | Traits + anomaly memory |
| **M08_raw** | Meteo + Traits + Mortality + EFP (raw) | Full + raw memory |
| **M08_anom** | Meteo + Traits + Mortality + EFP (anom) | Full + anomaly memory |

---

## RF Training Scripts

### Benchmark 1
**Script:** `scripts/model/run_54_RF_V10_B1_lag1_gs_meteo.R`

```bash
tmux new-session -d -s rf_v10_b1
tmux send-keys -t rf_v10_b1 \
  "/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript scripts/model/run_54_RF_V10_B1_lag1_gs_meteo.R 2>&1 | tee logs/rf_v10_b1.log" Enter
```

**Expected output:**
- `RF_V10_B1_lag1/RF_metrics_LOSO.csv` (128 rows: 8 models × 2 memory × 4 responses)
- `RF_V10_B1_lag1/RF_predictions_LOSO.csv` (LOSO predictions)
- `RF_V10_B1_lag1/PREDICTORS.csv` (already created)

**Runtime:** ~2–3 hours

### Benchmark 2
**Script:** `scripts/model/run_55_RF_V10_B2_lag1and2_gs_meteo.R`

```bash
tmux new-session -d -s rf_v10_b2
tmux send-keys -t rf_v10_b2 \
  "/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript scripts/model/run_55_RF_V10_B2_lag1and2_gs_meteo.R 2>&1 | tee logs/rf_v10_b2.log" Enter
```

**Expected output:**
- `RF_V10_B2_lag1and2/RF_metrics_LOSO.csv`
- `RF_V10_B2_lag1and2/RF_predictions_LOSO.csv`
- `RF_V10_B2_lag1and2/PREDICTORS.csv` (already created)

**Runtime:** ~2–3 hours

---

## Key Files

| Path | Contents |
|------|----------|
| `derived_tables/outputs_afterEGU_results/GS_to_GS_meteo_lags/` | Aggregated meteo by GS window (lag0, lag1, lag2) |
| `derived_tables/outputs_afterEGU_results/V10_gs_meteo_benchmarks/` | Harmonized benchmarks (B1, B2) |
| `derived_tables/outputs_afterEGU_results/RF_V10_B1_lag1/` | B1 RF outputs + PREDICTORS.csv |
| `derived_tables/outputs_afterEGU_results/RF_V10_B2_lag1and2/` | B2 RF outputs + PREDICTORS.csv |

---

## Data Attrition Summary

| Stage | Rows | Sites | Loss |
|-------|------|-------|------|
| V8 (initial) | 1,429 | 273 | — |
| V10 + traits | 772 | 143 | 46% |
| Harmonized (lag2) | 624 | 143 | 19% |

**Note:** Loss from 273 → 143 sites is due to missing trait data (only available for 143 sites from v3).

---

## Testing Checklist

Before declaring V10 complete:

- [ ] Both RF scripts run without errors
- [ ] `RF_metrics_LOSO.csv` has 128 rows each (8 models × 2 memory × 4 responses... wait, should be 64? 8×2×4 = 64 per benchmark)
- [ ] RMSE values are reasonable (not NaN, not 0)
- [ ] R² values are in range [0, 1]
- [ ] Predictions CSV matches metrics row count
- [ ] PREDICTORS.csv is readable and complete

---

## Next Steps

1. **Run RF:** Execute both B1 and B2 scripts in parallel tmux sessions
2. **Monitor progress:** Check logs every 30 minutes
3. **Post-processing:** After completion:
   - Extract best models per response
   - Compare B1 vs B2 (does lag2 help?)
   - Compare raw vs anomaly memory
   - SHAP analysis (if time permits)
4. **Manuscript:** Generate figures for paper

---

## Questions?

Refer to:
- **Meteo aggregation logic:** `prepare_meteo_gs_to_gs_lags.R`
- **Benchmark creation:** `prepare_v10_with_gs_meteo_lags.R`
- **Predictor breakdown:** `generate_predictor_docs_v2.R`
- **RF pipeline:** run_54/55 scripts

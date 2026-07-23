# Daily Report — 2026-07-03 (RF v3 Harmonized Benchmark)

---

## Background

Previous RF versions had **unequal sample sizes across EFPs**:
- GPPsat, NEPmax, ETmax: 644 site-years × 166 sites
- WUE, uWUE: 635 site-years × 164 sites (missing CN-Sb1, CN-Sb2)

This was unfair for model comparison. Today we fixed this.

---

## Changes Made

### 1. Remove Flagged Sites (CN-Sb1, CN-Sb2)

**Reason**: Both sites have no usable WUE/uWUE data after quality control:
- CN-Sb1: 5 site-years removed
- CN-Sb2: 5 site-years removed
- **Total removed**: 10 rows

**Why now**: During v2 data quality checks, we found extreme uWUE/WUE values (>8) at CN-Sb1 and CN-Sb2 — likely rice paddy/agricultural contamination despite DNF labeling. We set those values to NA. Now to ensure identical samples across EFPs, we remove these sites entirely.

### 2. Add Relative Disturbance Metric

Added 15 new columns (5 buffers × 3 lags):
```
relative_disturbance_pct_{100,200,300,400,500}m{,_lag1,_lag2}
```

**Formula**: `(deadwood_mean_pct + loss_area_frac×100) / (forest_mean_pct + loss_area_frac×100) × 100`

**Interpretation**: Fraction of original forest extent showing disturbance signal (standing deadwood + forest loss). Bounded 0–100%.

**Values**:
- Current year (100m–500m): 1068–1081 non-NA site-years
- Lag1: 884–892 site-years
- Lag2: 712–717 site-years

**Note**: `forest_mean_pct` only exists at current year (no lags in source data), so relative disturbance at lags uses current-year forest as denominator.

### 3. Harmonized Benchmark

**Input**: `EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv` (1180 rows)  
**Output**: `EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv` (1170 rows)

**Final benchmark**:
- All EFPs: 1164 site-years (identical across 5 EFPs)
- Sites: 182 (after removing CN-Sb1, CN-Sb2)
- Years: 9 (2016–2024)
- Columns: 668 (added 15 relative_disturbance metrics)

---

## RF v3 Runs (In Progress)

**Scripts created**:
- `run_39_RF_LOSO_anomaly_24mbench_v3.R` — Anomaly memory, M01–M08, LOSO
- `run_40_RF_LOSO_rawmem_24mbench_v3.R` — Raw-lag memory, M01–M08, LOSO
- `run_41_RF_shap_anomaly_24mbench_v3.R` — Anomaly SHAP (M04/M08)
- `run_42_RF_shap_rawmem_24mbench_v3.R` — Rawmem SHAP (M04/M08)

**Launch status** (2026-07-03 10:34 UTC):
- `rf39_anomaly` tmux: **running** (LOSO training)
- `rf40_rawmem` tmux: **running** (LOSO training)

**Expected completion**: ~4–6 hours per LOSO run; SHAP runs will follow after.

**Monitor**:
```bash
tmux capture-pane -t rf39_anomaly -p | tail -20
tmux capture-pane -t rf40_rawmem -p | tail -20
```

**Output locations**:
- `derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/`
- `derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_v3/`

---

## Summary Table

| Item | v2 | v3 | Change |
|------|----|----|--------|
| Sites | 166/164 (unequal) | 182 (equal) | -2 (removed CN-Sb1/2) |
| Site-years | 644/635 (unequal) | 1164 (equal) | harmonized |
| EFPs | GPPsat, NEPmax, ETmax, uWUE, WUE | same | N/A |
| Disturbance vars | mortality_intensity_pct×5 buffers | + relative_disturbance_pct×5 buffers | 15 new columns |

---

## Next Steps

1. ✓ Data harmonization done
2. ✓ RF runs launched
3. ⏳ Wait for v3 LOSO completion (~4–6h)
4. ⏳ Launch v3 SHAP runs
5. ☐ Replot figures 15–20 with v3 outputs
6. ☐ Commit and push results
7. ☐ Update manuscript tables with v3 numbers

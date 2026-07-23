# RF Training Runs - Final Pipeline Summary

## Status: 🚀 RUNNING IN PARALLEL

**Started:** 2026-07-16 15:55 UTC

Two comprehensive RF LOSO cross-validation runs are executing in parallel:

### Benchmark 1: Lag1 Only
- **Script:** `scripts/model/run_52_RF_B1_lag1_final.R`
- **Session:** `tmux capture-pane -t rf_b1 -p`
- **Data:** 682 site-years, 169 sites
- **Log:** `logs/run_52_B1_lag1.log`

### Benchmark 2: Lag1+Lag2
- **Script:** `scripts/model/run_53_RF_B2_lag1and2_final.R`
- **Session:** `tmux capture-pane -t rf_b2 -p`
- **Data:** 682 site-years, 169 sites (identical to B1)
- **Log:** `logs/run_53_B2_lag1and2.log`

---

## Model Configuration

### Response Variables (4)
1. **GPPsat** - Gross Primary Production at saturation
2. **NEPmax** - Maximum Net Ecosystem Production
3. **ETmax** - Maximum Evapotranspiration
4. **uWUE** - Unit Water Use Efficiency

### Model Variants (M01-M08)
- **M01:** Climate (meteo current + lag1/lag2)
- **M02:** Climate + Disturbance
- **M03:** Climate + Traits
- **M04:** Climate + Traits + Disturbance (full)
- **M05:** Climate + Memory (raw lag)
- **M06:** Climate + Memory + Disturbance
- **M07:** Climate + Traits + Memory
- **M08:** Climate + Traits + Memory + Disturbance (full)

### Memory Encoding (2)
- **Raw:** Previous year EFP values (e.g., GPPsat_lag1)
- **Anomaly:** Z-score normalized EFP (e.g., GPPsat_anom_lag1)

### Total Model Runs Per Benchmark
- 8 models × 2 memory types × 4 responses = **64 LOSO trainings**
- ~169 sites × 64 = ~10,816 individual RF fits

---

## Expected Runtime

- **Per model:** ~5-10 minutes per response variable
- **Per memory type:** ~20-40 minutes (4 responses)
- **Per benchmark:** ~80-160 minutes (~2-3 hours)
- **Total with parallel runs:** ~2-3 hours (wall-clock time)

---

## Output Locations

**Base directory:**
```
/mnt/gsdata/projects/panops/panops-data-registry/data/flux/
derived_tables/outputs_afterEGU_results/
```

### Benchmark 1 Outputs
```
RF_B1_lag1_final/
├── RF_metrics_LOSO.csv          [128 rows: models × responses × memory types]
└── RF_predictions_LOSO.csv      [~50k predictions from LOSO]
```

### Benchmark 2 Outputs
```
RF_B2_lag1and2_final/
├── RF_metrics_LOSO.csv          [128 rows]
└── RF_predictions_LOSO.csv      [~50k predictions]
```

### Metrics CSV Structure
```
model    | response | memory_type | n_rows | n_sites | RMSE  | R2
---------|----------|-------------|--------|---------|-------|-------
M01      | GPPsat   | raw         | 682    | 169     | 6.71  | 0.535
M01      | GPPsat   | anom        | 682    | 169     | 6.71  | 0.535
...      | ...      | ...         | ...    | ...     | ...   | ...
```

---

## Monitoring Progress

### Quick Check
```bash
bash scripts/monitor_rf_progress.sh
```

### Real-Time Output
```bash
# B1 progress
tmux capture-pane -t rf_b1 -p | tail -20

# B2 progress
tmux capture-pane -t rf_b2 -p | tail -20
```

### Log Files
```bash
tail -f logs/run_52_B1_lag1.log
tail -f logs/run_53_B2_lag1and2.log
```

---

## Expected Results Preview

Based on v4 lag benchmarks:

| Lag | Meteo+Traits+Dist | GPPsat R² | ETmax R² | Notes |
|-----|-------------------|-----------|----------|-------|
| L1  | Yes               | ~0.535    | ~0.50    | Previous v4 result |
| L1+L2 | Yes             | ~0.581    | ~0.538   | Previous v4 result |

### Key Questions Answered
1. **Do traits improve models?** M03/M04 vs M01/M02
2. **Does disturbance help?** M02/M04 vs M01/M03
3. **Does EFP memory add value?** M05-M08 vs M01-M04
4. **Raw vs anomaly memory?** Compare raw/anom results in same model
5. **Lag depth effect?** B1 vs B2 performance difference

---

## Post-Processing Steps

After runs complete:

1. **Extract best models** per response variable
2. **Compare memory types** (raw vs anomaly)
3. **SHAP analysis** for feature importance
4. **Generate figures** for manuscript
5. **Create results table** (LaTeX format)

---

## Contact / Status Updates

- Check logs every 30 minutes during runs
- Monitor will be updated as progress continues
- Expected completion: 2026-07-16 18:00-19:00 UTC


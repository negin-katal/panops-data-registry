# exp02 — Force raw EFP-memory into every split (`always.split.variables`)

**Goal:** recover exp01's large raw-memory gain *without* exp01's small penalty on the
non-memory / anomaly models. Follows directly from [exp01](../exp01_hyperparams/README.md), which
showed the default `mtry ≈ p/3` under-uses the dominant raw-memory predictor.

## What changed vs baseline
**Only the split rule for raw-memory models.** Everything else identical; datasets fixed
(high-Tcover 93, all-sites 112, same site-years, read-only).
- **Raw-memory models (M5–M8 `*_raw`):** `always.split.variables = {resp}_lag1` ( + `{resp}_lag2`
  for 24m), with the **default `mtry`**. The strong memory column is offered at *every* split, while
  the remaining `mtry` picks keep the weak climate/disturbance predictors decorrelated.
- **All other models (M1–M4, anomaly):** unchanged = baseline (no forcing, default mtry).

Script `scripts/run_v10_RF_ranger_exp02.R` → `RF_v10{_all_sites}_exp02/`. Baseline and exp01 outputs
left intact. LOSO folds parallel `mclapply(60)`. Seed 42, num.trees 500.

## Result — exp02 wins (3-way: base vs exp01 high-mtry vs exp02 always-split)
Mean LOSO R² by memory group (`three_way_metrics.csv`, `three_way_raw_memory_R2.png`):

| dataset | group | base | exp01 high-mtry | **exp02 always-split** |
|---|---|---|---|---|
| all-sites | **raw** | 0.484 | 0.693 | **0.703** ✅ |
| all-sites | anom | 0.293 | 0.267 | **0.293** (=base) |
| all-sites | none | 0.293 | 0.267 | **0.293** (=base) |
| high-Tcover | **raw** | 0.431 | 0.677 | **0.684** ✅ |
| high-Tcover | anom | 0.273 | 0.250 | **0.273** (=base) |
| high-Tcover | none | 0.272 | 0.251 | **0.272** (=base) |

**exp02 is the best of both worlds:**
1. Recovers the raw-memory gain **slightly better** than exp01's high-mtry (0.703 vs 0.693 all-sites;
   0.684 vs 0.677 high-Tcover) — raw models gain **+0.22 / +0.25 R²** over baseline.
2. **Zero penalty** on the non-memory and anomaly models (identical to baseline) — because they keep
   default behaviour, unlike exp01 which lost ~0.02–0.04 there.
3. Cleaner mechanistically: guarantees the dominant memory signal is always available while keeping
   the forest decorrelated over the weak predictors.

## Recommended final RF structure (adopt exp02)
- M5–M8 **raw**: default `mtry` + `always.split.variables = {resp}_lag1[/lag2]`.
- M1–M4 and M5–M8 **anom**: unchanged (baseline).
- num.trees 500, seed 42 (unchanged). No dataset changes.

## Cascade if adopted
Re-extract SHAP (M4/M6/M8) from the exp02 models, regenerate all plots, RF-metrics table, and fold a
"baseline vs adopted" note into the HTML report. (Baseline kept for the comparison the report will show.)

# exp01 — RF Hyperparameter Tuning

**Goal:** find better `ranger` hyperparameters than the defaults, *without* changing the datasets or
leaking into the reported LOSO metrics. See [`../RF_baseline_structure.md`](../RF_baseline_structure.md)
for the baseline.

## What changed vs baseline
**Only the RF hyperparameters.** Everything else is identical to the baseline:
- Datasets **unchanged & fixed** — high tree cover = **93 sites**, all sites = **112 sites**, same
  harmonized site-years (read-only). This preserves comparability across all experiments.
- Same predictor blocks, same 24-model set, same responses, same LOSO evaluation.

Tuned hyperparameters (baseline default in brackets):
- `mtry` — number of predictors tried per split, expressed as a **fraction of predictors** so it
  transfers across the 24 models of differing size *(default ⌊p/3⌋ ≈ 0.33)*
- `min.node.size` *(default 5)*
- `num.trees` *(default 500)*

## Method (leakage-free)
1. **Tuning CV ≠ reporting CV.** Hyperparameters are selected with **grouped 5-fold CV** (folds =
   disjoint groups of *sites*), so no site appears in both train and validation of a tuning fold.
2. Tuned on the **full model M8_raw_24m** (C+T+D+M, 24m) per response — the richest predictor set;
   `mtry` as a fraction generalises the winner to the smaller models.
3. The winning config is then applied to a **full LOSO re-run** (all 24 models) and compared to the
   baseline LOSO — the reported comparison is on LOSO, tuned on separate grouped folds.

**Grid:** `mtry_frac ∈ {0.20, 0.33, 0.50, 0.70, 1.00}` × `min.node.size ∈ {3, 5, 10}` ×
`num.trees ∈ {500, 1000}` = 30 combos. Selection metric = pooled grouped-CV RMSE.

**Compute:** parallelised with `mclapply(mc.cores = 60)` over grid×fold; `num.threads = 1` per fit.
Script: [`scripts/rf_tune_01_hyperparams.R`](../../../scripts/rf_tune_01_hyperparams.R). Seed 42.

## Outputs
- `tuning_grid_<dataset>.csv` — CV-RMSE for every combo × response
- `tuning_best_<dataset>.csv` — best config per response
- **`tuning_curves_mtry.png`** — grouped-CV RMSE vs `mtry` (relative to default), all 5 EFPs × both
  datasets — shows CV RMSE falling as `mtry` rises, `min.node`/`num.trees` nearly flat
- **`baseline_vs_tuned_dRMSE.png`** — LOSO ΔRMSE % per model (tuned vs baseline)

## Results

### Preliminary (first pass, mtry grid capped at 0.50)
Every response chose `mtry_frac = 0.50` (grid boundary) and mostly `num.trees = 1000`, with
**~4–6 % grouped-CV-RMSE reduction** vs the ranger defaults:

| Response | best mtry_frac | min.node | ntrees | CV-RMSE | vs default |
|---|---|---|---|---|---|
| GPPsat | 0.50 | 5 | 1000 | 5.183 | −6.1 % |
| NEPmax | 0.50 | 5 | 1000 | 4.591 | −6.0 % |
| ETmax | 0.50 | 10 | 1000 | 0.0418 | −4.2 % |
| uWUE | 0.50 | 10 | 1000 | 0.623 | −5.2 % |
| WUE | 0.50 | 3 | 500 | 0.633 | −4.5 % |

Because the optimum hit the grid edge, the grid was **extended to `mtry_frac` up to 1.00** and re-run
for both datasets. *(Final numbers filled in below once the extended run completes.)*

### Final (extended grid, both datasets)
Best config per response (grouped-5-fold CV RMSE vs ranger defaults). Higher `mtry` consistently
wins — often `mtry_frac = 1.0` (i.e. bagging) — with gains **larger** than the capped-grid pass:

**High tree cover (93 sites, p=408):**
| Response | mtry_frac | min.node | ntrees | vs default |
|---|---|---|---|---|
| GPPsat | 1.00 | 3 | 500 | **−10.6 %** |
| NEPmax | 0.70 | 10 | 500 | −8.5 % |
| ETmax | 1.00 | 10 | 500 | −7.5 % |
| uWUE | 1.00 | 10 | 1000 | −8.4 % |
| WUE | 1.00 | 10 | 500 | −6.1 % |

**All sites (112 sites, p=444):**
| Response | mtry_frac | min.node | ntrees | vs default |
|---|---|---|---|---|
| GPPsat | 0.70 | 10 | 1000 | −4.9 % |
| NEPmax | 0.70 | 3 | 1000 | −6.5 % |
| ETmax | 1.00 | 10 | 1000 | −5.2 % |
| uWUE | 0.70 | 10 | 500 | −5.3 % |
| WUE | 1.00 | 5 | 500 | −6.0 % |

**Takeaways:** (1) the ranger default `mtry ≈ p/3` is clearly too low here — the strong signal is
concentrated in a few predictors among many weak ones, so considering more per split helps;
(2) `num.trees` and `min.node.size` matter far less than `mtry`; (3) gains (~5–11 % grouped-CV RMSE)
are worth carrying into the reported LOSO.

### Tuned LOSO vs baseline LOSO — **KEY FINDING**
Applied the per-response tuned config to the full 24-model LOSO (`scripts/run_v10_RF_ranger_tuned.R`,
outputs `RF_v10{_all_sites}_tuned/`, baseline untouched; identical 414/395 site-years).
Compared with `scripts/rf_tune_01_compare.R` (→ `baseline_vs_tuned_metrics.csv`,
`baseline_vs_tuned_dRMSE.png`).

**The gain is NOT uniform — it is concentrated entirely in the raw-memory models:**

| Model group | mean ΔR² (all-sites) | mean ΔR² (high-Tcover) |
|---|---|---|
| **M5–M8 raw memory** | **+0.21** | **+0.25** |
| M5–M8 anomaly memory | −0.02 | −0.02 |
| M1–M4 (no memory) | −0.02 to −0.04 | −0.02 |

Examples (LOSO R², baseline → tuned): GPPsat M5_raw 0.51→**0.71**; NEPmax M6_raw 0.60→**0.77**;
uWUE M7_raw 0.28→**0.63**. Non-memory and anomaly models are flat or slightly worse.

**Why:** the raw prior-year EFP (`{resp}_lag1`) is a *dominant* single predictor sitting among
~240–440 mostly-weak climate/disturbance columns. At the ranger default `mtry ≈ p/3` it is only
offered at ~⅓ of splits, so the RF systematically **under-uses** the strongest signal. Raising
`mtry` (to 0.7·p or full bagging) lets that signal be chosen → large gains. Anomaly memory is a
weaker predictor, so it doesn't benefit; for the weak-diffuse non-memory models, higher `mtry`
just reduces tree decorrelation slightly → marginally worse.

**Implications**
- The baseline **understated raw-memory performance** — with correct `mtry`, temporal memory is a
  far stronger predictor than the baseline suggested (strengthens the "EFP memory matters" result).
- A single global `mtry` is **not** optimal: raw-memory models want high `mtry`; others want the
  default. → **exp02 candidate:** per-model `mtry` (high only when raw memory is present), or force
  the memory column into every split via ranger `always.split.variables`.

**Verdict:** adopt higher `mtry` for the raw-memory models (M5–M8 raw); keep defaults elsewhere.
The disturbance-with-memory models (M6/M8 raw) — the flagships — improve most.

## Interpretation & next step
- A consistent ~5 % RMSE gain from `mtry`↑ and `trees`↑ is worth applying (larger than typical RF
  tuning gains). `min.node.size` matters less.
- **Next:** apply the per-response tuned config to the full LOSO re-run (both datasets), regenerate
  metrics/plots into `exp01_hyperparams/`, and fold a baseline-vs-tuned comparison into the HTML report.

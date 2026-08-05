# Model structures — RF, RF exp01/exp02, XGBoost, LightGBM (V10)

**Date:** 2026-08-05
**Scope:** exact configuration of every learner and every model family used in the V10
disturbance-vs-EFP analysis. All learners share the same datasets, predictor blocks, 24 model
configs, LOSO folds and seed — only the learner and its hyperparameters differ.

---

## 0. Correction: ranger's default `mtry` is √p, **not** p/3

Several project documents (`plots/V10/RF_tuning/exp01_hyperparams/README.md`, Section 10 of the
HTML report, `plots/V10/{XGBoost,LightGBM}/metrics_comparison.md`) state that the RF default is
`mtry ≈ p/3`. **That is the `randomForest` package's default for regression. `ranger` uses
`floor(sqrt(p))`.** Verified empirically:

| p | ranger default `mtry` | √p | p/3 |
|---|---|---|---|
| 143 | **11** | 12 | 48 |
| 279 | **16** | 17 | 93 |
| 444 | **21** | 21 | 148 |

**Why it matters.** For `M6_raw_12m` (p = 279, mtry = 16), the single raw-memory predictor
`{resp}_lag1` is offered at only **16/279 ≈ 5.7 %** of splits — not ~33 % as documented. This does
not overturn the exp01/exp02 conclusions; it *strengthens* the mechanism and explains why forcing
that column into every split (exp02) bought so much. It also explains why exp01 improved at every
grid point: the grid started at `mtry_frac = 0.20`, already ~4× above the true default of ≈0.05.

Results are unaffected — only the explanatory text is wrong and should be corrected.

---

## 1. Learner configurations

| | RF baseline | RF exp01-tuned | RF exp02 (adopted-then-reverted) | XGBoost | LightGBM |
|---|---|---|---|---|---|
| Library | `ranger` | `ranger` | `ranger` | `xgboost` 3.2.1.1 | `lightgbm` 4.7.0 |
| Algorithm | bagging | bagging | bagging | boosting, depth-wise | boosting, leaf-wise |
| Ensemble size | `num.trees = 500` | 500 or 1000 (per response) | `num.trees = 500` | `nrounds = 500` | `nrounds = 500` |
| Complexity cap | grown to purity | grown to purity | grown to purity | `max_depth = 6` | `num_leaves = 31` |
| Min node / leaf | `min.node.size = 5` | 3 / 5 / 10 (per response) | `min.node.size = 5` | `min_child_weight = 1` | `min_data_in_leaf = 5` |
| Feature sampling | `mtry = floor(√p)` → 11–21 | `mtry` = 310–444 | `mtry = floor(√p)` | `colsample_bytree = 0.8` | `feature_fraction = 0.8` |
| Row sampling | bootstrap | bootstrap | bootstrap | `subsample = 0.8` | `bagging_fraction = 0.8`, `bagging_freq = 1` |
| Shrinkage | none | none | none | `learning_rate = 0.05` | `learning_rate = 0.05` |
| Split finding | exact | exact | exact | exact | histogram |
| Special | — | per-response hyperparameters | `always.split.variables = {resp}_lag1[/lag2]`, **raw-memory models only** | — | — |
| Categoricals | `respect.unordered.factors = "order"` | same | same | numeric matrix | numeric matrix |
| Seed | 42 | 42 | 42 | 42 | 42 |
| Script | `run_v10_RF_ranger.R` | `run_v10_RF_ranger_tuned.R` | `run_v10_RF_ranger_exp02.R` | `run_v10_XGB.R` | `run_v10_LGB.R` |

Notes:
- **XGBoost and LightGBM are untuned** — sensible defaults, matched to each other wherever a direct
  analogue exists, so the comparison isolates the algorithm rather than differing library defaults.
- The one deliberate LightGBM deviation was `min_data_in_leaf = 5` (library default is 20), chosen to
  match ranger's `min.node.size`. A later grouped-CV sweep showed this was **under-regularised** —
  see §4.
- `exp02` differs from baseline in *exactly one* way: the forced split variable on raw-memory models.
  Everything else is identical, which is why RF and RF exp02 give identical numbers on every
  non-raw-memory model.

### exp01 per-response tuned configurations (all-sites, p = 444)

| Response | `mtry_frac` | `mtry` | `min.node.size` | `num.trees` |
|---|---|---|---|---|
| GPPsat | 0.70 | 310 | 10 | 1000 |
| NEPmax | 0.70 | 310 | 3 | 1000 |
| ETmax | 1.00 | 444 | 10 | 1000 |
| uWUE | 0.70 | 310 | 10 | 500 |
| WUE | 1.00 | 444 | 5 | 500 |

Selected by **grouped 5-fold CV** (folds = disjoint groups of sites) on `M8_raw_24m`, so selection
never touches the reported LOSO metric.

---

## 2. Model families (M1–M8) and predictor counts

Predictor blocks: **C** climate/meteorology · **T** plant traits · **D** disturbance ·
**M** memory (the response's own previous-year value, raw or anomaly).

| Model | Blocks | p (12m) | p (24m) | default `mtry` 12m / 24m | Adds D vs |
|---|---|---|---|---|---|
| M1 | C | 143 | 286 | 11 / 16 | — |
| M2 | C + D | 278 | 421 | 16 / 20 | M1 |
| M3 | C + T | 164 | 307 | 12 / 17 | — |
| M4 | C + T + D | 299 | 442 | 17 / 21 | M3 |
| M5 raw / anom | C + M | 144 | 288 | 12 / 16 | — |
| M6 raw / anom | C + D + M | 279 | 423 | 16 / 20 | M5 |
| M7 raw / anom | C + T + M | 165 | 309 | 12 / 17 | — |
| M8 raw / anom | C + T + D + M | 300 | 444 | 17 / 21 | M7 |

### Block sizes

| Block | Size | Composition |
|---|---|---|
| **C** | 143 (12m) / 286 (24m) | monthly climate/meteo aggregates, `lag1_*` (+ `lag2_*` for 24m) |
| **T** | 21 | `P12_`, `P50_`, `P88_`, `gsmax_`, `rdmax_`, `SSD`, `SLA`, `Leaf*`, `Stem*` |
| **D** | **135** | **9 metrics × 5 buffers × 3 time points** |
| **M** | 1 (12m) / 2 (24m) | `{resp}_lag1` [+ `{resp}_lag2`], or the `_anom_` variant |

**D block detail** — 9 metrics: `absolute_mortality`, `relative_mortality`, `relative_disturbance`,
`new_deadwood_gain_pp`, `new_mortality_rate_pct`, `mortality_loss_severity_pct`, plus `_thresh`
variants of the last three. × 5 buffers: **100, 200, 300, 400, 500 m**. × 3 time points:
current, `_lag1`, `_lag2`.

> **Dilution implication.** Adding D to M1 takes p from 143 → 278 (nearly doubling the model) while
> the default `mtry` rises only 11 → 16. With 135 largely-redundant columns (5 nested buffers;
> `_thresh` near-duplicates), the probability that any given split is offered a *useful* predictor
> falls sharply. This is the most likely reason **RF — and only RF — shows negative ΔR² on the
> weak-signal EFPs (uWUE, WUE)**: greedy learners simply ignore useless columns, whereas RF's random
> subsetting cannot. The lag dimension is genuine information and should be kept; the buffer and
> `_thresh` dimensions are the compressible ones.

---

## 3. Shared / held-fixed across every learner

| Item | Value |
|---|---|
| Datasets | all sites **112 sites / 414 site-years**; high tree cover **93 / 395** |
| Responses | GPPsat, NEPmax, ETmax, uWUE, WUE |
| Model set | 24 configs (M1–M8 × raw/anom × 12m/24m) |
| Predictor selection | `get_predictor_cols()`, copied verbatim across all learner scripts |
| Evaluation | leave-one-site-out (LOSO), identical folds, same RMSE / MAE / R² definitions |
| SHAP | TreeSHAP on M4 / M6 / M8 (raw + anom), same per-site scheme and driver groups |
| Seed | 42 |
| Parallelism | `mclapply` over LOSO folds; `OMP_NUM_THREADS=1` per worker |

---

## 4. LightGBM regularisation sweep (2026-08-05)

Grouped 5-fold CV over `min_data_in_leaf` × `num_leaves`, on `M2_12m` (no memory, weak diffuse
signal) and `M6_raw_12m` (one dominant predictor), all 5 responses.
Script: `scripts/lgb_tune_regularisation.R`.

**The shipped setting (`min_data_in_leaf = 5`, `num_leaves = 31`) is under-regularised.**
Mean CV-R² gain from the CV-selected config:

| Model | mean gain |
|---|---|
| `M2_12m` (weak signal) | **+0.042** |
| `M6_raw_12m` (strong signal) | +0.025 |

Largest single gain: **WUE / M2_12m 0.028 → 0.118**. Every combination improved; none got worse.
The dominant knob is **`num_leaves`** (7 or 15 beats 31 nearly everywhere), not `min_data_in_leaf`.
`min_data_in_leaf = 40` is uniformly bad and makes `num_leaves` irrelevant — the constraint binds.

**Caveat:** `num_leaves = 7` won 8 of 10 combinations and 7 was the smallest value tested — the
optimum sits on the grid edge (the same mistake exp01 made with `mtry`). The grid was extended
downward to `num_leaves ∈ {3, 5, 7, 15}` before adopting anything.

**Fairness note.** XGBoost and RF are at library defaults. A CV-tuned LightGBM compared against
untuned RF/XGBoost is **not** a fair learner ranking — it is a *sensitivity check on LightGBM's
configuration*. A fair head-to-head would require the same grouped-CV treatment for all three.

**Planned (does not overwrite anything):** tuned LightGBM will be written to
`LGB_v10_tuned{,_all_sites}/`, `plots/V10/LightGBM_tuned/`, `table_LGB_tuned_LOSO_v10.tex`, and a
fifth report-toggle option. The existing LightGBM results stay exactly as they are.

---

## 5. Open items

- [x] **DONE 2026-08-05** — corrected `mtry ≈ p/3` → `⌊√p⌋` across: `RF_baseline_structure.md`,
      `exp01_hyperparams/README.md`, `exp02_always_split/README.md`, `XGBoost/README.md`,
      `XGBoost/metrics_comparison.md`, `LightGBM/README.md`, `LightGBM/metrics_comparison.md`,
      `V10_report.html` (Sections 10/11/12 + figure caption), `tuned_exp02/V10_report_tuned.html`,
      `rf_tune_01_hyperparams.R`, `rf_tune_01_plot_grid.R`, and regenerated `tuning_curves_mtry.png`
      (its subtitle had the wrong text baked in). Results unchanged throughout.
- [ ] Consider trimming the D block (135 → ~12 columns: keep 3–4 metrics × 1 buffer × 3 lags) and
      re-testing. Prediction: the disturbance effect gets **larger and cleaner**, and the negative
      ΔR² values largely disappear — especially for RF.
- [ ] `nrounds = 500` is held fixed for both boosters. With stronger regularisation this may
      slightly underfit; proper early stopping needs a validation split inside the LOSO protocol.

# V10 Random-Forest — Baseline Structure (pre-tuning)

Documents the **current / baseline** RF setup so tuning experiments have a fixed reference to
compare against. Baseline = the pipeline as of 2026-07-23 (after the all-sites memory fix).

---

## 1. Datasets
| Dataset | Sites | Site-years | Definition |
|---|---|---|---|
| **all sites** | 112 | 414 | every site with complete predictor data and ≥4 years of continuous observations |
| **high tree cover** | 93 | 395 | all-sites set after removing sites with <30 % mean tree cover |

Within each dataset, **all models are trained on identical site-years** (harmonized), so metric
differences reflect model structure only. Harmonizers: `step_20` (filtered), `step_21` (all-sites).

## 2. Responses (5 EFPs)
GPP$_{sat}$, NEP$_{max}$, ET$_{max}$, uWUE, WUE. Each response modelled independently.

## 3. Cross-validation
**Leave-One-Site-Out (LOSO):** for each site, train on all other sites, predict the held-out
site's site-years. Metrics (RMSE, MAE, R²) pooled over all held-out predictions. This tests
**transfer to unseen sites** — the paper's core claim.

## 4. Predictor blocks
| Block | Symbol | Columns (regex) | Notes |
|---|---|---|---|
| Climate | **C** | `^lag1_` (12m); `^lag1_` + `^lag2_` (24m) | meteo (TA, VPD, SW_IN, P; mean/p05/p95), CGS-centered |
| Traits | **T** | `^(P12_|P50_|P88_|gsmax_|rdmax_|SSD|SLA|Leaf|Stem)` | 21 static traits/site |
| Disturbance | **D** | `^(absolute_|relative_|new_|mortality_|disturbance_)` | mortality/deadwood/loss at 100–500 m + lag1/lag2 |
| Memory | **M** | response-specific: `^{resp}_lag1$` (raw) or `^{resp}_anom_lag1$` (anom); +`_lag2` for 24m | prior-year EFP value |

## 5. Model set (24 configs per response = 8 models × window × memory type)
| Model | Predictors | Memory |
|---|---|---|
| M1 | C | — |
| M2 | C + D | — |
| M3 | C + T | — |
| M4 | C + T + D | — |
| M5 | C + M | raw / anom |
| M6 | C + D + M | raw / anom |
| M7 | C + T + M | raw / anom |
| M8 | C + T + D + M | raw / anom |

**Windows / benchmarks:** `12m` = B1 (lag1 only); `24m` = B2 (lag1 + lag2). M1–M4 have no memory
(identical across raw/anom); M5–M8 come in `raw` and `anom` memory variants.

## 6. RF hyperparameters (`ranger`) — the tuning surface
Set explicitly in `scripts/run_v10_RF_ranger.R`:
- `num.trees = 500`
- `seed = 42`
- `num.threads = 24`
- `respect.unordered.factors = "order"`

Left at **ranger defaults** (candidates for tuning):
- `mtry` = ⌊p/3⌋ (regression default) — **untuned**
- `min.node.size` = 5 (regression default) — **untuned**
- `max.depth` = unlimited — **untuned**
- `sample.fraction` = 1, `replace = TRUE` (bootstrap) — **untuned**
- `splitrule = "variance"` (regression default)

Prediction filtering: per fold, `complete.cases` on response + predictors; folds with <10 train rows skipped.

## 7. Pipeline
1. `step_17…step_19` — build B1/B2 benchmark datasets (+ per-response memory).
2. `step_20` / `step_21` — harmonize to identical site-years per dataset.
3. `scripts/run_v10_RF_ranger.R <filtered|all_sites>` — LOSO training → models, predictions, metrics.
4. `scripts/run_v10_extract_SHAP_from_ranger.R <dataset>` — TreeSHAP (M4, M6, M8), 60-core `mclapply`.

## 8. Outputs (per dataset)
`derived_tables/outputs_afterEGU_results/RF_v10{,_all_sites}/`:
- `RF_model_<model>_<resp>.rds` (120 models)
- `RF_predictions_LOSO.csv`, `RF_metrics_LOSO.csv`
- `RF_site_shap_M04_M08.csv`

## 9. Baseline results snapshot (all-sites, GPPsat, R²)
M1 (C) 0.26 · M2 (C+D) 0.45 · M4 (C+T+D) 0.46 · M5_raw (C+M) 0.51 · **M6_raw (C+D+M) 0.55** · M8_raw 0.54.
Carbon fluxes (GPPsat, NEPmax) benefit most from D; ETmax least. Raw memory >> anomaly memory.

---

## Tuning experiments — folder convention
```
plots/V10/RF_tuning/
├── RF_baseline_structure.md          ← this file
├── exp01_<short-name>/               ← one folder per experiment (plots + notes.md)
├── exp02_<short-name>/
└── ...
```
RF outputs for each experiment → `derived_tables/outputs_afterEGU_results/RF_v10_tuning/exp01_.../`.
Each `expNN/notes.md`: what changed vs baseline, why, and the headline metric deltas.

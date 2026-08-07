# XGBoost (CV-tuned complexity) — a negative result

A re-run of the [XGBoost analysis](../XGBoost/README.md) with tree complexity chosen by
**exhaustive grid search over grouped 5-fold cross-validation**, the same protocol used for
[exp01](../RF_tuning/exp01_hyperparams/README.md) and
[LightGBM tuned](../LightGBM_tuned/README.md). Everything else — datasets, variables, 24 model
configs, LOSO folds, SHAP scheme, seed — is unchanged.

**Nothing here overwrites anything.** The shipped XGBoost results stay in `XGB_v10{,_all_sites}/`
and `plots/V10/XGBoost/`; this run lives in `XGB_v10_tuned{,_all_sites}/` and this folder.

## Headline: tuning did *not* reliably improve LOSO performance

| Dataset | Model group | shipped | tuned | change |
|---|---|---|---|---|
| **all sites (112)** | no memory | 0.248 | 0.238 | **−0.011** |
| | anomaly memory | 0.249 | 0.239 | **−0.010** |
| | raw memory | 0.664 | 0.667 | +0.003 |
| **high tree cover (93)** | no memory | 0.250 | 0.250 | 0.000 |
| | anomaly memory | 0.249 | 0.251 | +0.001 |
| | raw memory | 0.632 | **0.665** | **+0.033** |

On all-sites, **more models got worse than better (66 of 120 vs 54)**. On high-tree-cover it helped,
almost entirely through the raw-memory models (88 helped / 32 hurt).

This is reported as it came out. The run was done to remove a fairness caveat — RF and LightGBM had
CV-tuned variants and XGBoost did not — and the answer is that XGBoost had no meaningful headroom to
recover.

## Why the CV gains did not transfer

Grouped 5-fold CV predicted **+0.036 R²** on the weak-signal models. LOSO delivered **−0.011**.

The cause is the **training-size gap between selection and evaluation**:

| | trains on | favours |
|---|---|---|
| grouped 5-fold CV | ~90 of 112 sites | shallower trees |
| LOSO | 111 of 112 sites | more capacity |

CV selects the complexity that is right for ~80 % of the data. LOSO then hands the model ~99 % of
it, and the shallow trees CV preferred (`max_depth` 2–4 vs the shipped 6) **underfit**. The effect is
milder on the smaller 93-site dataset, where the absolute gap is smaller — which is exactly why
tuning helps there and hurts on all-sites.

The same mechanism, less severely, shrank LightGBM's CV gain from +0.042 to +0.021 in LOSO. Here it
flips the sign. **Anyone tuning on grouped CV and reporting on LOSO should expect this attenuation**,
and should not assume a CV improvement survives.

## Selected configuration

Grid: `max_depth` × `min_child_weight`, exhaustive, grouped 5-fold CV, evaluated on `M2_12m`
(no memory, weak diffuse signal) and `M6_raw_12m` (one dominant predictor), all five responses.
Script: `scripts/xgb_tune_hyperparams.R` → `../XGBoost/regularisation_sweep_xgb_combined.csv`.

| Response | `max_depth` | `min_child_weight` |
|---|---|---|
| GPPsat | 4 | 3 |
| NEPmax | 2 | 3 |
| ETmax | 2 | 1 |
| uWUE | 3 | 10 |
| WUE | 2 | 10 |

Everything else matches the shipped run: `nrounds = 500`, `learning_rate = 0.05`,
`subsample = 0.8`, `colsample_bytree = 0.8`, `seed = 42`.

**Boundary check.** The first grid (`max_depth` 2–8) put the optimum on its lower edge — depth 2 won
5 of 10 combinations, and depths 6 and 8 never won. The grid was extended down to `max_depth = 1`
and the optimum then sat **interior** (wins: depth 1 ×1, depth 2 ×4, depth 3 ×4, depth 4 ×1), so the
search space is adequate. Both earlier sweeps hit the same boundary problem; it is worth checking for
routinely.

## What this settles

1. **The untuned XGBoost in the learner comparison was not disadvantaged.** A proper tuning attempt
   produced no reliable gain, so *"RF beats boosting on weak diffuse signals"* is not an artefact of
   comparing a tuned learner against an untuned one — it is now demonstrated rather than assumed.
2. **All three learners agree that less tree capacity suits n ≈ 414 site-years** — LightGBM wanted
   `num_leaves` 3–15 instead of 31, XGBoost `max_depth` 2–4 instead of 6. RF went the other way on
   `mtry` for a different reason (it needs to *see* the dominant predictor more often).
3. **The disturbance effect is unchanged**, as it has been across every variant.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/xgb_tune_hyperparams.R` | grouped-CV grid sweep |
| `scripts/run_v10_XGB_tuned.R <dataset>` | LOSO training → `XGB_v10_tuned{,_all_sites}/` |
| `scripts/run_v10_XGB_tuned_SHAP.R <dataset>` | TreeSHAP → `XGB_site_shap_M04_M08.csv` |
| `scripts/run_v10_XGB_tuned_plots.sh [dataset]` | all model-dependent figures into this folder |
| `scripts/plot_v10_deltaRMSE_7way.R` | seven-variant comparison figures (in `../LightGBM/`) |

The per-response configuration is read from the sweep CSV at runtime rather than hard-coded, so
training and SHAP stay in sync automatically.

Table: `manuscript/tables/table_XGBtuned_LOSO_v10.tex`.
Report: the **XGBoost tuned** option in the learner toggle, and Section 12.

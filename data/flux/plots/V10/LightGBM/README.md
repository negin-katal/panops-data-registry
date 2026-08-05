# LightGBM — a second, independent booster

A third full run of the V10 analysis in which **only the learner changed**: LightGBM
(leaf-wise, histogram-binned gradient boosting). Same datasets, same variables, same 24 model
configs, same LOSO folds, same SHAP scheme as the RF baseline and the
[XGBoost run](../XGBoost/README.md).

Nothing here overwrites anything. RF stays in `RF_v10{,_all_sites}/` +
`plots/V10/{all_sites,sites_with_high_Tcover}/`; XGBoost stays in `XGB_v10*` + `plots/V10/XGBoost/`.

## Why a third learner

The XGBoost run showed a large gain on the raw-memory models together with a big drop in the SHAP
share attributed to disturbance. That raised the obvious question: **is that a property of boosting,
or a quirk of one library?** LightGBM is an independent implementation with a *different tree-growth
strategy*, so anything both boosters do together is attributable to boosting itself.

## What is held fixed (identical to RF and XGBoost)

| Held fixed | Value |
|---|---|
| Datasets | all sites **112 / 414 site-years**, high tree cover **93 / 395 site-years** — read-only |
| Responses | GPP<sub>sat</sub>, NEP<sub>max</sub>, ET<sub>max</sub>, uWUE, WUE |
| Predictor blocks | **C** climate, **T** traits, **D** disturbance, **M** memory (raw or anomaly) |
| Model set | the same 24 configs (M1–M8 × raw/anom × 12m/24m) |
| Predictor selection | `get_predictor_cols()` copied verbatim from `run_v10_RF_ranger.R` |
| Evaluation | LOSO, same folds, same RMSE / MAE / R² definitions |
| SHAP | TreeSHAP on M4 / M6 / M8 (raw + anom), same per-site scheme, same driver groups |
| Seed | 42 |

## What changed — the learner

| | RF (`ranger`) | XGBoost | LightGBM |
|---|---|---|---|
| Growth | independent deep trees (bagging) | boosting, **depth-wise** | boosting, **leaf-wise** (best-first) |
| Complexity cap | `min.node.size = 5` | `max_depth = 6` | `num_leaves = 31`, `min_data_in_leaf = 5` |
| Ensemble size | `num.trees = 500` | `nrounds = 500` | `nrounds = 500` |
| Shrinkage | none | `learning_rate = 0.05` | `learning_rate = 0.05` |
| Row / column sampling | `mtry = ⌊√p⌋` per split (11–21, ~5 % of p) | `subsample`/`colsample_bytree` = 0.8 | `bagging_fraction`/`feature_fraction` = 0.8 |
| Binning | exact splits | exact (default) | **histogram** (fast) |

**LightGBM hyperparameters (untuned).** Matched to the XGBoost run wherever a direct analogue
exists, so the comparison isolates the *algorithm* rather than differing library defaults:

```r
NROUNDS <- 500
LGB_PARAMS <- list(
  objective        = "regression",
  metric           = "rmse",
  learning_rate    = 0.05,   # = XGB learning_rate
  num_leaves       = 31,     # LightGBM default (leaf-wise); XGB grows depth-wise to max_depth 6
  min_data_in_leaf = 5,      # LightGBM's default of 20 is very restrictive at n ~ 400 site-years;
                             # 5 matches ranger's min.node.size
  feature_fraction = 0.8,    # = XGB colsample_bytree
  bagging_fraction = 0.8,    # = XGB subsample
  bagging_freq     = 1,      # required for bagging_fraction to take effect
  num_threads      = 1,      # parallelism comes from mclapply over LOSO folds
  seed             = 42,
  verbosity        = -1
)
```

The one deliberate deviation from "pure library defaults" is `min_data_in_leaf`: leaving it at 20
would have regularised LightGBM far more heavily than either other learner and confounded the
comparison.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/run_v10_LGB.R <dataset> [smoke]` | LOSO training → `LGB_v10{,_all_sites}/LGB_{predictions,metrics}_LOSO.csv` |
| `scripts/run_v10_LGB_SHAP.R <dataset> [smoke]` | TreeSHAP via `treeshap::lightgbm.unify` → `LGB_site_shap_M04_M08.csv` |
| `scripts/run_v10_LGB_plots.sh [dataset]` | regenerates every model-dependent figure from the LightGBM outputs |
| `scripts/plot_v10_learner_comparison.R` | three-way RF / XGBoost / LightGBM comparison figures |

Figures are produced by **the same plot scripts** the RF and XGBoost pipelines use, retargeted via
the `V10_IN_DIR` / `V10_PREFIX` / `V10_OUT_ROOT` environment variables read by
`scripts/v10_model_family.R` (a verified byte-identical no-op when unset).

`lgb.Booster` is an R6 object wrapping a C++ handle and does not survive `saveRDS` across sessions,
so the SHAP script re-trains the full-data model in-process — same approach as the XGBoost run.
LOSO folds are parallelised with `mclapply`; set `OMP_NUM_THREADS=1` so each worker stays on one core.

## Results

See [`metrics_comparison.md`](metrics_comparison.md) for the three-way comparison, the figures
`skill_3way.png` / `attribution_3way.png` in this folder, and the **LightGBM** option in the
report's learner toggle (Section 12).

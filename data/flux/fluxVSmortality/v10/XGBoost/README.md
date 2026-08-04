# XGBoost — same data, same variables, different learner

A full parallel run of the V10 analysis in which **only the learner changed**: gradient-boosted
trees (`xgboost`) instead of random forest (`ranger`). Everything the RF pipeline used is held
fixed, so any difference in the results is attributable to the learner alone.

Nothing here overwrites the RF results. The RF outputs stay in
`derived_tables/outputs_afterEGU_results/RF_v10{,_all_sites}/` and the RF figures stay in
`plots/V10/{all_sites,sites_with_high_Tcover}/`.

## What is held fixed (identical to the RF baseline)

| Held fixed | Value |
|---|---|
| Datasets | all sites **112 / 414 site-years**, high tree cover **93 / 395 site-years** — same harmonized files, read-only |
| Responses (EFPs) | GPP<sub>sat</sub>, NEP<sub>max</sub>, ET<sub>max</sub>, uWUE, WUE |
| Predictor blocks | **C** climate (`lag1_`/`lag2_`), **T** traits, **D** disturbance, **M** memory (`{resp}_lag1[/lag2]`, raw or anomaly) |
| Model set | the same 24 configs (M1–M8 × raw/anom × 12m/24m) |
| Predictor selection | `get_predictor_cols()` copied verbatim from `run_v10_RF_ranger.R` |
| Evaluation | leave-one-site-out (LOSO), same folds, same RMSE / MAE / R² definitions |
| SHAP | TreeSHAP on M4 / M6 / M8 (raw + anom), same per-site scheme, same driver groups |
| Seed | 42 |

## What changed — the learner

| | RF baseline (`ranger`) | XGBoost (`xgboost`) |
|---|---|---|
| Algorithm | bagged trees, grown independently in parallel | boosted trees, grown sequentially on residuals |
| Ensemble size | `num.trees = 500` | `nrounds = 500` |
| Randomness per split/tree | `mtry ≈ p/3` predictors sampled per split | `colsample_bytree = 0.8`, `subsample = 0.8` |
| Depth control | grown to purity (`min.node.size = 5`) | `max_depth = 6`, `min_child_weight = 1` |
| Shrinkage | none | `learning_rate = 0.05` |

**XGBoost hyperparameters (untuned).** These are sensible defaults, not a tuned configuration —
the point of this run is the learner comparison, not a best-possible model:

```r
NROUNDS <- 500                       # mirrors the RF's 500 trees
XGB_PARAMS <- list(
  objective        = "reg:squarederror",
  learning_rate    = 0.05,           # lowered from the xgboost default 0.3:
                                     # 500 rounds at 0.3 badly overfits n ~ 400 site-years
  max_depth        = 6,
  subsample        = 0.8,
  colsample_bytree = 0.8,
  min_child_weight = 1,
  nthread          = 1,              # parallelism comes from mclapply over LOSO folds
  seed             = 42
)
```

## Scripts

| Script | Purpose |
|---|---|
| `scripts/run_v10_XGB.R <dataset> [smoke]` | LOSO training → `XGB_v10{,_all_sites}/XGB_{predictions,metrics}_LOSO.csv` |
| `scripts/run_v10_XGB_SHAP.R <dataset> [smoke]` | TreeSHAP via `treeshap::xgboost.unify` → `XGB_site_shap_M04_M08.csv` |
| `scripts/run_v10_XGB_plots.sh [dataset]` | regenerates every RF-dependent figure from the XGBoost outputs |
| `scripts/v10_model_family.R` | path-override helper (see below) |

`xgb.Booster` objects do not survive `saveRDS` across sessions, so the SHAP script re-trains the
full-data model in-process rather than loading a saved one. LOSO folds are parallelised with
`mclapply(mc.cores = 60)` and `nthread = 1` per fit.

### How the figures are reused, not duplicated

The plot scripts are **the same files** the RF pipeline uses. `scripts/v10_model_family.R` reads
three environment variables and, when they are set, repoints the inputs and the output root:

```bash
V10_IN_DIR=derived_tables/outputs_afterEGU_results/XGB_v10_all_sites \
V10_PREFIX=XGB V10_OUT_ROOT=plots/V10/XGBoost \
  Rscript scripts/plot_v10_RMSE_paired_violin.R all_sites
```

With the variables unset the override is a verified **byte-identical no-op**, so the RF figures
regenerate exactly as before.

## Results

See `metrics_comparison.md` in this folder for the full RF-vs-XGBoost comparison, and the
**XGBoost** option in the RF-structure toggle of the interactive report.

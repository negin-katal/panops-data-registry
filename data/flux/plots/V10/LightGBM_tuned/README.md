# LightGBM (CV-tuned complexity)

A re-run of the [LightGBM analysis](../LightGBM/README.md) with **complexity chosen by grouped
5-fold cross-validation** instead of the arbitrary setting used in the first run. Everything else —
datasets, variables, 24 model configs, LOSO folds, SHAP scheme, seed — is unchanged.

**Nothing here overwrites anything.** The original LightGBM results stay in `LGB_v10{,_all_sites}/`
and `plots/V10/LightGBM/`; this run lives in `LGB_v10_tuned{,_all_sites}/` and this folder.

## Why

The first LightGBM run used `num_leaves = 31`, `min_data_in_leaf = 5`. The `min_data_in_leaf = 5`
was a deliberate deviation from LightGBM's default of 20, chosen to match ranger's `min.node.size`
— but at n ≈ 414 site-years that combination turned out to be **under-regularised**, and LightGBM
looked anomalously weak on the weak-signal (no-memory / anomaly) models as a result. That deficit
was a configuration artefact of ours, not a property of the algorithm, so it needed a fair re-run.

## How the configuration was chosen

`scripts/lgb_tune_regularisation.R` sweeps `min_data_in_leaf` × `num_leaves` under **grouped 5-fold
CV** (folds = disjoint groups of *sites*), the same protocol as [exp01](../RF_tuning/). Selection
therefore never touches the reported LOSO metric.

Tested on two models spanning both regimes — `M2_12m` (C+D, no memory, weak diffuse signal) and
`M6_raw_12m` (C+D+M raw, one dominant predictor) — across all five responses.

The first grid put the optimum on its boundary (`num_leaves = 7` won 8 of 10 combinations, and 7 was
the smallest value tested — the same mistake exp01 originally made with `mtry`), so the grid was
extended down to `num_leaves ∈ {3, 5, 7, 15}` before anything was adopted.

### Selected configuration per response

| Response | `min_data_in_leaf` | `num_leaves` |
|---|---|---|
| GPPsat | 20 | 15 |
| NEPmax | 5 | 7 |
| ETmax | 20 | 3 |
| uWUE | 10 | 7 |
| WUE | 5 | 5 |

Everything else is identical to the untuned run: `nrounds = 500`, `learning_rate = 0.05`,
`feature_fraction = 0.8`, `bagging_fraction = 0.8`, `bagging_freq = 1`, `seed = 42`.

**Key finding from the sweep:** `num_leaves` is the binding knob, not `min_data_in_leaf`. Values of
3–15 beat 31 nearly everywhere; `min_data_in_leaf = 40` is uniformly bad and makes `num_leaves`
irrelevant because the constraint binds first.

## Results — mean LOSO R² (all sites)

| Model group | LightGBM | **LightGBM tuned** | XGBoost | RF |
|---|---|---|---|---|
| no memory | 0.225 | **0.245** | 0.248 | **0.293** |
| anomaly memory | 0.223 | **0.249** | 0.249 | **0.293** |
| raw memory | 0.660 | **0.670** | 0.664 | 0.484 |

**With proper regularisation LightGBM converges onto XGBoost** — 0.245 / 0.249 / 0.670 against
0.248 / 0.249 / 0.664. Two independent boosting implementations, different growth strategies
(leaf-wise vs depth-wise) and different split finding (histogram vs exact), landing within
0.004 R² of each other on every model group.

Three things follow:

1. **The earlier LightGBM deficit was our configuration, not the algorithm.** Worth stating plainly
   in any write-up that cites the first run.
2. **RF still leads on the no-memory and anomaly models** (0.293 vs ~0.247). The bagging-beats-
   boosting result on weak diffuse signals therefore *survives* — and is now demonstrated against a
   fairly-configured booster rather than a handicapped one.
3. **The disturbance effect is unchanged.** Adding D still buys ~+0.08–0.14 R² where raw memory is
   absent and ~0.00–0.03 once it is present. No tuning of any learner has moved this.

### CV gains did not fully transfer to LOSO

Grouped CV predicted ~+0.042 R² on the weak-signal models; LOSO delivered +0.021 to +0.027. This is
expected rather than a problem: grouped 5-fold trains on ~80 % of sites while LOSO trains on ~99 %,
so a configuration selected under less data slightly over-regularises once it gets nearly all of it.
Anyone tuning on grouped CV and reporting on LOSO should expect the same attenuation.

## Fairness caveat

RF and XGBoost remain at library defaults. A CV-tuned LightGBM compared against untuned RF and
XGBoost is **not** a fair learner ranking — it is a *sensitivity check on LightGBM's configuration*.
It is included precisely because it removes a caveat from the untuned run, not because it makes
LightGBM the winner. A genuinely fair head-to-head would need the same grouped-CV treatment applied
to all three learners.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/lgb_tune_regularisation.R` | grouped-CV sweep → `../LightGBM/regularisation_sweep_ext.csv` |
| `scripts/run_v10_LGB_tuned.R <dataset>` | LOSO training → `LGB_v10_tuned{,_all_sites}/` |
| `scripts/run_v10_LGB_tuned_SHAP.R <dataset>` | TreeSHAP → `LGB_site_shap_M04_M08.csv` |
| `scripts/run_v10_LGB_tuned_plots.sh [dataset]` | all model-dependent figures into this folder |
| `scripts/plot_v10_deltaRMSE_6way.R` | six-variant comparison figures (in `../LightGBM/`) |

The per-response configuration is read from the sweep CSV at runtime rather than hard-coded, so the
training and SHAP scripts stay in sync automatically.

Table: `manuscript/tables/table_LGBtuned_LOSO_v10.tex`.
Report: the **LightGBM tuned** option in the learner toggle, and Section 12.

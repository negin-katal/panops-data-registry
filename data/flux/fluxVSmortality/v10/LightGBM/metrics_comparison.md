# RF vs XGBoost vs LightGBM — results

Same datasets, same variables, same 24 model configs, same LOSO folds; only the learner differs.
See [`README.md`](README.md) for the LightGBM configuration and
[`../XGBoost/metrics_comparison.md`](../XGBoost/metrics_comparison.md) for the two-way version.

## 1. Predictive skill (mean LOSO R², by model group)

| Model group | RF | XGBoost | LightGBM |
|---|---|---|---|
| **raw memory** — all sites | 0.484 | **0.664** | **0.660** |
| **raw memory** — high tree cover | 0.431 | **0.632** | **0.631** |
| anomaly memory — all sites | **0.293** | 0.249 | 0.223 |
| anomaly memory — high tree cover | **0.273** | 0.249 | 0.217 |
| no memory — all sites | **0.293** | 0.248 | 0.225 |
| no memory — high tree cover | **0.272** | 0.250 | 0.217 |

**The two boosters land within 0.004 R² of each other on the raw-memory models** (0.664 vs 0.660;
0.632 vs 0.631) despite being independent implementations with different tree-growth strategies
(depth-wise vs leaf-wise) and different split-finding (exact vs histogram). That is a strong
replication, and it splits the same way in both directions:

- **Where a dominant predictor exists** (raw prior-year EFP), both boosters gain ~0.18–0.20 R² over
  RF. Boosting is greedy — it fits the strong column on the first rounds — whereas RF at the default
  `mtry = ⌊√p⌋` offers it at only ~6 % of splits. This is exactly the deficiency
  [exp01/exp02](../RF_tuning/) diagnosed, and both boosters fix it without any tuning trick.
- **Where no dominant predictor exists** (anomaly and no-memory models, signal spread thinly over
  ~240–440 weak correlated columns), **RF wins** and LightGBM is slightly the weakest of the three.
  Bagging averages that noise; boosting chases it. LightGBM's leaf-wise growth is the more
  aggressive of the two boosters, which fits it being marginally worse here.

## 1b. Does adding disturbance help? (model performance, with-D vs without-D)

Organised around the contrast that matters for the research question: every model pair that differs
*only* by the disturbance block **D**, with M5–M8 split by memory type. Mean ΔR² from adding D,
averaged over the 5 EFPs and both windows (all sites / high tree cover):

| Model group | RF | XGBoost | LightGBM |
|---|---|---|---|
| no memory (M1→M2, M3→M4) | +0.078 / +0.087 | +0.096 / +0.120 | +0.094 / +0.127 |
| anomaly memory (M5→M6, M7→M8) | +0.077 / +0.087 | +0.092 / +0.125 | +0.104 / +0.136 |
| **raw memory** (M5→M6, M7→M8) | **−0.003 / +0.028** | **+0.009 / +0.014** | **+0.005 / +0.023** |

Per pair (all sites, both windows averaged):

| Pair | memory | RF | XGBoost | LightGBM |
|---|---|---|---|---|
| M1 → M2 | none | 0.095 | 0.115 | 0.110 |
| M3 → M4 | none | 0.061 | 0.078 | 0.078 |
| M5 → M6 | anomaly | 0.092 | 0.099 | 0.123 |
| M7 → M8 | anomaly | 0.062 | 0.084 | 0.084 |
| M5 → M6 | **raw** | **−0.007** | **0.008** | **0.003** |
| M7 → M8 | **raw** | **0.001** | **0.009** | **0.008** |

**Disturbance carries real predictive information — but only where raw memory is absent.** Adding D
buys roughly **+0.08 to +0.14 R²** in the no-memory and anomaly-memory models, and **essentially
nothing (0.00–0.03)** once the response's own raw previous-year value is in the model. All three
learners agree, so this is a property of the *data*, not of the algorithm: the raw lag already
encodes the site's state — including whatever disturbance occurred before year *t*−1 — leaving
little for the disturbance columns to add.

This is the predictive-skill counterpart of the SHAP result in §2: the same models where D stops
helping are the ones where D's attribution collapses. Figures: `disturbance_effect_3way.png`,
`disturbance_R2_paired_3way.png`, `disturbance_effect_by_EFP_3way.png`.

## 1c. The same contrast in RMSE — four learners (incl. exp02-tuned RF)

Mean % change in LOSO RMSE from adding D (**negative = less error = disturbance helps**),
averaged over the 5 EFPs and both windows (all sites / high tree cover):

| Model group | RF | RF exp02 | XGBoost | LightGBM |
|---|---|---|---|---|
| no memory | −5.87 / −5.70 | −5.87 / −5.70 | −6.86 / −7.40 | −6.63 / −7.60 |
| anomaly memory | −5.81 / −5.72 | −5.81 / −5.72 | −6.56 / −7.72 | −7.11 / −8.06 |
| **raw memory** | **−0.28 / −2.37** | **−0.26 / −0.10** | **−1.21 / −1.73** | **−1.08 / −3.10** |

Per pair, all sites (both windows averaged):

| Pair | RF | RF exp02 | XGBoost | LightGBM |
|---|---|---|---|---|
| M1 → M2 | −7.02 | −7.02 | −8.12 | −7.85 |
| M3 → M4 | −4.73 | −4.73 | −5.61 | −5.41 |
| M5 → M6 anom | −6.74 | −6.74 | −7.21 | −8.62 |
| **M5 → M6 raw** | **+0.04** | **−0.30** | **−1.17** | **−0.80** |
| **M7 → M8 raw** | **−0.60** | **−0.23** | **−1.26** | **−1.36** |

**RF and RF exp02 are identical on every non-raw row** — exp02 only ever modified the raw-memory
models, so this doubles as an internal consistency check on the whole pipeline.

The RMSE view says the same thing as the R² view: disturbance cuts prediction error by **~6–8 %**
wherever raw memory is absent, and by **only 0–3 %** once it is present — in all four learners.
Figures: `deltaRMSE_4way.png`, `RMSE_paired_4way.png`, `deltaRMSE_by_EFP_4way.png`.

## 2. Driver attribution (SHAP) — the shift is a property of *boosting*

Disturbance share of total |SHAP| (%):

| Model | RF | XGBoost | LightGBM | | RF | XGBoost | LightGBM |
|---|---|---|---|---|---|---|---|
| | **all sites** | | | | **high tree cover** | | |
| M4_12m (no memory) | 41.0 | 34.7 | 34.8 | | 35.9 | 30.8 | 29.2 |
| M4_24m (no memory) | 35.7 | 30.9 | 29.4 | | 30.5 | 26.7 | 25.3 |
| M6_anom_12m | 55.2 | 48.0 | 48.8 | | 47.0 | 41.6 | 42.6 |
| M6_anom_24m | 45.6 | 41.2 | 40.0 | | 39.1 | 35.9 | 35.9 |
| M8_anom_12m | 40.3 | 35.1 | 34.9 | | 35.9 | 29.7 | 28.4 |
| M8_anom_24m | 35.2 | 31.4 | 29.8 | | 30.8 | 27.1 | 24.9 |
| **M6_raw_12m** | **48.8** | **23.8** | **26.1** | | **41.5** | **23.3** | **20.0** |
| **M6_raw_24m** | **37.2** | **14.1** | **17.2** | | **35.1** | **16.6** | **14.8** |
| **M8_raw_12m** | **35.4** | **21.3** | **19.0** | | **32.0** | **19.1** | **17.5** |
| **M8_raw_24m** | **28.9** | **13.1** | **14.7** | | **27.7** | **15.4** | **15.4** |

Corresponding Memory share in the raw-memory models (all sites): RF 11.0–16.6 %, XGBoost
34.5–51.9 %, LightGBM 38.6–43.7 %.

**Two independent boosting implementations move the attribution by almost the same amount.** In the
raw-memory models both cut the disturbance share roughly in half relative to RF and load the freed
attribution onto Memory. In the anomaly and no-memory models all three learners agree within a few
points.

This settles the question the XGBoost run raised: the Disturbance→Memory shift is **not an artefact
of one library.** It is what boosting does when a single predictor (the site's own previous-year
value) already encodes site identity, baseline level, and any disturbance before year *t*−1 — there
is simply less residual variance left for the disturbance columns to explain.

## 3. What this means for the disturbance question

| | Spread across the three learners |
|---|---|
| **raw-memory models** | disturbance share moves **~15–23 percentage points** (e.g. M6_raw_12m: 48.8 → 23.8 / 26.1) |
| **anomaly & no-memory models** | disturbance share moves only **~4–7 points** |

- A disturbance effect estimated from a **raw-memory model is conditional on the learner** and should
  never be reported without stating it. Three reasonable, defensible learners disagree by a factor
  of two on that number.
- The **anomaly-memory and no-memory models are stable across all three learners** and are therefore
  the defensible lens for a disturbance conclusion meant to be robust.
- Note this is about *attribution*, not about ecology: none of this is evidence that disturbance
  matters less. It is evidence that the raw-memory design confounds the question.

## 4. Practical reading

| Goal | Preferred setup |
|---|---|
| Best predictive skill on EFPs | either booster with raw memory (they tie), or exp02-tuned RF |
| Best model without memory | **RF** — bagging beats boosting on the weak-diffuse predictor sets |
| Attributing the disturbance effect | anomaly-memory / no-memory models; report the learner |
| Fastest to run | **LightGBM** — roughly 5× quicker than XGBoost here (histogram binning) |

Files: metrics `LGB_v10{,_all_sites}/LGB_metrics_LOSO.csv`, SHAP `…/LGB_site_shap_M04_M08.csv`,
LaTeX table `manuscript/tables/table_LGB_LOSO_v10.tex`, figures `skill_3way.png` /
`attribution_3way.png` and the per-dataset folders here, plus the **LightGBM** option in the
report's learner toggle (Section 12).

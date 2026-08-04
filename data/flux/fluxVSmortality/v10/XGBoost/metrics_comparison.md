# RF vs XGBoost — results

Same datasets, same variables, same LOSO folds; only the learner differs. See
[`README.md`](README.md) for the configuration.

## 1. Predictive skill (mean LOSO R², by model group)

| Model group | RF all-sites | XGB all-sites | RF high-Tcover | XGB high-Tcover |
|---|---|---|---|---|
| **raw memory** (M5–M8 raw) | 0.484 | **0.664** | 0.431 | **0.632** |
| anomaly memory (M5–M8 anom) | **0.293** | 0.249 | **0.273** | 0.249 |
| no memory (M1–M4) | **0.293** | 0.248 | **0.272** | 0.250 |

**The learner swap is not a uniform improvement — it splits by model group.**

- **Raw-memory models: XGBoost wins big** (+0.18 all-sites, +0.20 high-Tcover). Boosting is
  greedy: it fits the dominant prior-year EFP on the first rounds and then boosts the residuals.
  Random forest at the default `mtry ≈ p/3` only offers that column at ~⅓ of splits, so it
  under-uses it — the exact deficiency [exp01/exp02](../RF_tuning/) diagnosed. **XGBoost recovers
  that gain for free, without the `always.split` trick.** For reference on all-sites GPP<sub>sat</sub>
  M6 raw 12m: RF baseline 0.554 → exp02-tuned RF 0.723 → XGBoost 0.712.
- **Anomaly and no-memory models: RF wins** (−0.04 / −0.02 for XGB). With no dominant predictor,
  the signal is spread thinly over ~240–440 weak, correlated columns. Bagging many decorrelated
  deep trees averages that noise well; boosting sequentially chases it and overfits slightly.

Largest single-model gains (all-sites, raw memory) land on the EFPs RF handled *worst*:

| Model | Response | RF | XGB | Δ |
|---|---|---|---|---|
| M6_raw_12m | uWUE | 0.297 | 0.555 | +0.258 |
| M6_raw_12m | WUE | 0.356 | 0.613 | +0.257 |
| M8_raw_12m | uWUE | 0.283 | 0.532 | +0.248 |
| M8_raw_12m | WUE | 0.348 | 0.575 | +0.226 |
| M6_raw_12m | ET<sub>max</sub> | 0.502 | 0.711 | +0.209 |

## 2. Driver attribution (SHAP) — the important caveat

Share of total |SHAP| per driver group, all-sites:

| Model | Disturbance RF → XGB | Memory RF → XGB |
|---|---|---|
| M4_12m (no memory) | 41.0 → 34.7 (−6.3) | — |
| M4_24m (no memory) | 35.7 → 30.9 (−4.8) | — |
| M6_anom_12m | 55.2 → 48.0 (−7.2) | 0.1 → 0.2 |
| M6_anom_24m | 45.6 → 41.2 (−4.4) | 0.2 → 0.6 |
| M8_anom_12m | 40.3 → 35.1 (−5.2) | 0.1 → 0.2 |
| M8_anom_24m | 35.2 → 31.4 (−3.8) | 0.2 → 0.8 |
| **M6_raw_12m** | **48.8 → 23.8 (−25.0)** | 11.2 → **42.9** |
| **M6_raw_24m** | **37.2 → 14.1 (−23.1)** | 16.6 → **51.9** |
| **M8_raw_12m** | **35.4 → 21.3 (−14.1)** | 11.0 → **34.5** |
| **M8_raw_24m** | **28.9 → 13.1 (−15.8)** | 15.5 → **48.9** |

**Better prediction bought a weaker-looking disturbance signal.** In the raw-memory models the
attribution shifts massively from Disturbance to Memory: XGBoost explains the same site-years
largely *from the site's own previous-year value*, which already encodes the site's identity,
its baseline level, and any disturbance that occurred before year *t−1*. There is less residual
variance left for the disturbance columns to explain, so their SHAP share roughly halves.

This is a **model-choice artefact, not ecological evidence that disturbance matters less.** The
practical consequence for the disturbance question:

- **Raw-memory models are fragile for attribution** — the disturbance share moves 14–25 percentage
  points purely from swapping the learner.
- **Anomaly-memory and no-memory models are far more stable** — 4–7 points across the same swap.
  If a disturbance conclusion needs to be robust to learner choice, those are the defensible lens.
- Reporting the disturbance effect from a raw-memory model should always state the learner and
  its memory handling, because the number is conditional on both.

## 3. Practical reading

| Goal | Preferred setup |
|---|---|
| Best predictive skill on EFPs | XGBoost with raw memory (or exp02-tuned RF — they land in the same place) |
| Best *predictive* model without memory | RF (bagging beats boosting on the weak-diffuse predictor sets) |
| Attributing the disturbance effect | anomaly-memory / no-memory models; report the learner alongside the estimate |

Files: metrics `XGB_v10{,_all_sites}/XGB_metrics_LOSO.csv`, SHAP `…/XGB_site_shap_M04_M08.csv`,
LaTeX table `manuscript/tables/table_XGB_LOSO_v10.tex`, figures in this folder, and the **XGBoost**
option in the report's RF-structure toggle.

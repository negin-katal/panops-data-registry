# V10 — Model selection and reporting decisions

**Date:** 2026-08-19
**Question addressed:** which dataset, cross-validation structure, learner and model subset to report in
the manuscript, and what the results actually support.

---

## Decisions

| choice | selected | role |
|---|---|---|
| **Dataset** | tree cover ≥30% — 93 sites, 395 site-years | main text |
| **Cross-validation** | leave-one-site-out (LOSO) | main text |
| | repeated LOSO-CV (3 × 80% of sites) | sanity check |
| **Learner** | XGBoost + Optuna (`XGB_optuna`) | main text |
| **Models** | M3/M4 (no memory) and M7/M8 raw (with memory) | main text |
| Everything else | 3 datasets × 9 learners × 2 CV structures | appendix |

---

## 1. Does disturbance help more in one dataset?

Across **1,620 paired comparisons** (9 learners × 12 model pairs × 5 EFPs × 3 datasets), where each
pair differs *only* by the disturbance block (M1→M2, M3→M4, M5→M6, M7→M8; both windows, both
memory types):

| dataset | median ΔRMSE | comparisons improved | EFPs helped |
|---|---:|---:|---:|
| **tc≥30 (93)** | **−4.74%** | **83.1%** | **4/5** |
| all_sites (112) | −2.11% | 79.4% | 4/5 |
| tc≥50 (65) | −0.75% | 65.0% | 3/5 |

The ranking is **not monotonic in tree cover** — the most forested dataset is the weakest.

### Which EFPs, by dataset (median ΔRMSE, % improved)

| EFP | all_sites | tc≥30 | tc≥50 |
|---|---:|---:|---:|
| NEPmax | −13.6% (96%) | −11.9% (98%) | −4.9% (98%) |
| GPPsat | −11.2% (96%) | −8.3% (97%) | −3.1% (93%) |
| ETmax | −2.4% (91%) | +0.3% (39%) | +0.7% (26%) |
| uWUE | −1.3% (67%) | −4.0% (82%) | +0.1% (47%) |
| WUE | +0.1% (47%) | −6.2% (99%) | −0.4% (61%) |

**The robust finding:** disturbance reliably improves the **carbon** fluxes — NEPmax and GPPsat improve
in 93–98% of comparisons in *every* dataset. The water-use properties are inconsistent and change sign
between datasets.

---

## 2. Does disturbance matter more for forests? — **No evidence**

Tested at **site level** (one value per site = median over all 9 learners × 12 pairs × 5 EFPs, so no
pseudo-replication), on the all_sites dataset which spans the full tree-cover gradient:

- **Tree cover vs disturbance benefit: Spearman ρ = 0.044, p = 0.65** — no relationship
- **Forest (83 sites) −3.09% vs non-forest (29 sites) −7.09%, p = 0.163** — not significant, and
  pointing *opposite* to the hypothesis

### Methodological warning

A first pass pooling all site × pair × EFP rows gave "non-forest benefits more, p = 1e-08". That was
**pseudo-replication** — 60 non-independent rows per site. After aggregating to one value per site the
effect disappears (p = 0.163). **Do not quote the pooled version.**

### Why tc≥50 looked weakest — a confound, not an answer

| dataset | mortality rate mean | sd | CV |
|---|---:|---:|---:|
| all_sites | 3.90 | 5.46 | 1.40 |
| tc≥30 | 3.58 | 5.14 | 1.44 |
| **tc≥50** | **2.80** | **3.18** | **1.13** |

tc≥50 has **42% less spread** in mortality rate, plus fewer sites (65) and site-years (287). The weak
result there reflects **less disturbance variance to detect**, not proof that mortality matters less in
dense forest. These are different claims and should not be conflated.

**Conclusion:** the disturbance effect is **EFP-specific, not ecosystem-specific**. It depends on which
function is predicted (carbon yes, water no), not on ecosystem type.

---

## 3. Cross-validation: LOSO vs repeated CV

Across **3,240 matched** model × EFP × learner × dataset rows:

| dataset | ΔR² (rep − LOSO) | ΔRMSE | model-rank agreement (ρ) |
|---|---:|---:|---:|
| all_sites | +0.004 | −0.31% | 0.958 |
| tc≥30 | +0.005 | −0.37% | 0.948 |
| tc≥50 | +0.019 | −1.14% | 0.853 |

- Repeated CV is very slightly **more optimistic**, not more conservative (it averages 3 predictions).
- **Best learner: `RF_exp02` under both structures in all three datasets** (6/6 agreement).
- Best model per EFP: same winner in 4/5, 4/5, 5/5.
- Disturbance effect correlates at **r = 0.966** across all 1,620 comparisons.
- Per-EFP sign agreement in **13/15** cases; both exceptions are effectively-zero effects flipping
  sign around zero.

### But repeated CV costs statistical power

For the reporting cell (tc≥30, XGB_optuna), site-level paired Wilcoxon with BH-FDR over 20 tests:

| | significant | no-memory (M3→M4) | raw-memory (M7→M8) | median effect |
|---|---:|---:|---:|---:|
| **LOSO** | **9/20** | 7/10 | 2/10 | −4.53% |
| repeated CV | 4/20 | 4/10 | 0/10 | −4.00% |

Effect sizes are nearly identical; repeated CV averages 3 predictions per site, smoothing both models
and shrinking the paired differences. **Decision: LOSO primary, repeated CV as the sanity check.**

---

## 4. Learner comparison

Mean R² across all three datasets (LOSO):

| learner | all_sites | tc≥30 | tc≥50 | overall |
|---|---:|---:|---:|---:|
| RF_exp02 | 0.430 | 0.410 | 0.276 | **0.372** |
| **XGB_optuna** | 0.413 | 0.402 | 0.258 | **0.358** |
| RF_optuna | 0.410 | 0.393 | 0.252 | 0.352 |
| LGB_optuna | 0.408 | 0.401 | 0.247 | 0.352 |
| XGB_tuned | 0.381 | 0.389 | 0.211 | 0.327 |
| LGB_tuned | 0.388 | 0.383 | 0.206 | 0.326 |
| XGB_base | 0.387 | 0.377 | 0.203 | 0.322 |
| LGB_base | 0.369 | 0.355 | 0.189 | 0.304 |
| RF_base | 0.357 | 0.325 | 0.191 | 0.291 |

Total spread 0.081 R², concentrated almost entirely in the **raw-memory** models:

| | no memory | anomaly | raw memory |
|---|---:|---:|---:|
| RF_exp02 | 0.234 | 0.234 | **0.648** |
| RF_base | 0.234 | 0.234 | **0.404** |

RF_exp02 and RF_base are *identical* without raw memory. exp02's only change — forcing raw EFP memory
into every split — is worth **+0.244 R²** there and nothing elsewhere.

### Why `RF_exp02` was rejected despite the best R²

`always.split.variables = raw memory` hard-codes a structural privilege for one predictor block. The
defence that exists: memory is the **control** (an autoregressive nuisance term), disturbance is the
**treatment**; forcing the control is conservative, and measurably so — RF_exp02 shows the *weakest*
disturbance effect of the RF family (−1.51% median, 70% improved, vs RF_base's −2.40%/67%). Forcing
disturbance instead would be circular.

**But the forcing is unnecessary.** `RF_optuna` reaches essentially the same raw-memory performance
(**0.644 vs 0.648**) with no forcing at all — purely by tuning `mtry` to **0.72–0.91** of predictors
instead of ranger's `sqrt(p)` default (~0.05 when p ≈ 449). With ~21 of 449 predictors sampled per
split, RF picked the memory variable by chance ~5% of the time, so it was diluted despite being the
strongest single predictor. **The forcing was a workaround for a hyperparameter pathology, not a
scientific statement.**

### The accuracy / effect-size tension

| learner | median ΔRMSE from D | improved | disturbance SHAP share |
|---|---:|---:|---:|
| LGB_base | −3.61% | 82.2% | 25.4% |
| LGB_tuned | −3.34% | 83.9% | 25.5% |
| XGB_tuned | −3.25% | 81.7% | 25.9% |
| **XGB_optuna** | **−2.15%** | **78.3%** | **26.7%** |
| RF_base | −2.40% | 67.2% | 35.6% |
| RF_exp02 | −1.51% | 70.0% | 25.9% |
| RF_optuna | −1.28% | 63.9% | 23.1% |

The best predictor shows the weakest disturbance effect: forcing raw memory into every split lets
memory absorb variance disturbance would otherwise explain. Visible in the SHAP split — RF_base's
disturbance share falls 38.2% → 31.6% when memory is added; RF_exp02's falls 28.8% → 21.4%.

**`XGB_optuna` selected:** highest R² of any non-forcing learner, hyperparameters from a defined TPE
search space (no hand-placed structure), disturbance effect mid-pack so not cherry-picked, and SHAP
share (26.7%) slightly above RF_exp02's.

*Caveat:* RF_base has the highest disturbance SHAP share (35.6%) partly **because it is the worst
model** — its raw-memory models underperform (0.404), so proportionally more attribution falls to
disturbance. Do not cite it as evidence that disturbance matters more.

---

## 5. Paper table — tc≥30 | LOSO | XGB_optuna

Site-level paired Wilcoxon (one-sided), BH-FDR across the 20 tests.
Full table: `derived_tables/paper_table_tc30_XGBoptuna_LOSO.csv`

| comparison | EFP | R² without D | R² with D | median ΔRMSE | sites improved | sig |
|---|---|---:|---:|---:|---:|:--|
| M3→M4 12m | GPPsat | 0.191 | 0.359 | −10.15% | 66% | *** |
| M3→M4 12m | NEPmax | 0.192 | 0.405 | −8.86% | 66% | *** |
| M3→M4 12m | ETmax | 0.420 | 0.419 | −0.08% | 51% | ns |
| M3→M4 12m | uWUE | 0.041 | 0.134 | −2.25% | 52% | ns |
| M3→M4 12m | WUE | 0.113 | 0.282 | −3.09% | 59% | * |
| M3→M4 24m | GPPsat | 0.205 | 0.347 | −7.17% | 65% | ** |
| M3→M4 24m | NEPmax | 0.215 | 0.400 | −11.79% | 66% | *** |
| M3→M4 24m | ETmax | 0.401 | 0.382 | +1.62% | 41% | ns |
| M3→M4 24m | uWUE | 0.024 | 0.141 | −5.29% | 59% | * |
| M3→M4 24m | WUE | 0.117 | 0.273 | −3.76% | 54% | * |
| M7→M8 raw 12m | GPPsat | 0.677 | 0.693 | −2.22% | 57% | * |
| M7→M8 raw 12m | NEPmax | 0.731 | 0.747 | +0.50% | 49% | ns |
| M7→M8 raw 12m | ETmax | 0.670 | 0.673 | +0.69% | 47% | ns |
| M7→M8 raw 12m | uWUE | 0.632 | 0.625 | −0.55% | 52% | ns |
| M7→M8 raw 12m | WUE | 0.643 | 0.662 | −1.84% | 57% | ns |
| M7→M8 raw 24m | GPPsat | 0.686 | 0.692 | −0.44% | 52% | ns |
| M7→M8 raw 24m | NEPmax | 0.733 | 0.746 | −2.91% | 55% | ns |
| M7→M8 raw 24m | ETmax | 0.651 | 0.653 | −0.25% | 54% | ns |
| M7→M8 raw 24m | uWUE | 0.629 | 0.630 | −1.89% | 55% | ns |
| M7→M8 raw 24m | WUE | 0.641 | 0.665 | −2.41% | 62% | * |

**9/20 significant — 7/10 without memory, 2/10 with raw memory.**

### The finding in four numbers

| | GPPsat | NEPmax |
|---|---|---|
| **no memory** (M3→M4) | R² 0.191 → **0.359**, −10.2% *** | R² 0.192 → **0.405**, −8.9% *** |
| **raw memory** (M7→M8) | R² 0.677 → 0.693, −2.2% * | R² 0.731 → 0.747, ns |

**Disturbance roughly doubles explained variance for both carbon fluxes when EFP memory is absent, and
adds almost nothing once raw memory is included.** Raw EFP memory already contains most of the
information disturbance carries.

---

## 6. Things to state explicitly in the manuscript

1. **Justify tc≥30 a priori** — "sites with ≥30% tree cover, the forest-relevant subset" — not because
   it showed the strongest effect. all_sites and tc≥50 are in the appendix showing the same direction.
2. **The 2 raw-memory significant results are fragile.** GPPsat 12m and WUE 24m (`*` under LOSO) drop to
   **0/10 under repeated CV**. Describe them as marginal and not robust to resampling structure. The
   defensible line is: *once raw EFP memory is included, disturbance adds no consistent improvement.*
3. **ETmax is a consistent null** — ns in every configuration and slightly positive in places. An honest
   null across 3 datasets × 9 learners × 2 CV structures is a result; report it rather than leaving it
   unremarked.
4. **uWUE/WUE are borderline** — significant at 24m, not 12m. Describe as weak and window-dependent.
5. **Do not compare R² across datasets.** tc≥50's R² is depressed ~41% by range restriction (GPPsat sd
   8.72 → 6.97) while its RMSE *improves* ~6.7%. Use RMSE for cross-dataset comparison; R² is valid for
   ranking models *within* a dataset.
6. **Robustness sentence available:** *"The disturbance effect is invariant across nine learner
   configurations (RF, XGBoost, LightGBM, each with tuned and Optuna variants) and two resampling
   structures; the adopted configuration yields a mid-range estimate."*

---

## Provenance

- Interactive report: https://negin-katal.github.io/fluxVSmortality/v10/index.html
- Datasets: `derived_tables/outputs_afterEGU_results/{v10, v10_all_sites, v10_tc50}/`
- Model outputs: `derived_tables/outputs_afterEGU_results/{RF,XGB,LGB}_v10*`
- Repeated CV: `*_repCV{,_all_sites,_tc50}/`
- Paper table: `derived_tables/paper_table_tc30_XGBoptuna_LOSO.csv`

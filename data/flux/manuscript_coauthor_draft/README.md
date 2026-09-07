# Coauthor working draft

Bullet points and figures only — no prose. Built to support decisions, not to be submitted.

## Scope

| | |
|---|---|
| Dataset | tree cover ≥30% (500 m buffer) — **93 sites / 395 site-years** |
| Models | **M3 (C+T) vs M4 (C+T+D)** only |
| Learners | Random forest, XGBoost, LightGBM — **all Optuna-tuned** |
| Windows | 12 m and 24 m |
| Cross-validation | leave-one-site-out **and** repeated LOSO (3 × 80%) |
| Responses | GPPsat, NEPmax, ETmax, **WUE** (uWUE dropped) |

Everything is filtered from results already computed. No models were retrained.

## Files

- `draft_coauthors.tex` — the draft (compile with pdflatex, no bibliography needed)
- `figures/fig1_site_map.*` — sites and EFP distributions (copied from the report)
- `figures/fig2_disturbance_effect_M3M4.*` — paired violins, 4 EFPs × 3 learners × (12m/24m × LOO/rep)
- `figures/fig3_site_shap_composition.*` — per-site SHAP composition, M4, 12 m
- `figures/fig4_grouped_disturbance_shap.*` — disturbance SHAP share by Low/Mid/High category
- `fig2_statistics.csv`, `fig3_shap_shares.csv`, `fig4_statistics.csv` — the numbers behind each figure

## Regenerating

```bash
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
$RS scripts/plot_draft_fig2_M3M4.R
$RS scripts/plot_draft_fig3_site_shap.R
$RS scripts/plot_draft_fig4_grouped_shap.R
```

## Known issue

`RF_v10_optuna`'s SHAP table lost the names of the 14 trait variables containing spaces,
parentheses or slashes (`Leaf C`, `Leaf N (area)`, `Leaf C/N ratio`, …), leaving ~35% of the
attribution in an unlabelled group. Group membership is unambiguous — 14 unnamed + 7 named =
the 21 traits the other two learners show — so the draft scripts reassign them to Traits.
The extraction in `scripts/run_v10_RF_optuna_SHAP.R` should still be fixed at source; this
also affects the RF-Optuna panels of Sections 8–9 in the interactive report.

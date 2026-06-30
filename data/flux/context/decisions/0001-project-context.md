# 0001 — Project Context and Key Decisions

**Date:** 2026-06-29
**Status:** Active

## Decisions

### D1: 24mbench as canonical benchmark
Unified dataset with 24-month meteorological lag window (644 site-years, 166 sites).
Supersedes earlier 52-site and 3-year datasets. All main results reported on 24mbench.

### D2: LOSO cross-validation (not random CV)
Leave-One-Site-Out preserves spatial independence. Random CV would allow the model
to see the same site in training and validation — inflating performance for site-rich
FLUXNET data.

### D3: 8-model design (M01–M08)
Each model adds one predictor block (C, +D, +T, +M) in a full factorial design.
This lets us isolate the marginal contribution of each block, including disturbance.

### D4: Both memory types shown (anomaly + raw-lag)
- Anomaly memory: EFP encoded as z-score of lagged value → primary encoding
- Raw-lag: lagged EFP value directly → secondary/supplementary comparison
Main manuscript reports anomaly; raw-lag appears as supplementary or comparison column.

### D5: noWET as secondary posthoc analysis
Wetland sites (WET) have qualitatively different dynamics. The noWET subset
(515 site-years, 128 sites) tests whether conclusions hold without them.

### D6: v2-2 disturbance product (new_mortality_rate)
The `new_mortality_rate_pct_*` columns from the v2-2 product replace the v1
`mortality_intensity_pct_*` columns in all new analyses and figures.
Old plots using v1 are retained in `plots/disturbance_effects/` but not updated.

### D7: Overleaf as canonical manuscript location
Git clone at `/home/nk1125/overleaf_panops/`. Push via `bash manuscript/push_to_overleaf.sh`.
All LaTeX edits made locally in `manuscript/` and synced — never edit directly on Overleaf.

### D8: Nature Springer format (sn-article.cls)
`sidewaystable` used for the main results table; `\resizebox` removed because it
conflicts with `sidewaystable`'s internal grouping. Use `\scriptsize + \tabcolsep=3pt` instead.

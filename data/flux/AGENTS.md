# Agent Guide — flux analysis

Working directory for all commands: `/mnt/gsdata/projects/panops/panops-data-registry/data/flux/`

## Critical: R runtime

**Always use the conda Rscript, never the system one.**

```bash
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
```

- Conda R: 4.3.3 — all packages installed here
- System `/usr/bin/Rscript`: R 4.1.2 — crashes on every package load (`undefined symbol: R_existsVarInFrame`)

## Script conventions

- `plot_NN_*.R` — produce figures; call `setwd()` internally; output goes to `plots/`
- `run_NN_*.R` — train/evaluate RF models; long-running (hours); launch in tmux
- Notebooks (`NN_*.ipynb`) — data prep and EFP calculation steps

Run a plot script:
```bash
$RSCRIPT plot_14_fig1_manuscript.R
```

Run an RF model in tmux:
```bash
tmux new-session -d -s rf_run
tmux send-keys -t rf_run "$RSCRIPT run_24_RF_LOSO_anomaly_24mbench.R 2>&1 | tee logs/run.log" Enter
tmux capture-pane -t rf_run -p | tail -10
```

## Overleaf sync

```bash
bash manuscript/push_to_overleaf.sh "message"
```

Syncs `manuscript/` → `/home/nk1125/overleaf_panops/` → Overleaf git remote.
Token is baked into the remote URL in that clone. Pull happens automatically before push.

## Key paths

| Path | Contents |
|---|---|
| `derived_tables/outputs_afterEGU_results/` | RF model outputs (metrics, predictions, SHAP, varimp CSVs) |
| `derived_tables/final_disturbance_v2-2_multibuffer.csv` | Canonical disturbance dataset (v2-2, multi-buffer) |
| `derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv` | Main modelling dataset (EFPs + traits + meteo + disturbance) |
| `manuscript/` | LaTeX paper + figures synced to Overleaf |
| `manuscript/tables/` | Table `.tex` files (`\input{tables/...}` in `sn-article.tex`) |
| `plots/manuscript_candidates/` | Candidate figures under review |
| `plots/disturbance_effects/24mbench/` | Disturbance effect plots (delta RMSE, SHAP, R²) |
| `.claude/skills/run-flux-analysis/` | Run skill for this project |

## Installing missing R packages

```bash
$RSCRIPT -e "install.packages('pkg', repos='https://cloud.r-project.org')"
```

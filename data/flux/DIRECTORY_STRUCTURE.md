# Flux Analysis Project Structure

**Project**: The role of tree mortality on ecosystem functional properties  
**Date**: July 2026  
**Status**: Active Analysis

## 📁 Directory Organization

### Core Analysis Directories

#### `scripts/` — All Analysis Scripts (147 files)
Organized R, Python, and shell scripts for data processing, modeling, and visualization.

```
scripts/
├── plot/         (74 files) Visualization and figure generation scripts
│   ├── plot_01_* : Delta RMSE and site-level analysis
│   ├── plot_03_* : SHAP importance visualizations
│   ├── plot_05_* : Disturbance SHAP scatter plots
│   ├── plot_06_* : Site overview and R² analysis
│   ├── plot_07_* : R² disturbance comparisons
│   ├── plot_08_* : Interactive mortality visualizations
│   ├── plot_10_* : EFP explorer and interactive viewers
│   ├── plot_11_* : EFP explorer for main analysis
│   ├── plot_12_* : Site-level SHAP mortality analysis
│   ├── plot_13_* : Site SHAP with new mortality metrics
│   ├── plot_14_* : Manuscript figures (Fig 1 - site map)
│   ├── plot_15_* : Manuscript figures (Fig 2 - RF performance)
│   ├── plot_16_* : Disturbance threshold and SHAP analysis
│   ├── plot_17_* : IGBP and tree cover analysis
│   ├── plot_18_* : IGBP-specific thresholds
│   ├── plot_19_* : Threshold effects per model
│   ├── plot_20_* : Per-model threshold comparisons
│   ├── plot_21_* : Site-level SHAP disturbance metrics
│   ├── plot_26_* : Delta RMSE separate comparisons
│   ├── plot_27_* : Delta RMSE by IGBP
│   ├── plot_28_* : Site SHAP M06/M08 analysis
│   ├── plot_32_* : Mortality distributions
│   ├── plot_33_* : Mortality quantile analysis
│   ├── plot_34_* : Mortality categorization methods
│   ├── plot_35_* : Master categorization tests
│   ├── plot_36_* : Master delta RMSE tests
│   ├── plot_37_* : Master site SHAP tests
│   ├── plot_38_* : Carbon vs water synthesis
│   ├── plot_39_* : SHAP direction analysis
│   ├── plot_40_* : Dose-response mechanisms
│   └── plot_41_* : IGBP cross-tabulation analysis
│
├── model/        (70 files) Random Forest model training & evaluation
│   ├── run_18_* : RF LOSO (Leave-One-Site-Out) models
│   ├── run_19_* : Fixed LOSO variants
│   ├── run_20_* : Precip quantile patches
│   ├── run_21_* : Site-level variable importance
│   ├── run_22_* : Site-level SHAP values
│   ├── run_23_* : Raw memory SHAP extraction
│   ├── run_24_* : Anomaly-based models (24-month benchmarks)
│   ├── run_25_* : SHAP anomaly extraction
│   ├── run_26_* : Post-processing pipelines
│   ├── run_27_* : No-WET filtering variants
│   ├── run_28_* : SHAP extraction (no-WET)
│   ├── run_29_* : Post-processing (no-WET)
│   ├── run_30_* : Post-hoc WET removal
│   ├── run_31_* : Model ensemble (M09, M10)
│   ├── run_32_* : SHAP ensemble extraction
│   ├── run_39_* : v3 harmonized models (all variants)
│   ├── run_40_* : v3 raw memory models
│   ├── run_41_* : v3 SHAP anomaly extraction
│   ├── run_42_* : v3 SHAP raw memory
│   ├── run_43_* : SHAP merge all v3
│   ├── run_44_* : M06 24-month anomaly
│   ├── run_45_* : M06 training
│   └── run_deadwood_*: Deadwood disturbance metrics
│
└── utility/      (3 files) Utility & helper scripts
    ├── step12_shap_continue.R: SHAP continuation handler
    ├── fix_traits_missing_sites.R: Data quality fixes
    └── launch_rf20_after_patch.sh: Model launching helper
```

#### `notebooks/` — Data Preparation Jupyter Notebooks (21 files)
Interactive notebooks for exploratory data analysis, EFP calculations, and modeling setup.

```
notebooks/
├── 01_EFPmodel.ipynb: EFP model exploration
├── 02_climate_data.ipynb: Climate data processing
├── 03_combine_climatedata_EFP.ipynb: Data integration
├── 04_EFP_prediction.ipynb: EFP model predictions
├── 05_model_with_Shap.ipynb: SHAP value calculation
├── 06_model_val_colin.ipynb: Model validation
├── 07_deadwood_Fcover_site_level.ipynb: Deadwood analysis
├── 08_EFP_newModel.ipynb: New EFP model variants
├── 09_visualization.ipynb: Data visualization
├── 10_step12_shap.ipynb: SHAP continuation workflow
├── 11_data_prep_4_modeling.ipynb: Modeling data prep
├── 12_FLUXNET_shuttle.ipynb: FluxNet data retrieval
├── 12_get_elevation_4_metadata.ipynb: Elevation metadata
├── 13_site_info_vis.ipynb: Site information visualization
├── 14_calc_EFPs.ipynb: EFP calculations
├── 15_merge_efp_meteo_mortality.ipynb: EFP-meteo-mortality merge
├── 15_merge_trait_mortality_meteo.ipynb: Trait-based merge
├── 16_growing_season_calc.ipynb: Growing season calculation
├── 17_EFP_anomalies_memory.ipynb: Anomaly memory effects
├── 18_RF_LOSO_EFP.ipynb: RF LOSO model training
├── 19_build_lagged_dataset.ipynb: Lagged feature creation
```

### Output & Results Directories

#### `plots/` — Generated Figures & Visualizations
```
plots/
├── manuscript_candidates/    Main publication figures (PDF + PNG)
│   ├── fig1_site_map_EFP_distributions.*
│   ├── fig2_RF_RMSE_disturbance_effect.*
│   ├── fig2_panels/           Individual EFP panels
│   ├── fig2_per_model/        Model-specific comparisons
│   ├── fig_IGBP_*             IGBP-stratified analysis
│   ├── fig_threshold_*        Disturbance threshold effects
│   ├── mortality_metrics_*    Mortality categorization
│   └── [M02, M04, M06, M08]/  Model-specific outputs
│
├── disturbance_effects/24mbench/  Delta RMSE & SHAP analysis
├── disturbance_metric_test/       Categorization method validation
├── site_shap_*/                   Site-level SHAP visualizations
├── synthesis/                     Summary analysis figures
├── abs_mort_analysis/             Absolute mortality IGBP analysis
├── rel_mort_analysis/             Relative mortality IGBP analysis
└── rel_dist_analysis/             Relative disturbance IGBP analysis
```

#### `derived_tables/` — Processed Datasets & Model Outputs
```
derived_tables/
├── EFP_*.csv                       Processed EFP datasets
├── final_disturbance_*.csv         Disturbance categorization results
├── outputs_afterEGU_results/       Main RF model outputs
│   ├── RF_metrics_LOSO.csv        Model performance metrics
│   ├── RF_predictions_*.csv       Model predictions & residuals
│   ├── RF_SHAP_*.csv              SHAP values per model
│   ├── RF_varimp_*.csv            Variable importance rankings
│   └── [per-model directories]/   Individual model outputs
│
└── disturbance_metric_test/        Disturbance categorization analysis
    ├── tertiles_method.csv        Final categorization results
    └── [analysis folders]/         IGBP confounding checks
```

#### `manuscript/` — Publication & Overleaf Sync
```
manuscript/
├── sn-article.tex                Main LaTeX manuscript
├── sn-article.pdf                Compiled PDF
├── sn-bibliography.bib            Bibliography
├── tables/                         Table `.tex` files
│   ├── table_RF_LOSO_results_*.tex
│   ├── table_RMSE_ratio_*.tex
│   └── [other summary tables]/
│
├── figures/                       Figure directory (if using local)
├── site_disturbance_history/      Dashboard HTML
└── push_to_overleaf.sh           Sync script to Overleaf
```

#### `html_reports/` — Interactive Dashboards & Explorers
```
html_reports/
├── index.html                      Hub page linking to all explorers
├── disturbance_metrics.html        Disturbance impact analysis
├── efp_explorer.html               EFP data explorer
├── mortality_explorer.html         Mortality-disturbance explorer
├── data_quality_report.html        Data quality assessment
└── plots/                          Referenced plot directories
```

#### `results_v3_final/` — Version 3 Harmonized Results
Final outputs from v3 harmonized modeling pipeline (M04, M06, M08 models with disturbance metrics)

#### `logs/` — Run Logs & Error Tracking
```
logs/
├── run_*.log                       Model training logs
├── plot_*.log                      Plot generation logs
└── [date-stamped logs]/
```

### Data Directories

#### `deadwood/` — Deadwood & Forest Loss Data
Processed deadwood detection and forest loss metrics from satellite data

#### `derived_tables/` — Derived Datasets (DVC-tracked)
Large processed datasets tracked via DVC (Data Version Control)

#### `merged_sites_subset*/` — Site Subsets & Versions
Different site filtering and preprocessing variants

#### `plant_trait/` — Plant Trait Database
Trait data for model features (wood density, plant height, etc.)

#### `fluxnet_2017_2025*/` — FluxNet Raw Data
Original FLUXNET tower data (large, requires DVC)

#### `efp_per_site/`, `efp_site_year_results/` — EFP Calculations
Intermediate and final EFP calculation results

### Configuration & Documentation

#### `CLAUDE.md`
Project instructions for Claude AI agent (critical setup info)

#### `AGENTS.md`
Agent guide with R runtime requirements and script conventions

#### `.claude/` — Claude Code Configuration
IDE settings and project-specific skills

#### `flux.code-workspace`
VS Code workspace configuration

#### `.dvc/` — DVC Configuration
Data version control configuration for large files

---

## 🚀 Quick Start Guide

### Running Plot Scripts
All plot scripts call `setwd()` internally. Run from project root:
```bash
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
$RSCRIPT scripts/plot/plot_14_fig1_manuscript.R
# Output: plots/manuscript_candidates/fig1_*.png
```

### Running Model Training Scripts
Launch in tmux for long-running processes:
```bash
tmux new-session -d -s rf_model
tmux send-keys -t rf_model "$RSCRIPT scripts/model/run_24_RF_LOSO_anomaly_24mbench.R 2>&1 | tee logs/run.log" Enter
tmux capture-pane -t rf_model -p | tail -10
```

### Accessing Interactive Explorers
All interactive HTML reports are in `html_reports/`:
- **Hub**: `html_reports/index.html` (local) or GitHub Pages
- **Disturbance Analysis**: `html_reports/disturbance_metrics.html`
- **EFP Explorer**: `html_reports/efp_explorer.html`

### Syncing to Overleaf
```bash
bash manuscript/push_to_overleaf.sh "describe your changes"
```

---

## 📊 Key Analysis Workflows

### 1. Disturbance Impact Analysis Pipeline
1. **Data Prep**: `notebooks/15_merge_efp_meteo_mortality.ipynb`
2. **Model Training**: `scripts/model/run_24_*.R` (RF LOSO)
3. **SHAP Extraction**: `scripts/model/run_25_*.R` and `run_41_*.R`
4. **Visualization**: `scripts/plot/plot_21_site_shap_distmetrics.R`
5. **Analysis**: `scripts/plot/plot_39_shap_direction_analysis.R`, `plot_40_mechanism_*.R`
6. **Dashboard**: `html_reports/disturbance_metrics.html`

### 2. Manuscript Figure Generation
Sequential plot script execution:
- **Fig 1**: `scripts/plot/plot_14_fig1_manuscript.R`
- **Fig 2**: `scripts/plot/plot_15_fig2_RF_performance.R`
- **Fig 2 Panels**: `scripts/plot/plot_16_disturbance_threshold.R`
- **Supporting**: `plot_17_*`, `plot_18_*`, etc.

### 3. Categorization Method Validation
```bash
# Run disturbance metric test
$RSCRIPT scripts/plot/plot_35_master_categorization_test.R
# Outputs: plots/disturbance_metric_test/COMPREHENSIVE_SUMMARY_REPORT.md
```

---

## 📝 File Naming Conventions

| Prefix | Purpose | Directory |
|--------|---------|-----------|
| `plot_NN_*` | Visualization scripts (NN = sequence number) | `scripts/plot/` |
| `run_NN_*` | Model training/evaluation scripts | `scripts/model/` |
| `step_*` | Step-by-step utility scripts | `scripts/utility/` |
| `NN_*.ipynb` | Data prep notebooks (NN = sequence) | `notebooks/` |
| `fig*` | Manuscript figures (PDF + PNG) | `plots/manuscript_candidates/` |
| `*_LOSO.csv` | Leave-One-Site-Out model metrics | `derived_tables/outputs_*/` |
| `*_SHAP.csv` | SHAP values per site | `derived_tables/outputs_*/` |

---

## ⚙️ Critical R Environment Setup

**Always use the conda R environment, NEVER the system R:**

```bash
# ✅ Correct
RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript

# ❌ Wrong (will crash with undefined symbol errors)
/usr/bin/Rscript
```

**Conda R**: 4.3.3 (all packages installed)  
**System R**: 4.1.2 (missing packages, incompatible)

Verify with:
```bash
$RSCRIPT --version
# → R scripting front-end version 4.3.3 (2024-02-29)
```

---

## 📚 Key References

### Model Variants
- **M04**: Climate + Traits + Disturbance
- **M06**: Climate + Memory + Disturbance
- **M08**: Climate + Traits + Memory + Disturbance

### EFP Metrics (5 variables)
- **Carbon**: GPPsat (gross primary productivity at saturated light), NEPmax (net ecosystem productivity)
- **Water**: ETmax (maximum evapotranspiration), uWUE (underlying water-use efficiency), WUE (water-use efficiency)

### Disturbance Metrics (3 approaches)
- **Absolute Mortality**: % tree mortality per site-year
- **Relative Mortality**: mortality relative to tree cover
- **Relative Disturbance**: mortality related to tree cover plus tree cover loss

### Temporal Lags
- **12-month lag**: Disturbance effects lagged 12 months
- **24-month lag**: Benchmark (24-month buffer for disturbance timing)

---

## 🔗 External Resources

- **GitHub Pages Site**: https://negin-katal.github.io/fluxVSmortality/
- **Overleaf Manuscript**: https://git.overleaf.com/698b0715a5817a2efadd24b6 (token in remote config)
- **FLUXNET Data**: https://fluxnet.org/ (via acquired downloads in `fluxnet_2017_2025/`)
- **DVC Storage**: `.dvc/` config points to remote (check local `.dvc/config` for paths)

---

## 📞 Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| R packages not found | Use conda R: `RSCRIPT=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript` |
| Plot script fails | Verify working directory is `/mnt/gsdata/projects/panops/panops-data-registry/data/flux` |
| Model training killed | Run in tmux: `tmux new-session -d -s rf_run` (hosts connection loss) |
| DVC data missing | Run `dvc pull` to fetch large files from remote |
| Plots not showing in HTML | Check relative paths in `html_reports/` match plot directory structure |

---

**Last Updated**: July 15, 2026  
**Maintainer**: Negin Katal  
**Status**: Active (v3 harmonized analysis complete, manuscript in preparation)

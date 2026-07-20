#!/usr/bin/env Rscript
# Generate comprehensive predictor documentation for RF results
# Includes: climate (meteo), traits, mortality/deadwood, and EFP memory

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('GENERATING COMPREHENSIVE PREDICTOR DOCUMENTATION (V2)\n')
cat('====================================================================\n\n')

# =========================================================
# B1 (Lag1 Only)
# =========================================================

cat('BENCHMARK 1 (Lag1 Only)\n')
cat(strrep('=', 50), '\n\n')

dt_b1 <- fread('derived_tables/outputs_afterEGU_results/V10_gs_meteo_benchmarks/benchmark_B1_lag1only_gs_meteo.csv')

# Identify feature groups
trait_cols <- grep('^(P12|P50|P88|gsmax|rdmax)_mean', names(dt_b1), value=TRUE)
mort_cols_cur <- grep('forest_mean_pct_500m$|deadwood_mean_pct_500m$|mortality_intensity_pct_500m$', names(dt_b1), value=TRUE)
mort_cols_lag1 <- grep('forest_mean_pct_500m_lag1$|deadwood_mean_pct_500m_lag1$|mortality_intensity_pct_500m_lag1$', names(dt_b1), value=TRUE)
meteo_cols_all <- grep('^(TA|VPD|P|SW_IN)_', names(dt_b1), value=TRUE)
meteo_cols_cur <- grep('^(TA|VPD|P|SW_IN)_[^_]*$', names(dt_b1), value=TRUE)
meteo_cols_lag1 <- grep('^(TA|VPD|P|SW_IN)_.*_lag1$', names(dt_b1), value=TRUE)
efp_lag_raw <- grep('^(GPPsat|NEPmax|ETmax|uWUE)_lag1$', names(dt_b1), value=TRUE)
efp_lag_anom <- grep('^(GPPsat|NEPmax|ETmax|uWUE)_anom_lag1$', names(dt_b1), value=TRUE)

cat('Feature inventory:\n')
cat('  Traits (static):', length(trait_cols), 'variables\n')
cat('    ', paste(trait_cols, collapse=', '), '\n')
cat('  Meteorology (current):', length(meteo_cols_cur), 'variables\n')
cat('  Meteorology (lag1):', length(meteo_cols_lag1), 'variables\n')
cat('  Mortality/deadwood (current):', length(mort_cols_cur), 'variables\n')
cat('    ', paste(mort_cols_cur, collapse=', '), '\n')
cat('  Mortality/deadwood (lag1):', length(mort_cols_lag1), 'variables\n')
cat('    ', paste(mort_cols_lag1, collapse=', '), '\n')
cat('  EFP memory (raw, lag1):', length(efp_lag_raw), 'variables\n')
cat('  EFP memory (anomaly, lag1):', length(efp_lag_anom), 'variables\n\n')

# Define models with detailed predictor lists
model_configs_b1 <- list(
  M01 = list(predictors = c(meteo_cols_cur, meteo_cols_lag1),
             description = "Climate: current + lag1 meteorology (GS-to-GS)"),
  M02 = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, mort_cols_cur, mort_cols_lag1),
             description = "Climate + Disturbance: meteo + mortality/deadwood current + lag1"),
  M03 = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, trait_cols),
             description = "Climate + Traits: meteo current + lag1 + static plant traits"),
  M04 = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, mort_cols_cur, mort_cols_lag1),
             description = "Full model: Climate + Traits + Disturbance"),
  M05_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, efp_lag_raw),
             description = "Climate + Memory (raw): meteo + raw EFP lag1"),
  M05_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, efp_lag_anom),
             description = "Climate + Memory (anomaly): meteo + EFP anomaly lag1"),
  M06_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, mort_cols_cur, mort_cols_lag1, efp_lag_raw),
             description = "Climate + Disturbance + Memory (raw)"),
  M06_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, mort_cols_cur, mort_cols_lag1, efp_lag_anom),
             description = "Climate + Disturbance + Memory (anomaly)"),
  M07_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, efp_lag_raw),
             description = "Climate + Traits + Memory (raw)"),
  M07_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, efp_lag_anom),
             description = "Climate + Traits + Memory (anomaly)"),
  M08_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, mort_cols_cur, mort_cols_lag1, efp_lag_raw),
             description = "Full + Memory (raw): Climate + Traits + Disturbance + raw EFP memory"),
  M08_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag1, trait_cols, mort_cols_cur, mort_cols_lag1, efp_lag_anom),
             description = "Full + Memory (anomaly): Climate + Traits + Disturbance + EFP anomaly")
)

# Create comprehensive documentation
doc_b1 <- list()
for (model_name in names(model_configs_b1)) {
  config <- model_configs_b1[[model_name]]
  doc_b1[[model_name]] <- data.table(
    Model = model_name,
    Description = config$description,
    N_Predictors = length(config$predictors),
    N_Traits = sum(config$predictors %in% trait_cols),
    N_Meteo_Current = sum(config$predictors %in% meteo_cols_cur),
    N_Meteo_Lag1 = sum(config$predictors %in% meteo_cols_lag1),
    N_Mortality = sum(config$predictors %in% c(mort_cols_cur, mort_cols_lag1)),
    N_EFP_Memory = sum(config$predictors %in% c(efp_lag_raw, efp_lag_anom)),
    Predictors = paste(config$predictors, collapse = "; ")
  )
}

df_doc_b1 <- rbindlist(doc_b1)

# Save B1 predictor doc
out_dir_b1 <- 'derived_tables/outputs_afterEGU_results/RF_V10_B1_lag1'
dir.create(out_dir_b1, recursive=TRUE, showWarnings=FALSE)
out_file_b1 <- file.path(out_dir_b1, 'PREDICTORS.csv')
fwrite(df_doc_b1, out_file_b1)

cat('Saved B1 predictors:', out_file_b1, '\n\n')

# =========================================================
# B2 (Lag1+Lag2)
# =========================================================

cat('BENCHMARK 2 (Lag1+Lag2)\n')
cat(strrep('=', 50), '\n\n')

dt_b2 <- fread('derived_tables/outputs_afterEGU_results/V10_gs_meteo_benchmarks/benchmark_B2_lag1and2_gs_meteo.csv')

trait_cols <- grep('^(P12|P50|P88|gsmax|rdmax)_mean', names(dt_b2), value=TRUE)
mort_cols_cur <- grep('forest_mean_pct_500m$|deadwood_mean_pct_500m$|mortality_intensity_pct_500m$', names(dt_b2), value=TRUE)
mort_cols_lag1 <- grep('forest_mean_pct_500m_lag1$|deadwood_mean_pct_500m_lag1$|mortality_intensity_pct_500m_lag1$', names(dt_b2), value=TRUE)
mort_cols_lag2 <- grep('forest_mean_pct_500m_lag2$|deadwood_mean_pct_500m_lag2$|mortality_intensity_pct_500m_lag2$', names(dt_b2), value=TRUE)
meteo_cols_all <- grep('^(TA|VPD|P|SW_IN)_', names(dt_b2), value=TRUE)
meteo_cols_cur <- grep('^(TA|VPD|P|SW_IN)_[^_]*$', names(dt_b2), value=TRUE)
meteo_cols_lag12 <- grep('^(TA|VPD|P|SW_IN)_.*_(lag1|lag2)$', names(dt_b2), value=TRUE)
efp_lag_raw <- grep('^(GPPsat|NEPmax|ETmax|uWUE)_lag[12]$', names(dt_b2), value=TRUE)
efp_lag_anom <- grep('^(GPPsat|NEPmax|ETmax|uWUE)_anom_lag[12]$', names(dt_b2), value=TRUE)

cat('Feature inventory:\n')
cat('  Traits (static):', length(trait_cols), 'variables\n')
cat('  Meteorology (current):', length(meteo_cols_cur), 'variables\n')
cat('  Meteorology (lag1+lag2):', length(meteo_cols_lag12), 'variables\n')
cat('  Mortality/deadwood (current):', length(mort_cols_cur), 'variables\n')
cat('  Mortality/deadwood (lag1):', length(mort_cols_lag1), 'variables\n')
cat('  Mortality/deadwood (lag2):', length(mort_cols_lag2), 'variables\n')
cat('  EFP memory (raw, lag1+lag2):', length(efp_lag_raw), 'variables\n')
cat('  EFP memory (anomaly, lag1+lag2):', length(efp_lag_anom), 'variables\n\n')

# Define models (with lag1+lag2)
model_configs_b2 <- list(
  M01 = list(predictors = c(meteo_cols_cur, meteo_cols_lag12),
             description = "Climate: current + lag1+lag2 meteorology (GS-to-GS)"),
  M02 = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, mort_cols_cur, mort_cols_lag1, mort_cols_lag2),
             description = "Climate + Disturbance: meteo + mortality/deadwood current + lag1+lag2"),
  M03 = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, trait_cols),
             description = "Climate + Traits: meteo current + lag1+lag2 + static traits"),
  M04 = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, trait_cols, mort_cols_cur, mort_cols_lag1, mort_cols_lag2),
             description = "Full model: Climate + Traits + Disturbance"),
  M05_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, efp_lag_raw),
             description = "Climate + Memory (raw): meteo + raw EFP lag1+lag2"),
  M05_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, efp_lag_anom),
             description = "Climate + Memory (anomaly): meteo + EFP anomaly lag1+lag2"),
  M06_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, mort_cols_cur, mort_cols_lag1, mort_cols_lag2, efp_lag_raw),
             description = "Climate + Disturbance + Memory (raw)"),
  M06_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, mort_cols_cur, mort_cols_lag1, mort_cols_lag2, efp_lag_anom),
             description = "Climate + Disturbance + Memory (anomaly)"),
  M07_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, trait_cols, efp_lag_raw),
             description = "Climate + Traits + Memory (raw)"),
  M07_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, trait_cols, efp_lag_anom),
             description = "Climate + Traits + Memory (anomaly)"),
  M08_raw = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, trait_cols, mort_cols_cur, mort_cols_lag1, mort_cols_lag2, efp_lag_raw),
             description = "Full + Memory (raw): Climate + Traits + Disturbance + raw EFP memory"),
  M08_anom = list(predictors = c(meteo_cols_cur, meteo_cols_lag12, trait_cols, mort_cols_cur, mort_cols_lag1, mort_cols_lag2, efp_lag_anom),
             description = "Full + Memory (anomaly): Climate + Traits + Disturbance + EFP anomaly")
)

# Create documentation
doc_b2 <- list()
for (model_name in names(model_configs_b2)) {
  config <- model_configs_b2[[model_name]]
  doc_b2[[model_name]] <- data.table(
    Model = model_name,
    Description = config$description,
    N_Predictors = length(config$predictors),
    N_Traits = sum(config$predictors %in% trait_cols),
    N_Meteo_Current = sum(config$predictors %in% meteo_cols_cur),
    N_Meteo_Lag12 = sum(config$predictors %in% meteo_cols_lag12),
    N_Mortality = sum(config$predictors %in% c(mort_cols_cur, mort_cols_lag1, mort_cols_lag2)),
    N_EFP_Memory = sum(config$predictors %in% c(efp_lag_raw, efp_lag_anom)),
    Predictors = paste(config$predictors, collapse = "; ")
  )
}

df_doc_b2 <- rbindlist(doc_b2)

# Save B2 predictor doc
out_dir_b2 <- 'derived_tables/outputs_afterEGU_results/RF_V10_B2_lag1and2'
dir.create(out_dir_b2, recursive=TRUE, showWarnings=FALSE)
out_file_b2 <- file.path(out_dir_b2, 'PREDICTORS.csv')
fwrite(df_doc_b2, out_file_b2)

cat('Saved B2 predictors:', out_file_b2, '\n\n')

# =========================================================
# Summary
# =========================================================

cat('====================================================================\n')
cat('PREDICTOR DOCUMENTATION SUMMARY\n')
cat('====================================================================\n\n')

cat('B1 (Lag1 Only) Models:\n')
print(df_doc_b1[, .(Model, Description, N_Predictors, N_Traits, N_Meteo_Current, N_Meteo_Lag1, N_Mortality, N_EFP_Memory)])

cat('\n\nB2 (Lag1+Lag2) Models:\n')
print(df_doc_b2[, .(Model, Description, N_Predictors, N_Traits, N_Meteo_Current, N_Meteo_Lag12, N_Mortality, N_EFP_Memory)])

cat('\n✅ COMPREHENSIVE PREDICTOR DOCS CREATED!\n')
cat('====================================================================\n\n')

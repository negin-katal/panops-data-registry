#!/usr/bin/env Rscript
# Create meteorological lags based on growing-season-to-growing-season aggregation
# Instead of calendar year lags, aggregate from CGS(Y-1) to CGS(Y) for lag1, etc.

library(data.table)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat('\n====================================================================\n')
cat('METEOROLOGICAL LAG AGGREGATION: GROWING-SEASON-TO-GROWING-SEASON\n')
cat('====================================================================\n\n')

# =========================================================
# PHASE 1: Load CGS dates and monthly meteo
# =========================================================

cat('PHASE 1: Loading CGS dates and monthly meteo...\n')

cgs_data <- fread('derived_tables/outputs_afterEGU_results/center_growing_season/center_growing_season_by_site_year.csv')
setnames(cgs_data, 'year', 'YEAR')

cat('  CGS data:', nrow(cgs_data), 'rows from', uniqueN(cgs_data$SITE_ID), 'sites\n')

# Load all monthly meteo files
meteo_path <- 'fluxnet_2017_2025_V02/EFP_outputs_corrected/monthly_meteo_per_site'
meteo_files <- list.files(meteo_path, pattern='_monthly_meteo.csv$', full.names=TRUE)

cat('  Loading', length(meteo_files), 'meteo files...\n')

meteo_list <- lapply(meteo_files, fread)
meteo_all <- rbindlist(meteo_list)

cat('  Meteo data:', nrow(meteo_all), 'rows from', uniqueN(meteo_all$SITE_ID), 'sites\n')
cat('  Year range:', min(meteo_all$YEAR), '-', max(meteo_all$YEAR), '\n')
cat('  Meteo variables:', length(setdiff(names(meteo_all), c('SITE_ID', 'YEAR', 'MONTH', 'n_obs'))), '\n\n')

# Store meteo variable names (exclude metadata)
meteo_vars <- setdiff(names(meteo_all), c('SITE_ID', 'YEAR', 'MONTH', 'n_obs'))

# =========================================================
# PHASE 2: Aggregate meteo from growing season to growing season
# =========================================================

cat('PHASE 2: Aggregating meteo from growing season to growing season...\n\n')

# =========================================================
# PHASE 3: Create lagged meteo aggregates
# =========================================================

cat('Creating lag1 meteo (CGS(Y-1) to CGS(Y))...\n')

# Prepare for lag1 aggregation
cgs_lags <- copy(cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)])
setnames(cgs_lags, c('SITE_ID', 'YEAR', 'CGS_weighted_doy'),
         c('SITE_ID', 'YEAR_Y', 'CGS_Y'))

# Merge with previous year's CGS
cgs_lags[, YEAR_Y_minus_1 := YEAR_Y - 1]
cgs_prev <- copy(cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)])
setnames(cgs_prev, c('YEAR', 'CGS_weighted_doy'), c('YEAR_Y_minus_1', 'CGS_Y_minus_1'))

cgs_lags <- merge(cgs_lags, cgs_prev,
                  by=c('SITE_ID', 'YEAR_Y_minus_1'), all.x=TRUE)

# Remove rows without previous year data
cgs_lags_valid <- cgs_lags[!is.na(CGS_Y_minus_1)]

cat('  CGS pairs ready:', nrow(cgs_lags_valid), 'rows\n')

# Simplified approach: convert CGS DOY to month range
cgs_lags_valid[, month_y_minus_1 := ceiling(CGS_Y_minus_1 / (365.25/12))]
cgs_lags_valid[, month_y := ceiling(CGS_Y / (365.25/12))]
cgs_lags_valid[, month_y_minus_1 := pmin(pmax(month_y_minus_1, 1L), 12L)]
cgs_lags_valid[, month_y := pmin(pmax(month_y, 1L), 12L)]

# Aggregate meteo for lag1 - simplified: direct month range
lag1_meteo_list <- list()

for (i in 1:nrow(cgs_lags_valid)) {
  site <- cgs_lags_valid[i, SITE_ID]
  year_y_minus_1 <- cgs_lags_valid[i, YEAR_Y_minus_1]
  year_y <- cgs_lags_valid[i, YEAR_Y]
  month_start <- cgs_lags_valid[i, month_y_minus_1]
  month_end <- cgs_lags_valid[i, month_y]

  # Get meteo rows in window
  if (year_y_minus_1 == year_y) {
    # Same year (unlikely)
    if (month_start <= month_end) {
      meteo_window <- meteo_all[SITE_ID == site & YEAR == year_y_minus_1 &
                                MONTH >= month_start & MONTH <= month_end]
    } else {
      meteo_window <- meteo_all[SITE_ID == site & YEAR == year_y_minus_1 &
                                (MONTH >= month_start | MONTH <= month_end)]
    }
  } else {
    # Spans two years
    meteo_y_minus_1 <- meteo_all[SITE_ID == site & YEAR == year_y_minus_1 & MONTH >= month_start]
    meteo_y <- meteo_all[SITE_ID == site & YEAR == year_y & MONTH <= month_end]
    meteo_window <- rbind(meteo_y_minus_1, meteo_y)
  }

  if (nrow(meteo_window) > 0) {
    lag1_agg <- meteo_window[, lapply(.SD, mean, na.rm=TRUE),
                            .SDcols=meteo_vars]
    lag1_agg[, SITE_ID := site]
    lag1_agg[, YEAR := year_y]
    lag1_meteo_list[[i]] <- lag1_agg
  }

  if (i %% 500 == 0) cat(sprintf('  %d/%d sites processed\n', i, nrow(cgs_lags_valid)))
}

lag1_meteo <- rbindlist(lag1_meteo_list, fill=TRUE)
lag1_meteo <- lag1_meteo[, c('SITE_ID', 'YEAR', meteo_vars), with=FALSE]
setnames(lag1_meteo, meteo_vars, paste0(meteo_vars, '_lag1'))

cat('  Lag1 meteo created:', nrow(lag1_meteo), 'rows\n\n')

# Similar process for lag2
cat('Creating lag2 meteo (CGS(Y-2) to CGS(Y-1))...\n')

cgs_lags_2 <- copy(cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)])
setnames(cgs_lags_2, c('SITE_ID', 'YEAR', 'CGS_weighted_doy'),
         c('SITE_ID', 'YEAR_Y', 'CGS_Y'))

cgs_lags_2[, YEAR_Y_minus_1 := YEAR_Y - 1]
cgs_lags_2[, YEAR_Y_minus_2 := YEAR_Y - 2]

cgs_y_minus_1_data <- copy(cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)])
setnames(cgs_y_minus_1_data, c('YEAR', 'CGS_weighted_doy'),
         c('YEAR_Y_minus_1', 'CGS_Y_minus_1'))

cgs_y_minus_2_data <- copy(cgs_data[, .(SITE_ID, YEAR, CGS_weighted_doy)])
setnames(cgs_y_minus_2_data, c('YEAR', 'CGS_weighted_doy'),
         c('YEAR_Y_minus_2', 'CGS_Y_minus_2'))

cgs_lags_2 <- merge(cgs_lags_2, cgs_y_minus_1_data,
                   by=c('SITE_ID', 'YEAR_Y_minus_1'), all.x=TRUE)
cgs_lags_2 <- merge(cgs_lags_2, cgs_y_minus_2_data,
                   by=c('SITE_ID', 'YEAR_Y_minus_2'), all.x=TRUE)

cgs_lags_2_valid <- cgs_lags_2[!is.na(CGS_Y_minus_2) & !is.na(CGS_Y_minus_1)]

cat('  CGS pairs ready (lag2):', nrow(cgs_lags_2_valid), 'rows\n')

cgs_lags_2_valid[, month_y_minus_2 := ceiling(CGS_Y_minus_2 / (365.25/12))]
cgs_lags_2_valid[, month_y_minus_1 := ceiling(CGS_Y_minus_1 / (365.25/12))]
cgs_lags_2_valid[, month_y_minus_2 := pmin(pmax(month_y_minus_2, 1L), 12L)]
cgs_lags_2_valid[, month_y_minus_1 := pmin(pmax(month_y_minus_1, 1L), 12L)]

lag2_meteo_list <- list()

for (i in 1:nrow(cgs_lags_2_valid)) {
  site <- cgs_lags_2_valid[i, SITE_ID]
  year_y_minus_2 <- cgs_lags_2_valid[i, YEAR_Y_minus_2]
  year_y_minus_1 <- cgs_lags_2_valid[i, YEAR_Y_minus_1]
  year_y <- cgs_lags_2_valid[i, YEAR_Y]
  month_start <- cgs_lags_2_valid[i, month_y_minus_2]
  month_end <- cgs_lags_2_valid[i, month_y_minus_1]

  if (year_y_minus_2 == year_y_minus_1) {
    # Same year
    if (month_start <= month_end) {
      meteo_window <- meteo_all[SITE_ID == site & YEAR == year_y_minus_2 &
                                MONTH >= month_start & MONTH <= month_end]
    } else {
      meteo_window <- meteo_all[SITE_ID == site & YEAR == year_y_minus_2 &
                                (MONTH >= month_start | MONTH <= month_end)]
    }
  } else {
    meteo_y_minus_2 <- meteo_all[SITE_ID == site & YEAR == year_y_minus_2 & MONTH >= month_start]
    meteo_y_minus_1 <- meteo_all[SITE_ID == site & YEAR == year_y_minus_1 & MONTH <= month_end]
    meteo_window <- rbind(meteo_y_minus_2, meteo_y_minus_1)
  }

  if (nrow(meteo_window) > 0) {
    lag2_agg <- meteo_window[, lapply(.SD, mean, na.rm=TRUE),
                            .SDcols=meteo_vars]
    lag2_agg[, SITE_ID := site]
    lag2_agg[, YEAR := year_y]
    lag2_meteo_list[[i]] <- lag2_agg
  }

  if (i %% 500 == 0) cat(sprintf('  %d/%d sites processed\n', i, nrow(cgs_lags_2_valid)))
}

lag2_meteo <- rbindlist(lag2_meteo_list, fill=TRUE)
lag2_meteo <- lag2_meteo[, c('SITE_ID', 'YEAR', meteo_vars), with=FALSE]
setnames(lag2_meteo, meteo_vars, paste0(meteo_vars, '_lag2'))

cat('  Lag2 meteo created:', nrow(lag2_meteo), 'rows\n\n')

# =========================================================
# PHASE 4: Create current year (lag0) meteo using CGS window
# =========================================================

cat('Creating current year meteo (CGS(Y-1) to CGS(Y) window)...\n')

# Use same window as lag1 for consistency
cgs_lag0 <- copy(cgs_lags_valid[, .(SITE_ID, YEAR_Y, YEAR_Y_minus_1, month_y_minus_1, month_y)])
setnames(cgs_lag0, c('YEAR_Y', 'YEAR_Y_minus_1', 'month_y_minus_1', 'month_y'),
         c('YEAR', 'YEAR_MINUS_1', 'month_start', 'month_end'))

lag0_meteo_list <- list()

for (i in 1:nrow(cgs_lag0)) {
  site <- cgs_lag0[i, SITE_ID]
  year_minus_1 <- cgs_lag0[i, YEAR_MINUS_1]
  year <- cgs_lag0[i, YEAR]
  month_start <- cgs_lag0[i, month_start]
  month_end <- cgs_lag0[i, month_end]

  if (year_minus_1 == year) {
    if (month_start <= month_end) {
      meteo_window <- meteo_all[SITE_ID == site & YEAR == year_minus_1 &
                                MONTH >= month_start & MONTH <= month_end]
    } else {
      meteo_window <- meteo_all[SITE_ID == site & YEAR == year_minus_1 &
                                (MONTH >= month_start | MONTH <= month_end)]
    }
  } else {
    meteo_y_minus_1 <- meteo_all[SITE_ID == site & YEAR == year_minus_1 & MONTH >= month_start]
    meteo_y <- meteo_all[SITE_ID == site & YEAR == year & MONTH <= month_end]
    meteo_window <- rbind(meteo_y_minus_1, meteo_y)
  }

  if (nrow(meteo_window) > 0) {
    lag0_agg <- meteo_window[, lapply(.SD, mean, na.rm=TRUE),
                            .SDcols=meteo_vars]
    lag0_agg[, SITE_ID := site]
    lag0_agg[, YEAR := year]
    lag0_meteo_list[[i]] <- lag0_agg
  }

  if (i %% 500 == 0) cat(sprintf('  %d/%d sites processed\n', i, nrow(cgs_lag0)))
}

lag0_meteo <- rbindlist(lag0_meteo_list, fill=TRUE)
lag0_meteo <- lag0_meteo[, c('SITE_ID', 'YEAR', meteo_vars), with=FALSE]

cat('  Lag0 (current) meteo created:', nrow(lag0_meteo), 'rows\n\n')

# =========================================================
# PHASE 5: Save outputs
# =========================================================

cat('PHASE 5: Saving GS-to-GS meteo lags...\n')

out_dir <- 'derived_tables/outputs_afterEGU_results/GS_to_GS_meteo_lags'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

fwrite(lag0_meteo, file.path(out_dir, 'meteo_lag0_gs_centered.csv'))
fwrite(lag1_meteo, file.path(out_dir, 'meteo_lag1_gs_to_gs.csv'))
fwrite(lag2_meteo, file.path(out_dir, 'meteo_lag2_gs_to_gs.csv'))

cat('  Lag0:', nrow(lag0_meteo), 'rows\n')
cat('  Lag1:', nrow(lag1_meteo), 'rows\n')
cat('  Lag2:', nrow(lag2_meteo), 'rows\n\n')

cat('✅ GS-TO-GS METEO LAGS COMPLETE!\n')
cat('====================================================================\n\n')

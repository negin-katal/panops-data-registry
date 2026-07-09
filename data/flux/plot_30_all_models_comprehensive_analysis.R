library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

cat("Loading data...\n")

main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")
preds <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv")
shap_m04_m08 <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv")
shap_m06 <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06.csv")
shap_m06_12m <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06_12m.csv")

# Combine M06 SHAP
shap_m06[, group := ifelse(group == "Meteo", "Memory", group)]
shap_m06_12m[, group := ifelse(group == "Meteo", "Memory", group)]
shap_m06_all <- rbindlist(list(shap_m06, shap_m06_12m), fill = TRUE)

# Combine all SHAP
shap_all <- rbindlist(list(shap_m04_m08, shap_m06_all), fill = TRUE)

# Reclassify variables: separate EFP memory from Climate
shap_all[, group := fcase(
  variable %in% c("ETmax_anom_lag1", "ETmax_anom_lag2",
                  "GPPsat_anom_lag1", "GPPsat_anom_lag2",
                  "NEPmax_anom_lag1", "NEPmax_anom_lag2",
                  "uWUE_anom_lag1", "uWUE_anom_lag2"),
  "Memory",
  grepl("^(TA|P|VPD|SW_IN).*_anom_lag", variable), "Climate",
  default = group
)]

# Calculate site-level disturbance metrics and tree cover
site_metrics <- main_data[, .(
  abs_mort = mean(deadwood_mean_pct_500m, na.rm = TRUE),
  rel_mort = mean((deadwood_mean_pct_500m / forest_mean_pct_500m * 100), na.rm = TRUE),
  rel_dist = mean(((deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
                    (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100), na.rm = TRUE),
  tree_cover = mean(forest_mean_pct_500m, na.rm = TRUE)
), by = SITE_ID]

# Create categorical tiers
site_metrics[, abs_mort_tier := fcase(
  abs_mort < 10,  "< 10%",
  abs_mort < 20,  "10-20%",
  default =       "> 20%"
)]

site_metrics[, rel_mort_tier := fcase(
  rel_mort < 40,  "< 40%",
  rel_mort < 60,  "40-60%",
  default =       "> 60%"
)]

site_metrics[, rel_dist_tier := fcase(
  rel_dist < 10,  "< 10",
  rel_dist < 40,  "10-40",
  default =       "> 40%"
)]

site_metrics[, tree_cover_tier := fcase(
  tree_cover < 30,  "< 30%",
  tree_cover < 60,  "30-60%",
  default =         "> 60%"
)]

site_metrics[, abs_mort_tier := factor(abs_mort_tier, levels = c("< 10%", "10-20%", "> 20%"))]
site_metrics[, rel_mort_tier := factor(rel_mort_tier, levels = c("< 40%", "40-60%", "> 60%"))]
site_metrics[, rel_dist_tier := factor(rel_dist_tier, levels = c("< 10", "10-40", "> 40%"))]
site_metrics[, tree_cover_tier := factor(tree_cover_tier, levels = c("< 30%", "30-60%", "> 60%"))]

# Process predictions
preds[, model_key := sub("_(12m|24m)_.*", "", model)]
preds[, window := regmatches(model, regexpr("(12m|24m)", model))]
preds[, response := sub(".*_(12m|24m)_", "", model)]

site_rmse <- preds[, .(
  rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))
), by = .(model_key, window, response, SITE_ID)]

# Calculate delta RMSE for all comparison pairs
delta_data_list <- list()

for(w in c("12m", "24m")) {
  for(r in c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")) {
    # M01 vs M02
    m01 <- site_rmse[model_key == "M01" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    m02 <- site_rmse[model_key == "M02" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    if(nrow(m01) > 0 & nrow(m02) > 0) {
      merged <- merge(m01, m02, by = "SITE_ID", suffixes = c("_base", "_dist"))
      delta_data_list[[length(delta_data_list) + 1]] <- merged[
        , .(SITE_ID, window = w, response = r, model_pair = "M01_vs_M02", delta_rmse = rmse_dist - rmse_base)]
    }

    # M03 vs M04
    m03 <- site_rmse[model_key == "M03" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    m04 <- site_rmse[model_key == "M04" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    if(nrow(m03) > 0 & nrow(m04) > 0) {
      merged <- merge(m03, m04, by = "SITE_ID", suffixes = c("_base", "_dist"))
      delta_data_list[[length(delta_data_list) + 1]] <- merged[
        , .(SITE_ID, window = w, response = r, model_pair = "M03_vs_M04", delta_rmse = rmse_dist - rmse_base)]
    }

    # M05 vs M06
    m05 <- site_rmse[model_key == "M05" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    m06 <- site_rmse[model_key == "M06" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    if(nrow(m05) > 0 & nrow(m06) > 0) {
      merged <- merge(m05, m06, by = "SITE_ID", suffixes = c("_base", "_dist"))
      delta_data_list[[length(delta_data_list) + 1]] <- merged[
        , .(SITE_ID, window = w, response = r, model_pair = "M05_vs_M06", delta_rmse = rmse_dist - rmse_base)]
    }

    # M07 vs M08
    m07 <- site_rmse[model_key == "M07" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    m08 <- site_rmse[model_key == "M08" & window == w & response == r, .(SITE_ID, rmse = rmse)]
    if(nrow(m07) > 0 & nrow(m08) > 0) {
      merged <- merge(m07, m08, by = "SITE_ID", suffixes = c("_base", "_dist"))
      delta_data_list[[length(delta_data_list) + 1]] <- merged[
        , .(SITE_ID, window = w, response = r, model_pair = "M07_vs_M08", delta_rmse = rmse_dist - rmse_base)]
    }
  }
}

delta_rmse <- rbindlist(delta_data_list)
delta_rmse <- merge(delta_rmse, site_metrics, by = "SITE_ID")

# Process SHAP for disturbance contribution
shap_grp <- shap_all[group %in% c("Climate", "Traits", "Disturbance", "Memory"),
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]

site_tot <- shap_grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
shap_grp <- merge(shap_grp, site_tot, by = c("model", "response", "test_site"))
shap_grp[, rel_shap := grp_shap / total]
shap_grp <- merge(shap_grp, site_metrics, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

# Extract disturbance SHAP
shap_dist <- shap_grp[group == "Disturbance"]
shap_dist[, model_key := sub("_(12m|24m)_.*", "", model)]
shap_dist[, window := regmatches(model, regexpr("(12m|24m)", model))]

# ============================================================
# Color schemes
# ============================================================
DARK_BG <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

abs_mort_cols <- c("< 10%" = "#4DAECC", "10-20%" = "#F0A500", "> 20%" = "#E8257A")
rel_mort_cols <- c("< 40%" = "#4DAECC", "40-60%" = "#F0A500", "> 60%" = "#E8257A")
rel_dist_cols <- c("< 10" = "#4DAECC", "10-40" = "#F0A500", "> 40%" = "#E8257A")
tree_cover_cols <- c("< 30%" = "#66C2A5", "30-60%" = "#FC8D62", "> 60%" = "#8DA0CB")

dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background = element_rect(fill = DARK_BG, colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text = element_text(colour = TEXT_COL, size = 8, face = "bold"),
    axis.text = element_text(colour = AXIS_COL, size = 7.5),
    axis.title = element_text(colour = AXIS_COL, size = 8.5),
    plot.tag = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.title = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    legend.position = "none"
  )

# ============================================================
# Generate plots for each model (all windows and pairs)
# ============================================================

model_info <- data.table(
  mod = c("M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08"),
  pair = c("M01_vs_M02", "M01_vs_M02", "M03_vs_M04", "M03_vs_M04",
           "M05_vs_M06", "M05_vs_M06", "M07_vs_M08", "M07_vs_M08"),
  has_shap = c(FALSE, FALSE, FALSE, TRUE, FALSE, TRUE, FALSE, TRUE)
)

for(i in 1:nrow(model_info)) {
  mod <- model_info$mod[i]
  pair <- model_info$pair[i]
  has_shap <- model_info$has_shap[i]

  cat("\n=== Processing", mod, "(pair:", pair, ", SHAP:", has_shap, ") ===\n")

  out_dir <- sprintf("plots/manuscript_candidates/%s", mod)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Get data for this model
  delta_sub <- delta_rmse[model_pair == pair]

  if(nrow(delta_sub) == 0) {
    cat("  Skipping - no delta RMSE data\n")
    next
  }

  shap_sub <- NULL
  if(has_shap) {
    shap_sub <- shap_dist[model_key == mod]
    if(nrow(shap_sub) == 0) {
      has_shap <- FALSE
      cat("  No SHAP data found\n")
    }
  }

  # Generate plots for each window
  for(w in c("12m", "24m")) {
    delta_w <- delta_sub[window == w]
    if(nrow(delta_w) == 0) next

    shap_w <- NULL
    if(has_shap) {
      shap_w <- shap_sub[window == w]
      if(nrow(shap_w) == 0) shap_w <- NULL
    }

    # ---- Plot 1: Delta RMSE vs Absolute Mortality ----
    p1 <- ggplot(delta_w[!is.na(abs_mort_tier)],
                 aes(x = abs_mort_tier, y = delta_rmse, fill = abs_mort_tier)) +
      geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
      geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
      geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
      stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
      scale_fill_manual(values = abs_mort_cols) +
      facet_wrap(~response, scales = "free_y") +
      labs(title = paste("Delta RMSE vs Absolute Mortality -", w),
           x = "Absolute Mortality (%)", y = expression(Delta*"RMSE")) +
      dark_theme

    ggsave(file.path(out_dir, sprintf("01_delta_RMSE_vs_abs_mortality_%s.png", w)), p1,
           width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
    ggsave(file.path(out_dir, sprintf("01_delta_RMSE_vs_abs_mortality_%s.pdf", w)), p1,
           width = 200, height = 150, units = "mm", bg = DARK_BG)

    # ---- Plot 2: Delta RMSE vs Relative Mortality ----
    p2 <- ggplot(delta_w[!is.na(rel_mort_tier)],
                 aes(x = rel_mort_tier, y = delta_rmse, fill = rel_mort_tier)) +
      geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
      geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
      geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
      stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
      scale_fill_manual(values = rel_mort_cols) +
      facet_wrap(~response, scales = "free_y") +
      labs(title = paste("Delta RMSE vs Relative Mortality -", w),
           x = "Relative Mortality (%)", y = expression(Delta*"RMSE")) +
      dark_theme

    ggsave(file.path(out_dir, sprintf("02_delta_RMSE_vs_rel_mortality_%s.png", w)), p2,
           width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
    ggsave(file.path(out_dir, sprintf("02_delta_RMSE_vs_rel_mortality_%s.pdf", w)), p2,
           width = 200, height = 150, units = "mm", bg = DARK_BG)

    # ---- Plot 3: Delta RMSE vs Relative Disturbance ----
    p3 <- ggplot(delta_w[!is.na(rel_dist_tier)],
                 aes(x = rel_dist_tier, y = delta_rmse, fill = rel_dist_tier)) +
      geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
      geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
      geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
      stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
      scale_fill_manual(values = rel_dist_cols) +
      facet_wrap(~response, scales = "free_y") +
      labs(title = paste("Delta RMSE vs Relative Disturbance -", w),
           x = "Relative Disturbance (%)", y = expression(Delta*"RMSE")) +
      dark_theme

    ggsave(file.path(out_dir, sprintf("03_delta_RMSE_vs_rel_disturbance_%s.png", w)), p3,
           width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
    ggsave(file.path(out_dir, sprintf("03_delta_RMSE_vs_rel_disturbance_%s.pdf", w)), p3,
           width = 200, height = 150, units = "mm", bg = DARK_BG)

    # ---- Plot 4: Delta RMSE vs Tree Cover ----
    p4 <- ggplot(delta_w[!is.na(tree_cover_tier)],
                 aes(x = tree_cover_tier, y = delta_rmse, fill = tree_cover_tier)) +
      geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
      geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
      geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
      stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
      scale_fill_manual(values = tree_cover_cols) +
      facet_wrap(~response, scales = "free_y") +
      labs(title = paste("Delta RMSE vs Tree Cover -", w),
           x = "Tree Cover (%)", y = expression(Delta*"RMSE")) +
      dark_theme

    ggsave(file.path(out_dir, sprintf("04_delta_RMSE_vs_tree_cover_%s.png", w)), p4,
           width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
    ggsave(file.path(out_dir, sprintf("04_delta_RMSE_vs_tree_cover_%s.pdf", w)), p4,
           width = 200, height = 150, units = "mm", bg = DARK_BG)

    cat("  ✓ Delta RMSE plots for", w, "\n")

    # SHAP plots (only if available)
    if(!is.null(shap_w) && nrow(shap_w) > 0) {
      # ---- Plot 5: Disturbance SHAP vs Absolute Mortality ----
      p5 <- ggplot(shap_w[!is.na(abs_mort_tier)],
                   aes(x = abs_mort_tier, y = grp_shap, fill = abs_mort_tier)) +
        geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
        geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
        stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
        scale_fill_manual(values = abs_mort_cols) +
        facet_wrap(~response, scales = "free_y") +
        labs(title = paste("Disturbance SHAP vs Absolute Mortality -", w),
             x = "Absolute Mortality (%)", y = "Mean |SHAP|") +
        dark_theme

      ggsave(file.path(out_dir, sprintf("05_SHAP_disturbance_vs_abs_mortality_%s.png", w)), p5,
             width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
      ggsave(file.path(out_dir, sprintf("05_SHAP_disturbance_vs_abs_mortality_%s.pdf", w)), p5,
             width = 200, height = 150, units = "mm", bg = DARK_BG)

      # ---- Plot 6: Disturbance SHAP vs Relative Mortality ----
      p6 <- ggplot(shap_w[!is.na(rel_mort_tier)],
                   aes(x = rel_mort_tier, y = grp_shap, fill = rel_mort_tier)) +
        geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
        geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
        stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
        scale_fill_manual(values = rel_mort_cols) +
        facet_wrap(~response, scales = "free_y") +
        labs(title = paste("Disturbance SHAP vs Relative Mortality -", w),
             x = "Relative Mortality (%)", y = "Mean |SHAP|") +
        dark_theme

      ggsave(file.path(out_dir, sprintf("06_SHAP_disturbance_vs_rel_mortality_%s.png", w)), p6,
             width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
      ggsave(file.path(out_dir, sprintf("06_SHAP_disturbance_vs_rel_mortality_%s.pdf", w)), p6,
             width = 200, height = 150, units = "mm", bg = DARK_BG)

      # ---- Plot 7: Disturbance SHAP vs Relative Disturbance ----
      p7 <- ggplot(shap_w[!is.na(rel_dist_tier)],
                   aes(x = rel_dist_tier, y = grp_shap, fill = rel_dist_tier)) +
        geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
        geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
        stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
        scale_fill_manual(values = rel_dist_cols) +
        facet_wrap(~response, scales = "free_y") +
        labs(title = paste("Disturbance SHAP vs Relative Disturbance -", w),
             x = "Relative Disturbance (%)", y = "Mean |SHAP|") +
        dark_theme

      ggsave(file.path(out_dir, sprintf("07_SHAP_disturbance_vs_rel_disturbance_%s.png", w)), p7,
             width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
      ggsave(file.path(out_dir, sprintf("07_SHAP_disturbance_vs_rel_disturbance_%s.pdf", w)), p7,
             width = 200, height = 150, units = "mm", bg = DARK_BG)

      # ---- Plot 8: Disturbance SHAP vs Tree Cover ----
      p8 <- ggplot(shap_w[!is.na(tree_cover_tier)],
                   aes(x = tree_cover_tier, y = grp_shap, fill = tree_cover_tier)) +
        geom_boxplot(outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
        geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = AXIS_COL) +
        stat_summary(fun = mean, geom = "point", colour = "white", size = 2) +
        scale_fill_manual(values = tree_cover_cols) +
        facet_wrap(~response, scales = "free_y") +
        labs(title = paste("Disturbance SHAP vs Tree Cover -", w),
             x = "Tree Cover (%)", y = "Mean |SHAP|") +
        dark_theme

      ggsave(file.path(out_dir, sprintf("08_SHAP_disturbance_vs_tree_cover_%s.png", w)), p8,
             width = 200, height = 150, units = "mm", dpi = 300, bg = DARK_BG)
      ggsave(file.path(out_dir, sprintf("08_SHAP_disturbance_vs_tree_cover_%s.pdf", w)), p8,
             width = 200, height = 150, units = "mm", bg = DARK_BG)

      cat("  ✓ SHAP plots for", w, "\n")
    }
  }
}

cat("\n=== ALL PLOTS COMPLETE ===\n")

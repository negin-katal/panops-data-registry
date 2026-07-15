library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir   <- "plots/site_shap_disturbance_metrics"
shap_m06  <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06.csv"
shap_m08  <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv"
mod_file  <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv"

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Colours
COL_CLIMATE     <- "#4A90D9"
COL_TRAITS      <- "#3DBDAA"
COL_DISTURBANCE <- "#D4A017"

GROUP_COLOURS   <- c(Climate = COL_CLIMATE, Traits = COL_TRAITS,
                     Disturbance = COL_DISTURBANCE, Memory = "#999999")
GROUP_LEVELS    <- c("Climate","Traits","Disturbance","Memory")

EFP_UNITS <- c(
  GPPsat = "GPPsat  (µmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)",
  WUE    = "WUE  (g C mm⁻¹)"
)

# Disturbance metrics config
DIST_META <- list(
  abs_mort = list(
    col = "abs_mort",
    label = "Absolute Mortality (%)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
    mid_v = 20
  ),
  rel_mort = list(
    col = "rel_mort",
    label = "Relative Mortality (%)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
    mid_v = 40
  ),
  rel_dist = list(
    col = "rel_dist",
    label = "Relative Disturbance (%)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
    mid_v = 20
  )
)

# ── Load SHAP data ────────────────────────────────────────────
cat("Loading M06 SHAP...\n")
shap_m06_data <- fread(shap_m06)
cat("M06 rows:", nrow(shap_m06_data), "\n")

cat("Loading M08 SHAP...\n")
shap_m08_data <- fread(shap_m08)[grepl("^M08_24m_", model)]
cat("M08 rows:", nrow(shap_m08_data), "\n")

# Combine and process SHAP
shap_raw <- rbindlist(list(shap_m06_data, shap_m08_data), fill = TRUE)

shap_grp <- shap_raw[group %in% GROUP_LEVELS,
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]

site_tot <- shap_grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
shap_grp <- merge(shap_grp, site_tot, by = c("model","response","test_site"))
shap_grp[, rel_shap := grp_shap / total]

full_key <- CJ(model     = unique(shap_grp$model),
               response  = unique(shap_grp$response),
               test_site = unique(shap_grp$test_site),
               group     = GROUP_LEVELS)
shap_grp <- merge(full_key, shap_grp[, .(model, response, test_site, group, rel_shap, grp_shap)],
                  by = c("model","response","test_site","group"), all.x = TRUE)
shap_grp[is.na(rel_shap), rel_shap := 0]
shap_grp[is.na(grp_shap), grp_shap := 0]
shap_grp[, group := factor(group, levels = GROUP_LEVELS)]

# ── Load disturbance metrics ──────────────────────────────────
cat("Loading site disturbance metrics...\n")
dt_raw <- fread(mod_file,
                select = c("SITE_ID","YEAR",
                           "deadwood_mean_pct_500m",
                           "forest_mean_pct_500m",
                           "loss_area_frac_500m"))

site_dist <- dt_raw[,
  .(
    abs_mort = max(deadwood_mean_pct_500m, na.rm = TRUE),
    rel_mort = max(
      ifelse(forest_mean_pct_500m > 0,
             deadwood_mean_pct_500m / forest_mean_pct_500m * 100, NA_real_),
      na.rm = TRUE),
    rel_dist = max(
      ifelse((forest_mean_pct_500m + loss_area_frac_500m * 100) > 0,
             (deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
             (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100, NA_real_),
      na.rm = TRUE)
  ), by = SITE_ID]

# ── Merge SHAP + disturbance metrics ───────────────────────────
shap_grp <- merge(shap_grp, site_dist, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

# ── Process each model+EFP+window combination ──────────────────
unique_combos <- unique(shap_grp[, .(model, response)])

for (i in seq_len(nrow(unique_combos))) {
  mod <- unique_combos$model[i]
  efp <- unique_combos$response[i]

  cat("\nProcessing:", mod, "-", efp, "\n")

  data <- shap_grp[model == mod & response == efp]

  # Extract window and memory type
  window <- ifelse(grepl("24m", mod), "24m", "12m")

  # Create one plot per disturbance metric
  for (metric_name in names(DIST_META)) {
    metric_info <- DIST_META[[metric_name]]

    # Sort by metric for better visualization
    data_sorted <- data[order(get(metric_info$col))]
    data_sorted[, site_ord := 1:.N]

    p <- ggplot(data_sorted, aes(x = site_ord, fill = group, y = rel_shap)) +
      geom_col(colour = NA, alpha = 0.9) +
      geom_point(aes(colour = get(metric_info$col)), size = 1.5, position = position_stack(vjust = 0.5), alpha = 0.8) +
      scale_fill_manual(values = GROUP_COLOURS, name = NULL) +
      scale_colour_gradient2(
        low = metric_info$low,
        mid = metric_info$mid,
        high = metric_info$high,
        midpoint = metric_info$mid_v,
        name = metric_info$label,
        guide = guide_colourbar(barheight = unit(3, "cm"), title.position = "top")
      ) +
      labs(
        title = paste(mod, "-", efp, window, "-", metric_info$label),
        x = "Site (sorted by metric)",
        y = "SHAP contribution (fraction)"
      ) +
      theme_minimal() +
      theme(
        axis.text.x = element_blank(),
        legend.position = "right",
        plot.title = element_text(size = 10, face = "bold")
      )

    # Save
    stem <- sprintf("%s/site_shap_%s_%s_%s_distmetrics", out_dir, mod, efp, window)
    ggsave(paste0(stem, ".png"), p, width = 280, height = 100, units = "mm", dpi = 300)
    ggsave(paste0(stem, ".pdf"), p, width = 280, height = 100, units = "mm")

    cat("  ✓", metric_name, "\n")
  }
}

cat("\n=== All plots saved to", out_dir, "===\n")

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir   <- "plots/site_shap_disturbance_metrics"
shap_m06  <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06.csv"
shap_m08_file  <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv"
mod_file  <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv"

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Colours
COL_CLIMATE     <- "#4A90D9"
COL_TRAITS      <- "#3DBDAA"
COL_DISTURBANCE <- "#D4A017"
COL_MEMORY      <- "#E74C3C"

GROUP_COLOURS   <- c(Climate = COL_CLIMATE, Traits = COL_TRAITS,
                     Disturbance = COL_DISTURBANCE, Memory = COL_MEMORY)
GROUP_LEVELS    <- c("Climate","Traits","Disturbance","Memory")

EFP_UNITS <- c(
  GPPsat = "GPPsat  (µmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)",
  WUE    = "WUE  (g C mm⁻¹)"
)

DIST_META <- list(
  abs_mort = list(
    col = "abs_mort",
    label = "Absolute Mortality\n(deadwood 500m, %)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
    mid_v = 20
  ),
  rel_mort = list(
    col = "rel_mort",
    label = "Relative Mortality\n(deadwood / forest × 100, %)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
    mid_v = 40
  ),
  rel_dist = list(
    col = "rel_dist",
    label = "Relative Disturbance\n((deadwood + loss×100) / (forest + loss×100), %)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
    mid_v = 20
  )
)

# Load SHAP data
cat("Loading M06 SHAP (24m and 12m)...\n")
shap_m06_24m <- fread(shap_m06)
# M06 12m file (if it exists)
shap_m06_12m_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06_12m.csv"
if (file.exists(shap_m06_12m_file)) {
  shap_m06_12m <- fread(shap_m06_12m_file)
  shap_m06_data <- rbindlist(list(shap_m06_24m, shap_m06_12m), fill = TRUE)
  cat("  Loaded both 24m and 12m\n")
} else {
  shap_m06_data <- shap_m06_24m
  cat("  Loaded only 24m (12m not yet computed)\n")
}

# Fix M06 group names: "Meteo" → "Memory"
shap_m06_data[, group := ifelse(group == "Meteo", "Memory", group)]

cat("Loading M08 SHAP from anomaly (same memory type as M06)...\n")
shap_m08_file_anomaly <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv"
shap_m08_data <- fread(shap_m08_file_anomaly)[grepl("^M08_(12m|24m)_", model)]

shap_raw <- rbindlist(list(shap_m06_data, shap_m08_data), fill = TRUE)

# Reclassify variables: separate EFP memory from Climate
# EFP memory variables (autoregressive): ETmax, GPPsat, NEPmax, uWUE anomaly lags
# Climate variables: TA, P, VPD, SW_IN anomaly lags
shap_raw[, group := fcase(
  variable %in% c("ETmax_anom_lag1", "ETmax_anom_lag2",
                  "GPPsat_anom_lag1", "GPPsat_anom_lag2",
                  "NEPmax_anom_lag1", "NEPmax_anom_lag2",
                  "uWUE_anom_lag1", "uWUE_anom_lag2"),
  "Memory",
  grepl("^(TA|P|VPD|SW_IN).*_anom_lag", variable), "Climate",
  default = group
)]

# Identify sites with data in both models before aggregation
m06_raw_sites <- unique(shap_m06_data$test_site)
m08_raw_sites <- unique(shap_m08_data$test_site)
common_sites_pre <- intersect(m06_raw_sites, m08_raw_sites)
cat("Sites with M06 data:", length(m06_raw_sites), "\n")
cat("Sites with M08 data:", length(m08_raw_sites), "\n")
cat("Common sites:", length(common_sites_pre), "\n")

# Filter to common sites only
shap_raw <- shap_raw[test_site %in% common_sites_pre]

# Process SHAP
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

# Load disturbance metrics
cat("Loading site disturbance metrics...\n")
dt_raw <- fread(mod_file, select = c("SITE_ID","YEAR",
                           "deadwood_mean_pct_500m",
                           "forest_mean_pct_500m",
                           "loss_area_frac_500m"))

site_dist <- dt_raw[,
  .(
    abs_mort = max(deadwood_mean_pct_500m, na.rm = TRUE),
    rel_mort = max(ifelse(forest_mean_pct_500m > 0,
             deadwood_mean_pct_500m / forest_mean_pct_500m * 100, NA_real_),
      na.rm = TRUE),
    rel_dist = max(ifelse((forest_mean_pct_500m + loss_area_frac_500m * 100) > 0,
             (deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
             (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100, NA_real_),
      na.rm = TRUE)
  ), by = SITE_ID]

site_dist[abs_mort == -Inf, abs_mort := NA]
site_dist[rel_mort == -Inf, rel_mort := NA]
site_dist[rel_dist == -Inf, rel_dist := NA]

shap_grp <- merge(shap_grp, site_dist, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

# Plot factory
make_one_panel <- function(dt_sub, site_order, metric_key, show_y = TRUE) {
  meta    <- DIST_META[[metric_key]]
  col_var <- meta$col

  dt_plot <- copy(dt_sub)
  dt_plot[, test_site := factor(test_site, levels = site_order)]

  dot_dt  <- unique(dt_plot[, c("test_site", col_var), with = FALSE])
  dot_dt[, test_site := factor(test_site, levels = site_order)]
  setnames(dot_dt, col_var, "metric_val")

  max_val <- ceiling(max(dot_dt$metric_val, na.rm = TRUE) / 5) * 5
  max_val <- max(max_val, meta$mid_v * 2)

  p <- ggplot() +
    geom_col(data = dt_plot,
             aes(x = rel_shap, y = test_site, fill = group),
             position = "stack", width = 0.75) +
    geom_point(data = dot_dt,
               aes(x = -0.05, y = test_site, colour = metric_val, size = metric_val)) +
    scale_fill_manual(values = GROUP_COLOURS, name = "Driver group") +
    scale_colour_gradient2(
      low = meta$low, mid = meta$mid, high = meta$high,
      midpoint = meta$mid_v,
      limits = c(0, max_val),
      na.value = "grey80",
      name = meta$label
    ) +
    scale_size_continuous(
      name = meta$label,
      range = c(0.5, 4.5),
      limits = c(0, max_val)
    ) +
    scale_x_continuous(
      limits = c(-0.09, 1.02),
      breaks = seq(0, 1, 0.25),
      labels = c("0","0.25","0.50","0.75","1.00"),
      expand = expansion(0)
    ) +
    labs(x = "Relative mean |SHAP|", y = NULL) +
    theme_bw(base_size = 9) +
    theme(
      axis.text.y = if (show_y) element_text(size = 6.5) else element_blank(),
      axis.ticks.y = if (show_y) element_line() else element_blank(),
      legend.position = "right",
      legend.key.size = unit(0.4, "cm"),
      legend.title = element_text(size = 7.5),
      legend.text = element_text(size = 7),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank()
    ) +
    guides(
      fill = guide_legend(order = 1, override.aes = list(size = 3.5)),
      colour = guide_colourbar(order = 2, barheight = unit(2.5, "cm")),
      size = "none"
    )

  p
}

make_combined_plot <- function(dt_sub, resp_label, mod_key, win) {
  site_order <- dt_sub[group == "Disturbance",
                       .(dist_share = mean(rel_shap)), by = test_site
                       ][order(-dist_share), test_site]

  panels <- lapply(seq_along(DIST_META), function(i) {
    mk <- names(DIST_META)[i]
    make_one_panel(dt_sub, site_order, mk, show_y = (i == 1))
  })

  title_str <- sprintf("%s  |  %s  |  %s window", mod_key, resp_label, win)

  combined <- (panels[[1]] | panels[[2]] | panels[[3]]) +
    plot_annotation(
      title = title_str,
      theme = theme(plot.title = element_text(face = "bold", size = 10, hjust = 0.5))
    ) +
    plot_layout(guides = "collect") &
    theme(legend.position = "right")

  combined
}

# Generate plots for M06 and M08
for (mod_key in c("M06", "M08")) {
  cat("\n=== Generating", mod_key, "plots ===\n")

  efps    <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")
  windows <- c("12m", "24m")  # Both 12m and 24m

  for (win in windows) {
    for (resp in efps) {
      mod_pattern <- paste0("^", mod_key, "_", win, "_", resp, "$")
      dt_sub <- shap_grp[grepl(mod_pattern, model) & response == resp]
      if (nrow(dt_sub) == 0) {
        cat("  No data:", resp, win, "\n")
        next
      }

      p <- make_combined_plot(dt_sub, EFP_UNITS[resp], mod_key, win)

      n_sites <- uniqueN(dt_sub$test_site)
      h <- max(6, n_sites * 0.17 + 2)

      stem <- file.path(out_dir, paste0("site_shap_", mod_key, "_", resp, "_", win, "_distmetrics"))
      ggsave(paste0(stem, ".png"), p, width = 20, height = h, dpi = 150, limitsize = FALSE)
      ggsave(paste0(stem, ".pdf"), p, width = 20, height = h, limitsize = FALSE)
      cat("  ✓ Saved:", resp, win, "(", n_sites, "sites)\n")
    }
  }
}

cat("\n=== DONE ===\n")
cat("Outputs in:", out_dir, "\n")

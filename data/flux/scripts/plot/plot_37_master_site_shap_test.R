#!/usr/bin/env Rscript
# Master script for site SHAP stacked bar plots (plot_29 style)

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

METHODS <- c("tertiles_method", "equal_width_method", "natural_breaks_method")
OUT_BASE <- "plots/disturbance_metric_test"

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

COL_CLIMATE     <- "#4A90D9"
COL_TRAITS      <- "#3DBDAA"
COL_DISTURBANCE <- "#D4A017"
COL_MEMORY      <- "#E74C3C"

GROUP_COLOURS   <- c(Climate = COL_CLIMATE, Traits = COL_TRAITS,
                     Disturbance = COL_DISTURBANCE, Memory = COL_MEMORY)
GROUP_LEVELS    <- c("Climate", "Traits", "Disturbance", "Memory")

EFP_UNITS <- c(
  GPPsat = "GPPsat  (µmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)",
  WUE    = "WUE  (g C mm⁻¹)"
)

DIST_META <- list(
  abs_mort_cat = list(
    label = "Absolute Mortality (deadwood, %)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A"
  ),
  rel_mort_cat = list(
    label = "Relative Mortality (deadwood / forest × 100, %)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A"
  ),
  rel_dist_cat = list(
    label = "Relative Disturbance ((deadwood + loss) / (forest + loss) × 100, %)",
    low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A"
  )
)

# Load SHAP and categorization data
cat("Loading SHAP data...\n")
shap_m06 <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06.csv")
shap_m08_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv"
shap_m08 <- fread(shap_m08_file)[grepl("^M08_", model)]

shap_m06[, group := ifelse(group == "Meteo", "Memory", group)]

shap_raw <- rbindlist(list(shap_m06, shap_m08), fill = TRUE)

# Reclassify variables
shap_raw[, group := fcase(
  variable %in% c("ETmax_anom_lag1", "ETmax_anom_lag2",
                  "GPPsat_anom_lag1", "GPPsat_anom_lag2",
                  "NEPmax_anom_lag1", "NEPmax_anom_lag2",
                  "uWUE_anom_lag1", "uWUE_anom_lag2"),
  "Memory",
  grepl("^(TA|P|VPD|SW_IN).*_anom_lag", variable), "Climate",
  default = group
)]

# Get common sites
m06_sites <- unique(shap_m06$test_site)
m08_sites <- unique(shap_m08$test_site)
common_sites <- intersect(m06_sites, m08_sites)
cat("Using", length(common_sites), "common sites\n\n")

shap_raw <- shap_raw[test_site %in% common_sites]

# Process SHAP
shap_grp <- shap_raw[group %in% GROUP_LEVELS,
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]

site_tot <- shap_grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
shap_grp <- merge(shap_grp, site_tot, by = c("model", "response", "test_site"))
shap_grp[, rel_shap := grp_shap / total]

full_key <- CJ(model     = unique(shap_grp$model),
               response  = unique(shap_grp$response),
               test_site = unique(shap_grp$test_site),
               group     = GROUP_LEVELS)
shap_grp <- merge(full_key, shap_grp[, .(model, response, test_site, group, rel_shap, grp_shap)],
                  by = c("model", "response", "test_site", "group"), all.x = TRUE)
shap_grp[is.na(rel_shap), rel_shap := 0]
shap_grp[is.na(grp_shap), grp_shap := 0]
shap_grp[, group := factor(group, levels = GROUP_LEVELS)]

# Loop through methods
for (method in METHODS) {
  cat("\n╔════════════════════════════════════════════════════════════╗\n")
  cat("║ SITE SHAP - METHOD:", method, "\n")
  cat("╚════════════════════════════════════════════════════════════╝\n")

  out_dir <- file.path(OUT_BASE, method, "site_shap")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Load categorization data
  cat_data <- fread(paste0("derived_tables/disturbance_metric_test/", method, ".csv"))

  # Merge SHAP with categorization
  shap_grp_cat <- merge(shap_grp, cat_data[, .(SITE_ID, abs_mort_cat, rel_mort_cat, rel_dist_cat)],
                        by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

  # Function to create one panel
  make_one_panel <- function(dt_sub, site_order, metric_col, show_y = TRUE) {
    meta <- DIST_META[[metric_col]]

    dt_plot <- copy(dt_sub)
    dt_plot[, test_site := factor(test_site, levels = site_order)]

    p <- ggplot() +
      geom_col(data = dt_plot,
               aes(x = rel_shap, y = test_site, fill = group),
               position = "stack", width = 0.75) +
      scale_fill_manual(values = GROUP_COLOURS, name = "Driver group") +
      scale_x_continuous(
        limits = c(0, 1.02),
        breaks = seq(0, 1, 0.25),
        labels = c("0", "0.25", "0.50", "0.75", "1.00"),
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
        fill = guide_legend(order = 1, override.aes = list(size = 3.5))
      )

    p
  }

  # Create plots for M06 and M08
  for (mod_key in c("M06", "M08")) {
    cat("  Generating", mod_key, "plots...\n")

    efps    <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
    windows <- c("12m", "24m")

    for (win in windows) {
      for (resp in efps) {
        mod_pattern <- paste0("^", mod_key, "_", win, "_", resp, "$")
        dt_sub <- shap_grp_cat[grepl(mod_pattern, model) & response == resp]

        if (nrow(dt_sub) == 0) {
          cat("    (no data:", resp, win, ")\n")
          next
        }

        # Create three panels (one per metric)
        site_order <- dt_sub[group == "Disturbance",
                             .(dist_share = mean(rel_shap)), by = test_site
                             ][order(-dist_share), test_site]

        panels <- list()
        for (metric_col in c("abs_mort_cat", "rel_mort_cat", "rel_dist_cat")) {
          p <- make_one_panel(dt_sub, site_order, metric_col, show_y = (metric_col == "abs_mort_cat"))
          panels[[metric_col]] <- p
        }

        title_str <- sprintf("%s | %s | %s window", mod_key, EFP_UNITS[resp], win)

        combined <- (panels[[1]] | panels[[2]] | panels[[3]]) +
          plot_annotation(
            title = title_str,
            theme = theme(plot.title = element_text(face = "bold", size = 10, hjust = 0.5))
          ) +
          plot_layout(guides = "collect") &
          theme(legend.position = "right")

        n_sites <- uniqueN(dt_sub$test_site)
        h <- max(6, n_sites * 0.17 + 2)

        stem <- file.path(out_dir, paste0("site_shap_", mod_key, "_", resp, "_", win))
        ggsave(paste0(stem, ".png"), combined, width = 24, height = h, dpi = 150, limitsize = FALSE, bg = DARK_BG)
      }
    }
  }

  cat("✓ Site SHAP plots complete for", method, "\n")
}

cat("\n✓ All site SHAP plots complete!\n")

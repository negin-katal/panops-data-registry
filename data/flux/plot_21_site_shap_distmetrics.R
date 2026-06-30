library(data.table)
library(ggplot2)
library(patchwork)

# ============================================================
# PLOT 21: Site-level SHAP stacked bars (M04, 12m + 24m,
#          all 5 EFPs) with dots coloured by 3 disturbance
#          metrics:
#   1. Absolute Mortality  = deadwood_mean_pct_500m          (%)
#   2. Relative Mortality  = (deadwood / forest) × 100       (%)
#   3. Relative Disturbance= (deadwood + loss*100) / forest  (%)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir   <- "plots/site_shap_disturbance_metrics"
shap_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_site_shap_M04_M08.csv"
mod_file  <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── colours ──────────────────────────────────────────────────
COL_CLIMATE     <- "#4A90D9"
COL_TRAITS      <- "#3DBDAA"
COL_DISTURBANCE <- "#D4A017"

GROUP_COLOURS   <- c(Climate = COL_CLIMATE, Traits = COL_TRAITS,
                     Disturbance = COL_DISTURBANCE)
GROUP_LEVELS    <- c("Climate","Traits","Disturbance")

EFP_UNITS <- c(
  GPPsat = "GPPsat  (µmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)",
  WUE    = "WUE  (g C mm⁻¹)"
)

# Shared colour ramp: green (low) → orange → red (high)
MORT_LOW  <- "#1A9641"   # green  = low mortality
MORT_MID  <- "#FDAE61"   # orange = mid
MORT_HIGH <- "#D7191C"   # red    = high mortality

DIST_META <- list(
  abs_mort = list(
    col   = "abs_mort",
    label = "Absolute Mortality\n(deadwood 500m, %)",
    low = MORT_LOW, mid = MORT_MID, high = MORT_HIGH,
    mid_v = 10
  ),
  rel_mort = list(
    col   = "rel_mort",
    label = "Relative Mortality\n(deadwood / forest × 100, %)",
    low = MORT_LOW, mid = MORT_MID, high = MORT_HIGH,
    mid_v = 10
  ),
  rel_dist = list(
    col   = "rel_dist",
    label = "Relative Disturbance\n((deadwood + loss×100) / (forest + loss×100), %)",
    low = MORT_LOW, mid = MORT_MID, high = MORT_HIGH,
    mid_v = 20
  )
)

# ── load SHAP ────────────────────────────────────────────────
shap_raw <- fread(shap_file)
cat("SHAP rows:", nrow(shap_raw), "\n")

shap_grp <- shap_raw[group %in% GROUP_LEVELS,
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]
# total only over the 3 shown groups (Memory excluded), so bars sum to 1
site_tot <- shap_grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
shap_grp <- merge(shap_grp, site_tot, by = c("model","response","test_site"))
shap_grp[, rel_shap := grp_shap / total]

full_key <- CJ(model     = unique(shap_grp$model),
               response  = unique(shap_grp$response),
               test_site = unique(shap_grp$test_site),
               group     = GROUP_LEVELS)
shap_grp <- merge(full_key,
                  shap_grp[, .(model, response, test_site, group, rel_shap, grp_shap)],
                  by = c("model","response","test_site","group"), all.x = TRUE)
shap_grp[is.na(rel_shap), rel_shap := 0]
shap_grp[is.na(grp_shap), grp_shap := 0]
shap_grp[, group := factor(group, levels = GROUP_LEVELS)]

# ── compute 3 disturbance metrics per site (peak across years) ──
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
             deadwood_mean_pct_500m / forest_mean_pct_500m * 100,
             NA_real_), na.rm = TRUE),
    rel_dist = max(
      ifelse((forest_mean_pct_500m + loss_area_frac_500m * 100) > 0,
             (deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
               (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100,
             NA_real_), na.rm = TRUE)
  ),
  by = SITE_ID]

# replace Inf (from all-NA sites) with NA
site_dist[abs_mort == -Inf, abs_mort := NA]
site_dist[rel_mort == -Inf, rel_mort := NA]
site_dist[rel_dist == -Inf, rel_dist := NA]

cat(sprintf("abs_mort:  %.2f – %.2f\n",
            min(site_dist$abs_mort, na.rm=T), max(site_dist$abs_mort, na.rm=T)))
cat(sprintf("rel_mort:  %.2f – %.2f\n",
            min(site_dist$rel_mort, na.rm=T), max(site_dist$rel_mort, na.rm=T)))
cat(sprintf("rel_dist:  %.2f – %.2f\n",
            min(site_dist$rel_dist, na.rm=T), max(site_dist$rel_dist, na.rm=T)))

shap_grp <- merge(shap_grp, site_dist, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

# ── plot factory ─────────────────────────────────────────────

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
    geom_col(data     = dt_plot,
             aes(x = rel_shap, y = test_site, fill = group),
             position = "stack", width = 0.75) +
    geom_point(data = dot_dt,
               aes(x      = -0.05,
                   y      = test_site,
                   colour = metric_val,
                   size   = metric_val)) +
    scale_fill_manual(values = GROUP_COLOURS, name = "Driver group") +
    scale_colour_gradient2(
      low      = meta$low, mid = meta$mid, high = meta$high,
      midpoint = meta$mid_v,
      limits   = c(0, max_val),
      na.value = "grey80",
      name     = meta$label
    ) +
    scale_size_continuous(
      name   = meta$label,
      range  = c(0.5, 4.5),
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
      axis.text.y        = if (show_y) element_text(size = 6.5) else element_blank(),
      axis.ticks.y       = if (show_y) element_line()           else element_blank(),
      legend.position    = "right",
      legend.key.size    = unit(0.4, "cm"),
      legend.title       = element_text(size = 7.5),
      legend.text        = element_text(size = 7),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank()
    ) +
    guides(
      fill   = guide_legend(order = 1, override.aes = list(size = 3.5)),
      colour = guide_colourbar(order = 2, barheight = unit(2.5, "cm")),
      size   = "none"
    )

  p
}

make_combined_plot <- function(dt_sub, resp_label, mod_key, win) {

  # site order: by descending disturbance SHAP share
  site_order <- dt_sub[group == "Disturbance",
                       .(dist_share = mean(rel_shap)), by = test_site
                       ][order(-dist_share), test_site]

  panels <- lapply(seq_along(DIST_META), function(i) {
    mk <- names(DIST_META)[i]
    make_one_panel(dt_sub, site_order, mk, show_y = (i == 1))
  })

  title_str <- sprintf("M04  (C + T + D)  |  %s  |  %s window",
                       resp_label, win)

  combined <- (panels[[1]] | panels[[2]] | panels[[3]]) +
    plot_annotation(
      title = title_str,
      theme = theme(plot.title = element_text(face = "bold", size = 10, hjust = 0.5))
    ) +
    plot_layout(guides = "collect") &
    theme(legend.position = "right")

  combined
}

# ── generate plots ───────────────────────────────────────────
efps    <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")
windows <- c("12m","24m")

for (win in windows) {
  for (resp in efps) {
    mod_pattern <- paste0("^M04_", win, "_", resp, "$")
    dt_sub <- shap_grp[grepl(mod_pattern, model) & response == resp]
    if (nrow(dt_sub) == 0) {
      cat("  No data:", resp, win, "\n"); next
    }

    p <- make_combined_plot(dt_sub, EFP_UNITS[resp], "M04", win)

    n_sites <- uniqueN(dt_sub$test_site)
    h       <- max(6, n_sites * 0.17 + 2)

    stem <- file.path(out_dir, paste0("site_shap_M04_", resp, "_", win, "_distmetrics"))
    ggsave(paste0(stem, ".png"), p, width = 20, height = h,
           dpi = 150, limitsize = FALSE)
    ggsave(paste0(stem, ".pdf"), p, width = 20, height = h,
           limitsize = FALSE)
    cat("  Saved:", resp, win, "(", n_sites, "sites )\n")
  }
}

cat("\n=== plot_21 DONE ===\n")
cat("Outputs in:", out_dir, "\n")

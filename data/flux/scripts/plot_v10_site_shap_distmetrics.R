#!/usr/bin/env Rscript
# ============================================================================
# V10: Site-level SHAP stacked bars with disturbance-metric dots + IGBP
# Matches plot_21 style. Models: M4, M6(raw/anom), M8(raw/anom) x 12m/24m.
# - Stack: Climate / Traits / Disturbance (+ Memory for M6/M8)
# - Dots: 3 mortality metrics, colour midpoint = natural-break High cut
# - Right y-axis: IGBP group per site
# ============================================================================

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_site_shap_distmetrics.R <dataset_type>")
dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 SITE SHAP DISTMETRICS: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep = "")

if (dataset_type == "filtered") {
  harm_file <- "derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_site_shap_M04_M08.csv"
  out_dir   <- "plots/V10/sites_with_high_Tcover/site_SHAP"
} else if (dataset_type == "all_sites") {
  harm_file <- "derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_GPPsat_harmonized.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_site_shap_M04_M08.csv"
  out_dir   <- "plots/V10/all_sites/site_SHAP"
} else {
  stop("Invalid dataset_type")
}
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ── colours ──────────────────────────────────────────────────
GROUP_COLOURS <- c(Climate = "#4A90D9", Traits = "#3DBDAA",
                   Disturbance = "#D4A017", Memory = "#9B5DE5")
GROUP_LEVELS  <- c("Climate", "Traits", "Disturbance", "Memory")

EFP_UNITS <- c(
  GPPsat = "GPPsat  (µmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)",
  WUE    = "WUE  (g C mm⁻¹)"
)

# ── load SHAP ────────────────────────────────────────────────
shap_raw <- fread(shap_file)
cat("SHAP rows:", nrow(shap_raw), "\n")

shap_grp <- shap_raw[group %in% GROUP_LEVELS,
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]
site_tot <- shap_grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
shap_grp <- merge(shap_grp, site_tot, by = c("model", "response", "test_site"))
shap_grp[, rel_shap := grp_shap / total]

# ── disturbance metrics per site (peak across years) from V10 harmonized ──
dt_raw <- fread(harm_file, select = c("SITE_ID", "YEAR",
                                      "absolute_mortality_500m",
                                      "relative_mortality_500m",
                                      "relative_disturbance_500m"))
na_inf <- function(x) { x[!is.finite(x)] <- NA; x }
site_dist <- dt_raw[, .(
  abs_mort = na_inf(max(absolute_mortality_500m, na.rm = TRUE)),
  rel_mort = na_inf(max(relative_mortality_500m, na.rm = TRUE)),
  rel_dist = na_inf(max(relative_disturbance_500m, na.rm = TRUE))
), by = SITE_ID]

# ── natural-break HIGH threshold (mean + 0.5*SD) per metric ──
nb_high <- function(x) mean(x, na.rm = TRUE) + 0.5 * sd(x, na.rm = TRUE)
NB <- list(
  abs_mort = nb_high(site_dist$abs_mort),
  rel_mort = nb_high(site_dist$rel_mort),
  rel_dist = nb_high(site_dist$rel_dist)
)
cat(sprintf("Natural-break HIGH cut  abs_mort=%.2f  rel_mort=%.2f  rel_dist=%.2f\n",
            NB$abs_mort, NB$rel_mort, NB$rel_dist))

DIST_META <- list(
  abs_mort = list(col = "abs_mort",
                  label = sprintf("Absolute Mortality\n(500m, %%)  NB=%.1f", NB$abs_mort),
                  mid_v = NB$abs_mort),
  rel_mort = list(col = "rel_mort",
                  label = sprintf("Relative Mortality\n(%%)  NB=%.1f", NB$rel_mort),
                  mid_v = NB$rel_mort),
  rel_dist = list(col = "rel_dist",
                  label = sprintf("Relative Disturbance\n(%%)  NB=%.1f", NB$rel_dist),
                  mid_v = NB$rel_dist)
)

shap_grp <- merge(shap_grp, site_dist, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

# ── IGBP per site ────────────────────────────────────────────
igbp_src <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv",
                  select = c("SITE_ID", "IGBP"))
igbp_map <- unique(igbp_src)[, .(IGBP = IGBP[1]), by = SITE_ID]

# ── plot factory ─────────────────────────────────────────────
make_one_panel <- function(dt_sub, site_order, metric_key, igbp_vec,
                           show_y = TRUE, show_igbp = FALSE) {
  meta    <- DIST_META[[metric_key]]
  col_var <- meta$col

  dt_plot <- copy(dt_sub)
  dt_plot[, test_site := factor(test_site, levels = site_order)]

  dot_dt <- unique(dt_plot[, c("test_site", col_var), with = FALSE])
  dot_dt[, test_site := factor(test_site, levels = site_order)]
  setnames(dot_dt, col_var, "metric_val")

  max_val <- ceiling(max(dot_dt$metric_val, na.rm = TRUE) / 5) * 5
  max_val <- max(max_val, meta$mid_v * 2)

  y_scale <- if (show_igbp) {
    scale_y_discrete(sec.axis = dup_axis(labels = igbp_vec, name = "IGBP"))
  } else {
    scale_y_discrete()
  }

  p <- ggplot() +
    geom_col(data = dt_plot,
             aes(x = rel_shap, y = test_site, fill = group),
             position = "stack", width = 0.75) +
    geom_point(data = dot_dt,
               aes(x = -0.05, y = test_site, colour = metric_val, size = metric_val)) +
    scale_fill_manual(values = GROUP_COLOURS, name = "Driver group",
                      drop = TRUE) +
    scale_colour_gradient2(
      low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
      midpoint = meta$mid_v, limits = c(0, max_val),
      na.value = "grey80", name = meta$label
    ) +
    scale_size_continuous(name = meta$label, range = c(0.5, 4.5),
                          limits = c(0, max_val)) +
    y_scale +
    scale_x_continuous(limits = c(-0.09, 1.02), breaks = seq(0, 1, 0.25),
                       labels = c("0", "0.25", "0.50", "0.75", "1.00"),
                       expand = expansion(0)) +
    labs(x = "Relative mean |SHAP|", y = NULL) +
    theme_bw(base_size = 9) +
    theme(
      axis.text.y       = if (show_y) element_text(size = 6.5) else element_blank(),
      axis.ticks.y      = if (show_y) element_line() else element_blank(),
      axis.text.y.right = if (show_igbp) element_text(size = 6, colour = "grey30") else element_blank(),
      legend.position   = "right",
      legend.key.size   = unit(0.4, "cm"),
      legend.title      = element_text(size = 7.5),
      legend.text       = element_text(size = 7),
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

make_combined_plot <- function(dt_sub, resp_label, model_label) {
  site_order <- dt_sub[group == "Disturbance",
                       .(dist_share = mean(rel_shap)), by = test_site
                       ][order(-dist_share), test_site]
  # IGBP labels ordered to match site_order
  igbp_vec <- igbp_map[match(site_order, SITE_ID), IGBP]
  igbp_vec[is.na(igbp_vec)] <- "NA"

  metric_keys <- names(DIST_META)
  panels <- lapply(seq_along(metric_keys), function(i) {
    make_one_panel(dt_sub, site_order, metric_keys[i], igbp_vec,
                   show_y = (i == 1), show_igbp = (i == length(metric_keys)))
  })

  title_str <- sprintf("%s  |  %s", model_label, resp_label)

  (panels[[1]] | panels[[2]] | panels[[3]]) +
    plot_annotation(title = title_str,
                    theme = theme(plot.title = element_text(face = "bold", size = 10, hjust = 0.5))) +
    plot_layout(guides = "collect") &
    theme(legend.position = "right")
}

# ── model set + labels ───────────────────────────────────────
MODEL_LABELS <- list(
  "M4_12m"      = "M4 (C+T+D)",              "M4_24m"      = "M4 (C+T+D)",
  "M6_raw_12m"  = "M6 raw (C+T+D+Mem)",      "M6_raw_24m"  = "M6 raw (C+T+D+Mem)",
  "M6_anom_12m" = "M6 anom (C+T+D+Mem)",     "M6_anom_24m" = "M6 anom (C+T+D+Mem)",
  "M8_raw_12m"  = "M8 raw (C+T+D+Mem)",      "M8_raw_24m"  = "M8 raw (C+T+D+Mem)",
  "M8_anom_12m" = "M8 anom (C+T+D+Mem)",     "M8_anom_24m" = "M8 anom (C+T+D+Mem)"
)

models  <- names(MODEL_LABELS)
efps    <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

cat("\nGenerating plots:\n")
for (this_model in models) {
  model_label <- MODEL_LABELS[[this_model]]
  win <- if (grepl("12m$", this_model)) "12m" else "24m"
  mtag <- sub("_(12m|24m)$", "", this_model)  # e.g. M6_raw

  for (this_resp in efps) {
    # NB: use distinct names so data.table's i-scope does not resolve these
    # to the columns `model`/`response` (that makes the filter always-TRUE).
    dt_sub <- shap_grp[model == this_model & response == this_resp]
    if (nrow(dt_sub) == 0) { cat("  No data:", this_model, this_resp, "\n"); next }
    resp <- this_resp

    dt_sub[, group := factor(group, levels = GROUP_LEVELS)]

    p <- make_combined_plot(dt_sub, EFP_UNITS[resp],
                            sprintf("%s | %s window", model_label, win))

    n_sites <- uniqueN(dt_sub$test_site)
    h <- max(6, n_sites * 0.17 + 2)

    stem <- file.path(out_dir, sprintf("site_shap_%s_%s_%s_distmetrics", mtag, resp, win))
    ggsave(paste0(stem, ".png"), p, width = 20, height = h, dpi = 150, limitsize = FALSE)
    ggsave(paste0(stem, ".pdf"), p, width = 20, height = h, limitsize = FALSE)
    cat(sprintf("  ✓ %s (%d sites)\n", basename(stem), n_sites))
  }
}

cat("\n✅ V10 SITE SHAP DISTMETRICS COMPLETE\n")
cat("   Output:", out_dir, "/\n")

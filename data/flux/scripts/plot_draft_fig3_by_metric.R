#!/usr/bin/env Rscript
# ============================================================================
# Coauthor draft — Fig 3, restructured: metric becomes the file-split axis,
# EFPs become the side-by-side panels (transpose of the previous 4-file,
# 3-panel layout: 4 files [one per EFP] x 3 panels [one per disturbance
# metric] -> 3 files [one per metric] x 4 panels [one per EFP]).
#
# Same visual design as plot_v10_site_shap_distmetrics.R, unchanged:
# per-site stacked driver-group composition (Climate/Traits/Disturbance) +
# one dot-column per panel giving that site's value of the fixed metric,
# IGBP on the right axis of the last panel. M4 only, both windows,
# XGBoost-Optuna (matches the figure as already captioned in the draft).
#
# 24m draws on the lag2-corrected true_24m data; 12m is unchanged.
# ============================================================================
suppressMessages({library(data.table); library(ggplot2); library(patchwork)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

B <- "derived_tables/outputs_afterEGU_results"
OUT <- "manuscript_coauthor_draft/figures"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

shap_file <- sprintf("%s/XGB_v10_true24m_optuna/XGB_site_shap_M04_M08.csv", B)
harm_file <- sprintf("%s/v10/v10_B1_GPPsat_harmonized.csv", B)   # site-level metric values; window-independent

GROUP_COLOURS <- c(Climate = "#4A90D9", Traits = "#3DBDAA", Disturbance = "#D4A017", Memory = "#9B5DE5")
GROUP_LEVELS  <- c("Climate", "Traits", "Disturbance", "Memory")
EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "WUE")   # uWUE dropped, matches the rest of the draft
EFP_UNITS <- c(GPPsat = "GPPsat  (µmol m⁻² s⁻¹)", NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
               ETmax  = "ETmax  (mm d⁻¹)",         WUE    = "WUE  (g C mm⁻¹)")

shap_raw <- fread(shap_file)
shap_grp <- shap_raw[group %in% GROUP_LEVELS & model %in% c("M4_12m", "M4_24m") & response %in% EFP_ORDER,
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]
site_tot <- shap_grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
shap_grp <- merge(shap_grp, site_tot, by = c("model", "response", "test_site"))
shap_grp[, rel_shap := grp_shap / total]

dt_raw <- fread(harm_file, select = c("SITE_ID", "YEAR", "absolute_mortality_500m",
                                       "relative_mortality_500m", "relative_disturbance_500m"))
na_inf <- function(x) { x[!is.finite(x)] <- NA; x }
site_dist <- dt_raw[, .(abs_mort = na_inf(max(absolute_mortality_500m, na.rm = TRUE)),
                        rel_mort = na_inf(max(relative_mortality_500m, na.rm = TRUE)),
                        rel_dist = na_inf(max(relative_disturbance_500m, na.rm = TRUE))), by = SITE_ID]

nb_high <- function(x) mean(x, na.rm = TRUE) + 0.5 * sd(x, na.rm = TRUE)
NB <- list(abs_mort = nb_high(site_dist$abs_mort), rel_mort = nb_high(site_dist$rel_mort),
          rel_dist = nb_high(site_dist$rel_dist))

DIST_META <- list(
  abs_mort = list(col = "abs_mort", label = sprintf("Absolute Mortality\n(500m, %%)  NB=%.1f", NB$abs_mort), mid_v = NB$abs_mort),
  rel_mort = list(col = "rel_mort", label = sprintf("Relative Mortality\n(%%)  NB=%.1f", NB$rel_mort), mid_v = NB$rel_mort),
  rel_dist = list(col = "rel_dist", label = sprintf("Relative Disturbance\n(%%)  NB=%.1f", NB$rel_dist), mid_v = NB$rel_dist)
)

shap_grp <- merge(shap_grp, site_dist, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

igbp_src <- fread(sprintf("%s/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv", B), select = c("SITE_ID", "IGBP"))
igbp_map <- unique(igbp_src)[, .(IGBP = IGBP[1]), by = SITE_ID]

# one panel = one EFP's stacked composition + the FIXED metric's dot column
make_one_panel <- function(dt_sub, site_order, metric_key, igbp_vec, efp_label,
                           show_y = TRUE, show_igbp = FALSE) {
  meta <- DIST_META[[metric_key]]; col_var <- meta$col
  dt_plot <- copy(dt_sub); dt_plot[, test_site := factor(test_site, levels = site_order)]
  dot_dt <- unique(dt_plot[, c("test_site", col_var), with = FALSE])
  dot_dt[, test_site := factor(test_site, levels = site_order)]
  setnames(dot_dt, col_var, "metric_val")
  max_val <- ceiling(max(dot_dt$metric_val, na.rm = TRUE) / 5) * 5
  max_val <- max(max_val, meta$mid_v * 2)
  y_scale <- if (show_igbp) scale_y_discrete(sec.axis = dup_axis(labels = igbp_vec, name = "IGBP")) else scale_y_discrete()

  ggplot() +
    geom_col(data = dt_plot, aes(x = rel_shap, y = test_site, fill = group), position = "stack", width = 0.75) +
    geom_point(data = dot_dt, aes(x = -0.05, y = test_site, colour = metric_val, size = metric_val)) +
    scale_fill_manual(values = GROUP_COLOURS, name = "Driver group", drop = TRUE) +
    scale_colour_gradient2(low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
                           midpoint = meta$mid_v, limits = c(0, max_val), na.value = "grey80", name = meta$label) +
    scale_size_continuous(name = meta$label, range = c(0.5, 4.5), limits = c(0, max_val)) +
    y_scale +
    scale_x_continuous(limits = c(-0.09, 1.02), breaks = seq(0, 1, 0.25),
                       labels = c("0", "0.25", "0.50", "0.75", "1.00"), expand = expansion(0)) +
    labs(x = "Relative mean |SHAP|", y = NULL, title = efp_label) +
    theme_bw(base_size = 9) +
    theme(
      plot.title = element_text(size = 9, face = "bold", hjust = 0.5),
      axis.text.y = if (show_y) element_text(size = 6.5) else element_blank(),
      axis.ticks.y = if (show_y) element_line() else element_blank(),
      axis.text.y.right = if (show_igbp) element_text(size = 6, colour = "grey30") else element_blank(),
      legend.position = "right", legend.key.size = unit(0.4, "cm"),
      legend.title = element_text(size = 7.5), legend.text = element_text(size = 7),
      panel.grid.major.y = element_blank(), panel.grid.minor = element_blank()
    ) +
    guides(fill = guide_legend(order = 1, override.aes = list(size = 3.5)),
          colour = guide_colourbar(order = 2, barheight = unit(2.5, "cm")), size = "none")
}

make_combined_plot <- function(dt_model, metric_key, model_label) {
  # shared site order across all 4 EFP panels: mean disturbance SHAP share,
  # pooled across the 4 EFPs for this model/window (same principle as the
  # production script's per-EFP ordering, extended to be shared across panels)
  site_order <- dt_model[group == "Disturbance", .(dist_share = mean(rel_shap)), by = test_site
                         ][order(-dist_share), test_site]
  igbp_vec <- igbp_map[match(site_order, SITE_ID), IGBP]; igbp_vec[is.na(igbp_vec)] <- "NA"

  panels <- lapply(seq_along(EFP_ORDER), function(i) {
    efp <- EFP_ORDER[i]
    dt_sub <- dt_model[response == efp]
    dt_sub[, group := factor(group, levels = GROUP_LEVELS)]
    make_one_panel(dt_sub, site_order, metric_key, igbp_vec, EFP_UNITS[efp],
                   show_y = (i == 1), show_igbp = (i == length(EFP_ORDER)))
  })

  metric_title <- strsplit(DIST_META[[metric_key]]$label, "\n")[[1]][1]
  title_str <- sprintf("%s  |  %s", model_label, metric_title)

  Reduce(`|`, panels) +
    plot_annotation(title = title_str,
                    theme = theme(plot.title = element_text(face = "bold", size = 11, hjust = 0.5))) +
    plot_layout(guides = "collect") & theme(legend.position = "right")
}

MODEL_LABELS <- list(M4_12m = "M4 (C+T+D), 12m window, XGBoost--Optuna",
                     M4_24m = "M4 (C+T+D), 24m window, XGBoost--Optuna")

cat("Generating metric-keyed Fig 3 panels (M4, XGBoost-Optuna, both windows):\n")
for (metric_key in names(DIST_META)) {
  for (this_model in names(MODEL_LABELS)) {
    win <- if (grepl("12m$", this_model)) "12m" else "24m"
    dt_model <- shap_grp[model == this_model]
    if (nrow(dt_model) == 0) { cat("  No data:", this_model, "\n"); next }

    p <- make_combined_plot(dt_model, metric_key, MODEL_LABELS[[this_model]])
    n_sites <- uniqueN(dt_model$test_site)
    h <- max(6, n_sites * 0.17 + 2)

    stem <- file.path(OUT, sprintf("fig3_%s_%s", metric_key, win))
    ggsave(paste0(stem, ".png"), p, width = 20, height = h, dpi = 150, limitsize = FALSE)
    ggsave(paste0(stem, ".pdf"), p, width = 20, height = h, limitsize = FALSE)
    cat(sprintf("  OK %s (%d sites)\n", basename(stem), n_sites))
  }
}
cat("\nFig 3 (by metric) done.\n")

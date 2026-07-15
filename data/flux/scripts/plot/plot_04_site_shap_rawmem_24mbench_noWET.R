library(data.table)
library(ggplot2)

# ============================================================
# PLOT 03: Site-level SHAP — stacked bar of relative |SHAP|
#          by driver group, with disturbance intensity dots
#
# Uses output of run_22_RF_site_shap.R (anomaly memory)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

MEMORY_TYPE <- "raw-lag"   # label used in plot titles ("anomaly" or "raw-lag")

COL_CLIMATE     <- "#4A90D9"
COL_TRAITS      <- "#3DBDAA"
COL_DISTURBANCE <- "#D4A017"
COL_MEMORY      <- "#9B59B6"

DOT_LOW  <- "#6AACD0"   # blue  (low disturbance)
DOT_HIGH <- "#C0507A"   # rose  (high disturbance)
DOT_MID  <- "#F0F0F0"   # near-white at midpoint

THRESH_PCT <- 30        # colour midpoint (%)

out_dir    <- "plots/disturbance_effects/24mbench_noWET"
shap_file  <- "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench/RF_site_shap_M04_M08.csv"
model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# ============================================================
# 1) Load SHAP data and aggregate by group
# ============================================================

shap_raw <- fread(shap_file)
cat("Loaded", nrow(shap_raw), "SHAP rows\n")

# Exclude WET (wetland) IGBP sites post-hoc (no retraining)
site_igbp <- unique(fread(model_file, select = c("SITE_ID", "IGBP")))
wet_sites <- site_igbp[IGBP == "WET", SITE_ID]
n_before  <- uniqueN(shap_raw$test_site)
shap_raw  <- shap_raw[!test_site %in% wet_sites]
n_after   <- uniqueN(shap_raw$test_site)
cat(sprintf("Excluded WET sites from SHAP (%d -> %d sites)\n", n_before, n_after))


GROUP_LEVELS <- c("Climate", "Traits", "Disturbance", "Memory")

shap_grp <- shap_raw[group %in% GROUP_LEVELS,
                     .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]

site_total <- shap_grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
shap_grp   <- merge(shap_grp, site_total, by = c("model", "response", "test_site"))
shap_grp[, rel_shap := grp_shap / total]

full_key <- CJ(
  model     = unique(shap_grp$model),
  response  = unique(shap_grp$response),
  test_site = unique(shap_grp$test_site),
  group     = GROUP_LEVELS
)
shap_grp <- merge(full_key,
                  shap_grp[, .(model, response, test_site, group, rel_shap, grp_shap)],
                  by = c("model", "response", "test_site", "group"), all.x = TRUE)
shap_grp[is.na(rel_shap), rel_shap := 0]
shap_grp[is.na(grp_shap), grp_shap := 0]
shap_grp[, group := factor(group, levels = GROUP_LEVELS)]

# ============================================================
# 2) Disturbance intensity per site
# ============================================================

dt_dist  <- fread(model_file,
                  select = c("SITE_ID", "YEAR", "mortality_intensity_pct_500m"))
dt_dist  <- dt_dist[!SITE_ID %in% EXCLUDE_SITES]
dt_dist  <- dt_dist[!SITE_ID %in% wet_sites]
site_dist <- dt_dist[, .(
  peak_mort = max(mortality_intensity_pct_500m, na.rm = TRUE)
), by = SITE_ID]

cat(sprintf("Peak mortality range: %.1f – %.1f%%\n",
            min(site_dist$peak_mort), max(site_dist$peak_mort)))

shap_grp <- merge(shap_grp,
                  site_dist[, .(SITE_ID, peak_mort)],
                  by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)
shap_grp[is.na(peak_mort), peak_mort := 0]

# ============================================================
# 3) Plot factory
# ============================================================

group_colours <- c(
  Climate     = COL_CLIMATE,
  Traits      = COL_TRAITS,
  Disturbance = COL_DISTURBANCE,
  Memory      = COL_MEMORY
)

efp_units <- c(
  GPPsat = "GPPsat  (μmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (μmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)"
)

# Human-readable model label: "M04" -> "M04  (C+T+D)"
model_predictor_label <- c(
  M04 = "C + T + D",
  M08 = sprintf("C + T + D + M (%s)", MEMORY_TYPE)
)

make_shap_plot <- function(dt_in, mod_key, resp_label) {

  site_order <- dt_in[group == "Disturbance",
                      .(dist_share = mean(rel_shap)),
                      by = test_site][order(-dist_share), test_site]
  dt_in[, test_site := factor(test_site, levels = site_order)]

  dot_dt <- unique(dt_in[, .(test_site, peak_mort)])
  dot_dt[, test_site := factor(test_site, levels = site_order)]

  mort_max <- max(dot_dt$peak_mort, na.rm = TRUE)

  title_str <- paste0(mod_key, "  (", model_predictor_label[mod_key], ")  |  ", resp_label)

  ggplot() +
    geom_col(data  = dt_in,
             aes(x = rel_shap, y = test_site, fill = group),
             position = "stack", width = 0.75) +
    geom_point(data = dot_dt,
               aes(x       = -0.05,
                   y       = test_site,
                   colour  = peak_mort,
                   size    = peak_mort)) +
    scale_fill_manual(values = group_colours, name = "Driver group") +
    scale_colour_gradient2(
      low      = DOT_LOW,
      mid      = DOT_MID,
      high     = DOT_HIGH,
      midpoint = THRESH_PCT,
      limits   = c(0, max(100, mort_max)),
      name     = "Peak mortality\nintensity (%)"
    ) +
    scale_size_continuous(
      name   = "Peak mortality\nintensity (%)",
      range  = c(0.5, 4.5),
      limits = c(0, max(100, mort_max)),
      breaks = c(10, 30, 50, 80),
      labels = c("10 %", "30 %", "50 %", "80 %")
    ) +
    scale_x_continuous(
      limits = c(-0.09, 1.02),
      breaks = seq(0, 1, 0.25),
      labels = c("0", "0.25", "0.50", "0.75", "1.00"),
      expand = expansion(0)
    ) +
    labs(
      title = title_str,
      x     = "Relative mean |SHAP|",
      y     = NULL
    ) +
    theme_bw(base_size = 10) +
    theme(
      plot.title         = element_text(face = "bold", size = 10, hjust = 0.5),
      axis.text.y        = element_text(size = 7),
      legend.position    = "right",
      legend.key.size    = unit(0.45, "cm"),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank()
    ) +
    guides(
      fill   = guide_legend(order = 1, override.aes = list(size = 4)),
      colour = guide_colourbar(order = 2, barheight = unit(3, "cm")),
      size   = guide_legend(order = 3)
    )
}

# ============================================================
# 4) Generate plots
# ============================================================

cat("Generating SHAP plots...\n")
for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
  for (mod_key in c("M04", "M08")) {
    mod_pattern <- paste0("^", mod_key, "_12m_", resp)
    dt_sub <- shap_grp[grepl(mod_pattern, model) & response == resp]
    if (nrow(dt_sub) == 0) {
      cat("No data for", mod_key, resp, "\n"); next
    }

    p <- make_shap_plot(dt_sub, mod_key, efp_units[resp])
    h <- max(5, uniqueN(dt_sub$test_site) * 0.18 + 2)

    stem <- file.path(out_dir,
                      paste0("site_shap_", mod_key, "_", MEMORY_TYPE, "_", resp, "_12m"))
    ggsave(paste0(stem, ".png"), p, width = 7.5, height = h,
           dpi = 180, limitsize = FALSE)
    ggsave(paste0(stem, ".pdf"), p, width = 7.5, height = h,
           limitsize = FALSE)
    cat("  Saved:", mod_key, resp, "\n")
  }
}

cat("\n=== plot_03 DONE ===\n")
cat("Outputs in:", out_dir, "\n")

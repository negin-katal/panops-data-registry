library(data.table)
library(ggplot2)

# ============================================================
# PLOT 13: Site-level SHAP bars — dot colour = new mortality
#          rate raw (v2-2, 500m), IGBP label on right side
#
# Based on plot_03_site_shap_24mbench.R; only changes:
#   - dot colour metric → new_mortality_rate_pct_500m
#   - IGBP code label added to right of each bar
#   - output → plots/site_shap_newmort/
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

MEMORY_TYPE <- "anomaly"

COL_CLIMATE     <- "#4A90D9"
COL_TRAITS      <- "#3DBDAA"
COL_DISTURBANCE <- "#D4A017"
COL_MEMORY      <- "#9B59B6"

DOT_LOW  <- "#6AACD0"
DOT_HIGH <- "#CC2200"
DOT_MID  <- "#F0F0F0"
THRESH_PCT <- 10        # midpoint: above 10% → red

out_dir    <- "plots/site_shap_newmort"
shap_file  <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_site_shap_M04_M08.csv"
shap_file2 <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_site_shap_M09_M10.csv"
model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
dist_file  <- "derived_tables/final_disturbance_v2-2_multibuffer.csv"

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# ── 1) SHAP data ──────────────────────────────────────────────────────────────
shap_raw <- fread(shap_file)
if (file.exists(shap_file2)) {
  shap_raw <- rbindlist(list(shap_raw, fread(shap_file2)), fill = TRUE)
}
cat("SHAP rows:", nrow(shap_raw), "\n")

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

# ── 2) New mortality rate raw (peak per site, 500m) ───────────────────────────
dt_dist <- fread(dist_file, select = c("site_id", "year", "new_mortality_rate_pct_500m"))
setnames(dt_dist, "site_id", "SITE_ID")
dt_dist <- dt_dist[!SITE_ID %in% EXCLUDE_SITES]
site_mr <- dt_dist[!is.na(new_mortality_rate_pct_500m),
                   .(peak_mr = max(new_mortality_rate_pct_500m, na.rm = TRUE)),
                   by = SITE_ID]
cat(sprintf("Peak new mort. rate range: %.1f – %.1f%%\n",
            min(site_mr$peak_mr), max(site_mr$peak_mr)))

# ── 3) IGBP per site ──────────────────────────────────────────────────────────
site_igbp <- unique(fread(model_file, select = c("SITE_ID", "IGBP")))
site_igbp <- site_igbp[!SITE_ID %in% EXCLUDE_SITES]

# Merge both into shap_grp
shap_grp <- merge(shap_grp,
                  site_mr[, .(SITE_ID, peak_mr)],
                  by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)
shap_grp[is.na(peak_mr), peak_mr := 0]

shap_grp <- merge(shap_grp,
                  site_igbp[, .(SITE_ID, IGBP)],
                  by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)
shap_grp[is.na(IGBP), IGBP := "?"]

# ── 4) Plot factory ───────────────────────────────────────────────────────────
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

model_predictor_label <- c(
  M04 = "C + T + D",
  M08 = sprintf("C + T + D + M (%s)", MEMORY_TYPE),
  M09 = sprintf("M (%s) only", MEMORY_TYPE),
  M10 = sprintf("M (%s) + D", MEMORY_TYPE)
)

make_shap_plot <- function(dt_in, mod_key, resp_label) {

  # Order sites by Disturbance SHAP share (descending)
  site_order <- dt_in[group == "Disturbance",
                      .(dist_share = mean(rel_shap)),
                      by = test_site][order(-dist_share), test_site]
  dt_in[, test_site := factor(test_site, levels = site_order)]

  dot_dt  <- unique(dt_in[, .(test_site, peak_mr, IGBP)])
  dot_dt[, test_site := factor(test_site, levels = site_order)]

  mr_max <- max(dot_dt$peak_mr, na.rm = TRUE)

  title_str <- paste0(mod_key, "  (", model_predictor_label[mod_key], ")  |  ", resp_label)

  ggplot() +
    # Stacked SHAP bars
    geom_col(data     = dt_in,
             aes(x    = rel_shap, y = test_site, fill = group),
             position = "stack", width = 0.75) +
    # Left-side dot coloured by new mortality rate raw
    geom_point(data = dot_dt,
               aes(x      = -0.05,
                   y      = test_site,
                   colour = peak_mr,
                   size   = peak_mr)) +
    # IGBP code on right side of bars
    geom_text(data = dot_dt,
              aes(x = 1.03, y = test_site, label = IGBP),
              hjust  = 0, size = 2.2, colour = "#9CA3AF") +
    scale_fill_manual(values = group_colours, name = "Driver group") +
    scale_colour_gradient2(
      low      = DOT_LOW,
      mid      = DOT_MID,
      high     = DOT_HIGH,
      midpoint = THRESH_PCT,
      limits   = c(0, max(50, mr_max)),
      name     = "Peak new\nmort. rate\nraw (%)"
    ) +
    scale_size_continuous(
      name   = "Peak new\nmort. rate\nraw (%)",
      range  = c(0.5, 4.5),
      limits = c(0, max(50, mr_max)),
      breaks = c(5, 15, 30, 50),
      labels = c("5 %", "15 %", "30 %", "50 %")
    ) +
    scale_x_continuous(
      limits = c(-0.09, 1.15),
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

# ── 5) Generate plots ─────────────────────────────────────────────────────────
cat("Generating site_shap plots with new mortality rate...\n")
for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
  for (mod_key in c("M04", "M08", "M09", "M10")) {
    mod_pattern <- paste0("^", mod_key, "_12m_", resp)
    dt_sub <- shap_grp[grepl(mod_pattern, model) & response == resp]
    if (nrow(dt_sub) == 0) { cat("No data for", mod_key, resp, "\n"); next }

    p <- make_shap_plot(dt_sub, mod_key, efp_units[resp])
    h <- max(5, uniqueN(dt_sub$test_site) * 0.18 + 2)

    stem <- file.path(out_dir,
                      paste0("site_shap_", mod_key, "_", MEMORY_TYPE, "_", resp, "_12m"))
    ggsave(paste0(stem, ".png"), p, width = 8, height = h,
           dpi = 180, limitsize = FALSE)
    ggsave(paste0(stem, ".pdf"), p, width = 8, height = h,
           limitsize = FALSE)
    cat("  Saved:", mod_key, resp, "\n")
  }
}

cat("\n=== plot_13 DONE ===\n")
cat("Outputs in:", out_dir, "\n")

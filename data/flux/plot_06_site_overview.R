library(data.table)
library(ggplot2)

# ============================================================
# PLOT 06: Site overview figures
#
#  A) Global map — coloured by IGBP
#  B) Global map — coloured by peak mortality intensity
#  C) Bar plot — N sites per IGBP class
#  D) Mortality intensity ~ IGBP  (violin + jitter, site-level)
#  E) Disturbance SHAP ~ IGBP    (violin + jitter, per EFP × model)
#       → one figure per model key (M04 / M08) × memory type
#          with 4 EFP facets
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir    <- "plots/disturbance_effects"
model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

shap_sources <- list(
  anomaly = "derived_tables/outputs_afterEGU_results/RF_outputs_fixed/RF_site_shap_M04_M08.csv",
  rawlag  = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_fixed_v2/RF_site_shap_M04_M08.csv"
)

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# ============================================================
# Shared colour / style definitions
# ============================================================

igbp_colours <- c(
  ENF = "#1B6B3A",
  EBF = "#45B045",
  DNF = "#2E8B8B",
  DBF = "#8FBC45",
  MF  = "#5F9EA0",
  CSH = "#C4843B",
  OSH = "#D4B483",
  WSA = "#A9A93A",
  SAV = "#D4C23A",
  WET = "#4682B4",
  CRO = "#CC4444",
  URB = "#888888"
)

igbp_full <- c(
  ENF = "Evergreen Needleleaf",
  EBF = "Evergreen Broadleaf",
  DNF = "Deciduous Needleleaf",
  DBF = "Deciduous Broadleaf",
  MF  = "Mixed Forest",
  CSH = "Closed Shrubland",
  OSH = "Open Shrubland",
  WSA = "Woody Savanna",
  SAV = "Savanna",
  WET = "Wetland",
  CRO = "Cropland",
  URB = "Urban"
)

efp_labels <- c(
  GPPsat = "GPPsat  (μmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (μmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)"
)

mem_labels <- c(anomaly = "anomaly memory", rawlag = "raw-lag memory")

# ============================================================
# 1) Build site-level metadata table
# ============================================================

dt_raw <- fread(model_file,
                select = c("SITE_ID", "YEAR", "IGBP",
                           "LOCATION_LAT", "LOCATION_LONG",
                           "mortality_intensity_pct_500m"))
dt_raw <- dt_raw[!SITE_ID %in% EXCLUDE_SITES]

site_dt <- dt_raw[, .(
  lat       = LOCATION_LAT[1],
  lon       = LOCATION_LONG[1],
  IGBP      = IGBP[1],
  peak_mort = max(mortality_intensity_pct_500m, na.rm = TRUE)
), by = SITE_ID]

# Restrict to the 166-site benchmark (sites present in the anomaly SHAP file)
bench_sites <- unique(fread(shap_sources[["anomaly"]])$test_site)
site_dt <- site_dt[SITE_ID %in% bench_sites]
cat("Sites (benchmark):", nrow(site_dt), "\n")

# factor IGBP in frequency order for bar chart
igbp_freq   <- site_dt[, .N, by = IGBP][order(-N), IGBP]
site_dt[, IGBP_f := factor(IGBP, levels = igbp_freq)]

# ============================================================
# Shared dark-theme helper for maps
# ============================================================

DARK_BG      <- "#1C1C2E"   # near-black ocean/background
LAND_FILL    <- "#2E3250"   # dark blue-grey land
LAND_BORDER  <- "#3D4270"   # slightly lighter border
TEXT_LIGHT   <- "#E0E0E0"   # light grey text

theme_dark_map <- function(base_size = 11) {
  theme_void(base_size = base_size) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = DARK_BG,  colour = NA),
    legend.background = element_rect(fill = DARK_BG, colour = NA),
    legend.key        = element_rect(fill = DARK_BG, colour = NA),
    plot.title        = element_text(colour = TEXT_LIGHT, face = "bold",
                                     size = 11, hjust = 0.5,
                                     margin = margin(b = 6)),
    legend.title      = element_text(colour = TEXT_LIGHT, size = 9),
    legend.text       = element_text(colour = TEXT_LIGHT, size = 8),
    legend.position   = "right",
    legend.key.size   = unit(0.45, "cm"),
    plot.margin       = margin(6, 6, 6, 6)
  )
}

# ============================================================
# A) Global map — coloured by IGBP  (dark theme)
# ============================================================

world <- map_data("world")

p_map_igbp <- ggplot() +
  geom_polygon(data = world,
               aes(x = long, y = lat, group = group),
               fill = LAND_FILL, colour = LAND_BORDER, linewidth = 0.15) +
  geom_point(data = site_dt,
             aes(x = lon, y = lat, colour = IGBP, shape = IGBP),
             size = 2.5, alpha = 0.95) +
  scale_colour_manual(values = igbp_colours,
                      labels = igbp_full,
                      name   = "IGBP class",
                      drop   = TRUE) +
  scale_shape_manual(values = rep(c(16, 17, 15, 18, 8, 3), 2)[seq_along(igbp_colours)],
                     labels = igbp_full,
                     name   = "IGBP class",
                     drop   = TRUE) +
  coord_fixed(1.4, xlim = c(-170, 175), ylim = c(-55, 75), expand = FALSE) +
  labs(title = sprintf("Study sites (n = %d) - IGBP land-cover class",
                       nrow(site_dt)),
       x = NULL, y = NULL) +
  theme_dark_map()

ggsave(file.path(out_dir, "map_sites_IGBP.png"),
       p_map_igbp, width = 10, height = 5, dpi = 200,
       bg = DARK_BG)
ggsave(file.path(out_dir, "map_sites_IGBP.pdf"),
       p_map_igbp, width = 10, height = 5,
       bg = DARK_BG)
cat("Saved: map_sites_IGBP\n")

# ============================================================
# B) Global map — coloured by peak mortality intensity  (dark theme)
# ============================================================

p_map_mort <- ggplot() +
  geom_polygon(data = world,
               aes(x = long, y = lat, group = group),
               fill = LAND_FILL, colour = LAND_BORDER, linewidth = 0.15) +
  geom_point(data = site_dt[order(peak_mort)],   # low mort plotted first
             aes(x = lon, y = lat, colour = peak_mort),
             size = 2.5, alpha = 0.95) +
  scale_colour_gradient2(
    low      = "#6AACD0",
    mid      = "#F5F5F5",
    high     = "#C0507A",
    midpoint = 30,
    name     = "Peak mortality\nintensity (%)",
    limits   = c(0, 100)
  ) +
  coord_fixed(1.4, xlim = c(-170, 175), ylim = c(-55, 75), expand = FALSE) +
  labs(title = sprintf("Study sites (n = %d) - Peak mortality intensity",
                       nrow(site_dt)),
       x = NULL, y = NULL) +
  theme_dark_map() +
  theme(legend.key.size = unit(0.5, "cm"))

ggsave(file.path(out_dir, "map_sites_mortality.png"),
       p_map_mort, width = 10, height = 5, dpi = 200,
       bg = DARK_BG)
ggsave(file.path(out_dir, "map_sites_mortality.pdf"),
       p_map_mort, width = 10, height = 5,
       bg = DARK_BG)
cat("Saved: map_sites_mortality\n")

# ============================================================
# C) Bar chart — N sites per IGBP class
# ============================================================

bar_dt <- site_dt[, .N, by = .(IGBP, IGBP_f)][order(-N)]

p_bar <- ggplot(bar_dt, aes(x = reorder(IGBP_f, -N), y = N, fill = IGBP)) +
  geom_col(width = 0.7, colour = "white") +
  geom_text(aes(label = N), vjust = -0.4, size = 3.5, fontface = "bold") +
  scale_fill_manual(values = igbp_colours, guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = sprintf("Sites per IGBP class  (n = %d total)", nrow(site_dt)),
       x = NULL, y = "Number of sites") +
  theme_bw(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold", size = 11, hjust = 0.5),
    axis.text.x      = element_text(size = 8),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank()
  )

ggsave(file.path(out_dir, "bar_sites_per_IGBP.png"),
       p_bar, width = 8, height = 4.5, dpi = 200)
ggsave(file.path(out_dir, "bar_sites_per_IGBP.pdf"),
       p_bar, width = 8, height = 4.5)
cat("Saved: bar_sites_per_IGBP\n")

# ============================================================
# D) Mortality intensity ~ IGBP  (violin + box + jitter)
# ============================================================

p_mort_igbp <- ggplot(site_dt,
                      aes(x = reorder(IGBP, peak_mort, FUN = median),
                          y = peak_mort,
                          fill = IGBP, colour = IGBP)) +
  geom_violin(alpha = 0.35, linewidth = 0.4, trim = TRUE) +
  geom_boxplot(width = 0.18, alpha = 0.7, outlier.shape = NA,
               colour = "grey20", linewidth = 0.5) +
  geom_jitter(width = 0.15, size = 1.5, alpha = 0.6) +
  scale_fill_manual(values   = igbp_colours, guide = "none") +
  scale_colour_manual(values = igbp_colours, guide = "none") +
  labs(title = "Peak mortality intensity by IGBP class",
       x = NULL, y = "Peak mortality intensity (%)") +
  theme_bw(base_size = 11) +
  theme(
    plot.title         = element_text(face = "bold", size = 11, hjust = 0.5),
    axis.text.x        = element_text(size = 8),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank()
  )

ggsave(file.path(out_dir, "violin_mortality_by_IGBP.png"),
       p_mort_igbp, width = 9, height = 5, dpi = 200)
ggsave(file.path(out_dir, "violin_mortality_by_IGBP.pdf"),
       p_mort_igbp, width = 9, height = 5)
cat("Saved: violin_mortality_by_IGBP\n")

# ============================================================
# E) Disturbance SHAP ~ IGBP  — per EFP × model (faceted)
# ============================================================

for (mem_type in names(shap_sources)) {

  shap_file <- shap_sources[[mem_type]]
  if (!file.exists(shap_file)) {
    cat("Skipping", mem_type, "— file not found\n"); next
  }

  shap_raw <- fread(shap_file)

  GROUP_LEVELS <- c("Climate", "Traits", "Disturbance", "Memory")
  grp <- shap_raw[group %in% GROUP_LEVELS,
                  .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                  by = .(model, response, test_site, group)]
  totals <- grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
  grp    <- merge(grp, totals, by = c("model", "response", "test_site"))
  grp[, rel_shap := grp_shap / total]

  dist_shap <- grp[group == "Disturbance",
                   .(model, response, test_site, dist_rel_shap = rel_shap)]

  # join IGBP
  dist_shap <- merge(dist_shap,
                     site_dt[, .(SITE_ID, IGBP, peak_mort)],
                     by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)

  for (mod_key in c("M04", "M08")) {

    mod_pattern <- paste0("^", mod_key, "_12m_")
    dt_sub <- dist_shap[grepl(mod_pattern, model)]
    if (nrow(dt_sub) == 0) next

    # nice EFP facet labels
    dt_sub[, response_f := factor(response,
                                  levels = c("GPPsat","NEPmax","ETmax","uWUE"),
                                  labels = efp_labels[c("GPPsat","NEPmax","ETmax","uWUE")])]

    mem_lab  <- mem_labels[mem_type]
    pred_lab <- if (mod_key == "M04") "C + T + D" else
                  sprintf("C + T + D + M (%s)", mem_lab)

    igbp_present <- intersect(sort(unique(dt_sub$IGBP)), names(igbp_colours))
    col_sub      <- igbp_colours[igbp_present]

    p_shap_igbp <- ggplot(
      dt_sub[!is.na(IGBP) & IGBP %in% igbp_present],
      aes(x    = reorder(IGBP, dist_rel_shap, FUN = median),
          y    = dist_rel_shap,
          fill = IGBP,
          colour = IGBP)
    ) +
      geom_violin(alpha = 0.35, linewidth = 0.4, trim = TRUE) +
      geom_boxplot(width = 0.18, alpha = 0.7, outlier.shape = NA,
                   colour = "grey20", linewidth = 0.5) +
      geom_jitter(width = 0.15, size = 1.0, alpha = 0.5) +
      scale_fill_manual(values   = col_sub, guide = "none") +
      scale_colour_manual(values = col_sub, guide = "none") +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                         name   = "Disturbance SHAP share") +
      facet_wrap(~ response_f, nrow = 1, scales = "free_y") +
      labs(
        title = sprintf("%s  (%s)  -Disturbance SHAP share by IGBP", mod_key, pred_lab),
        x = NULL
      ) +
      theme_bw(base_size = 10) +
      theme(
        plot.title         = element_text(face = "bold", size = 10, hjust = 0.5),
        strip.text         = element_text(size = 8),
        axis.text.x        = element_text(size = 8, angle = 30, hjust = 1),
        panel.grid.major.x = element_blank(),
        panel.grid.minor   = element_blank()
      )

    stem <- file.path(out_dir,
                      sprintf("violin_distshap_IGBP_%s_%s", mod_key, mem_type))
    ggsave(paste0(stem, ".png"), p_shap_igbp,
           width = 14, height = 4.5, dpi = 200)
    ggsave(paste0(stem, ".pdf"), p_shap_igbp,
           width = 14, height = 4.5)
    cat("Saved: violin_distshap_IGBP", mod_key, mem_type, "\n")
  }
}

cat("\n=== plot_06 DONE ===\n")
cat("Outputs in:", out_dir, "\n")

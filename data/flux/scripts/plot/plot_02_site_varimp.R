library(data.table)
library(ggplot2)

# ============================================================
# PLOT 02: Site-level relative variable importance (M04, M08)
#
# Stacked horizontal bar: Climate | Traits | Disturbance | Memory
# Left-side dot: disturbance intensity (size) and class (colour)
# Sites sorted by Disturbance share (descending)
# One plot per model × EFP  (8 plots total)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

COL_CLIMATE     <- "#4A90D9"  # steel blue
COL_TRAITS      <- "#3DBDAA"  # teal
COL_DISTURBANCE <- "#D4A017"  # amber/gold
COL_MEMORY      <- "#9B59B6"  # purple
COL_OTHER       <- "#AAAAAA"  # grey
COL_HIGH_DOT    <- "#C0507A"  # rose (high disturbance dot)
COL_LOW_DOT     <- "#6AACD0"  # sky blue (low disturbance dot)

out_dir    <- "plots/disturbance_effects"
varimp_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_fixed/RF_per_fold_varimp_M04_M08.csv"
model_file  <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# ============================================================
# 1) Load per-fold variable importance
# ============================================================

if (!file.exists(varimp_file)) {
  stop("Per-fold varimp not found. Run run_21_RF_site_varimp.R first.\n  Expected: ",
       varimp_file)
}

vimp_raw <- fread(varimp_file)
cat("Loaded", nrow(vimp_raw), "rows from", varimp_file, "\n")
cat("Models:", paste(unique(vimp_raw$model), collapse = ", "), "\n")

# ============================================================
# 2) Aggregate to site-level group importance
#    For each (model, response, test_site):
#      sum importance by group → then normalise to relative share
# ============================================================

vimp_grp <- vimp_raw[!is.na(importance) & importance > 0,
                     .(grp_imp = sum(importance, na.rm = TRUE)),
                     by = .(model, response, test_site, group)]

# Total importance per (model, response, test_site) for normalisation
site_total <- vimp_grp[, .(total = sum(grp_imp)), by = .(model, response, test_site)]
vimp_grp   <- merge(vimp_grp, site_total, by = c("model", "response", "test_site"))
vimp_grp[, rel_imp := grp_imp / total]

# Ensure all four groups exist for every site (fill 0 if absent)
GROUP_LEVELS <- c("Climate", "Traits", "Disturbance", "Memory")
full_key <- CJ(
  model     = unique(vimp_grp$model),
  response  = unique(vimp_grp$response),
  test_site = unique(vimp_grp$test_site),
  group     = GROUP_LEVELS
)
vimp_grp <- merge(full_key, vimp_grp[, .(model, response, test_site, group, rel_imp)],
                  by = c("model", "response", "test_site", "group"), all.x = TRUE)
vimp_grp[is.na(rel_imp), rel_imp := 0]

vimp_grp[, group := factor(group, levels = GROUP_LEVELS)]

# ============================================================
# 3) Site disturbance intensity
# ============================================================

cat("Loading disturbance intensity...\n")
dt_dist <- fread(model_file,
                 select = c("SITE_ID", "YEAR", "mortality_intensity_pct_500m"))
dt_dist <- dt_dist[!SITE_ID %in% EXCLUDE_SITES]

site_dist <- dt_dist[, .(
  mean_mort = mean(mortality_intensity_pct_500m, na.rm = TRUE),
  peak_mort = max( mortality_intensity_pct_500m, na.rm = TRUE)
), by = SITE_ID]

thresh <- median(site_dist$peak_mort, na.rm = TRUE)
site_dist[, dist_class := fifelse(peak_mort >= thresh,
                                  "High disturbance", "Low disturbance")]
cat(sprintf("Disturbance threshold: %.1f%% (median peak)\n", thresh))

# Merge into varimp
vimp_grp <- merge(vimp_grp,
                  site_dist[, .(SITE_ID, peak_mort, dist_class)],
                  by.x = "test_site", by.y = "SITE_ID",
                  all.x = TRUE)
vimp_grp[is.na(dist_class), dist_class := "Low disturbance"]
vimp_grp[is.na(peak_mort),  peak_mort  := 0]

# Normalise peak_mort for dot sizes
max_mort <- max(vimp_grp$peak_mort, na.rm = TRUE)
vimp_grp[, dot_size := (peak_mort / max_mort) * 4 + 0.5]  # range ~0.5–4.5

# ============================================================
# 4) Plot factory
# ============================================================

group_colours <- c(
  Climate     = COL_CLIMATE,
  Traits      = COL_TRAITS,
  Disturbance = COL_DISTURBANCE,
  Memory      = COL_MEMORY
)
dot_colours <- c("High disturbance" = COL_HIGH_DOT, "Low disturbance" = COL_LOW_DOT)

efp_units <- c(
  GPPsat = "GPPsat  (μmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (μmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)"
)

make_varimp_plot <- function(dt_in, model_label, resp_label) {

  # Sort sites by Disturbance share (descending)
  site_order <- dt_in[group == "Disturbance",
                      .(dist_share = mean(rel_imp)),
                      by = test_site][order(-dist_share), test_site]
  dt_in[, test_site := factor(test_site, levels = site_order)]

  # One row per site for the dot layer
  dot_dt <- unique(dt_in[, .(test_site, peak_mort, dist_class, dot_size)])
  dot_dt[, test_site := factor(test_site, levels = site_order)]

  ggplot() +
    # Stacked bars
    geom_bar(data = dt_in,
             aes(x = rel_imp, y = test_site, fill = group),
             stat = "identity", position = "stack", width = 0.75) +
    # Disturbance intensity dots at x = -0.04 (left margin)
    geom_point(data = dot_dt,
               aes(x = -0.04, y = test_site,
                   colour = dist_class, size = dot_size)) +
    scale_fill_manual(values = group_colours, name = "Driver group") +
    scale_colour_manual(values = dot_colours, name = "Disturbance class") +
    scale_size_identity() +
    scale_x_continuous(
      limits = c(-0.08, 1.02),
      breaks = c(0, 0.25, 0.5, 0.75, 1.0),
      labels = c("0", "0.25", "0.50", "0.75", "1.00"),
      expand = expansion(0)
    ) +
    labs(
      title = paste0(model_label, "  |  ", resp_label),
      x     = "Relative importance",
      y     = NULL
    ) +
    theme_bw(base_size = 10) +
    theme(
      plot.title         = element_text(face = "bold", size = 11, hjust = 0.5),
      axis.text.y        = element_text(size = 7),
      legend.position    = "right",
      legend.key.size    = unit(0.5, "cm"),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank()
    ) +
    guides(
      fill   = guide_legend(order = 1, override.aes = list(size = 4)),
      colour = guide_legend(order = 2, override.aes = list(size = 3)),
      size   = "none"
    )
}

# ============================================================
# 5) Generate and save
# ============================================================

for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {
  for (mod_label in c("M04", "M08")) {
    mod_pattern <- paste0("^", mod_label, "_12m_", resp)
    dt_sub <- vimp_grp[grepl(mod_pattern, model) & response == resp]
    if (nrow(dt_sub) == 0) {
      cat("No data for", mod_label, resp, "— skipping\n"); next
    }

    p <- make_varimp_plot(dt_sub, mod_label, efp_units[resp])

    h <- max(5, uniqueN(dt_sub$test_site) * 0.18 + 2)
    stem <- file.path(out_dir,
                      paste0("site_varimp_", mod_label, "_", resp, "_12m"))
    ggsave(paste0(stem, ".png"), p, width = 7, height = h,
           dpi = 180, limitsize = FALSE)
    ggsave(paste0(stem, ".pdf"), p, width = 7, height = h,
           limitsize = FALSE)
    cat("  Saved:", mod_label, resp, "\n")
  }
}

cat("\n=== plot_02 DONE ===\n")
cat("Outputs in:", out_dir, "\n")

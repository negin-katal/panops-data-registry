library(data.table)
library(ggplot2)

# ============================================================
# PLOT 05: Scatter — Disturbance SHAP share vs mortality intensity
#          coloured by IGBP, one panel per model × EFP
#
# Reads both anomaly (run_22) and raw-lag (run_23) SHAP files.
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
# 1) Site metadata: peak mortality + IGBP
# ============================================================

dt_meta <- fread(model_file,
                 select = c("SITE_ID", "YEAR", "IGBP", "mortality_intensity_pct_500m"))
dt_meta <- dt_meta[!SITE_ID %in% EXCLUDE_SITES]

site_meta <- dt_meta[, .(
  peak_mort = max(mortality_intensity_pct_500m, na.rm = TRUE),
  IGBP      = IGBP[1]
), by = SITE_ID]

cat("Sites:", nrow(site_meta), "\n")
cat("IGBP classes:\n")
print(site_meta[, .N, by = IGBP][order(-N)])

# ============================================================
# 2) IGBP colour palette
# ============================================================

igbp_colours <- c(
  ENF = "#1B6B3A",   # dark green       – evergreen needleleaf
  EBF = "#45B045",   # bright green     – evergreen broadleaf
  DNF = "#2E8B8B",   # teal             – deciduous needleleaf
  DBF = "#8FBC45",   # yellow-green     – deciduous broadleaf
  MF  = "#5F9EA0",   # cadet blue       – mixed forest
  CSH = "#C4843B",   # brown-orange     – closed shrubland
  OSH = "#D4B483",   # tan              – open shrubland
  WSA = "#A9A93A",   # olive            – woody savanna
  SAV = "#D4C23A",   # gold             – savanna
  WET = "#4682B4",   # steel blue       – wetland
  CRO = "#CC4444",   # red              – cropland
  URB = "#888888"    # grey             – urban
)

efp_units <- c(
  GPPsat = "GPPsat  (μmol m⁻² s⁻¹)",
  NEPmax = "NEPmax  (μmol m⁻² s⁻¹)",
  ETmax  = "ETmax  (mm d⁻¹)",
  uWUE   = "uWUE  (g C mm⁻¹)"
)

mem_labels <- c(anomaly = "anomaly memory", rawlag = "raw-lag memory")

# ============================================================
# 3) Process each SHAP source
# ============================================================

for (mem_type in names(shap_sources)) {

  shap_file <- shap_sources[[mem_type]]
  if (!file.exists(shap_file)) {
    cat("Skipping", mem_type, "— SHAP file not found\n"); next
  }

  shap_raw <- fread(shap_file)
  cat("\nLoaded", mem_type, "SHAP:", nrow(shap_raw), "rows\n")

  # Relative disturbance SHAP per site × model × response
  GROUP_LEVELS <- c("Climate", "Traits", "Disturbance", "Memory")

  grp <- shap_raw[group %in% GROUP_LEVELS,
                  .(grp_shap = sum(mean_abs_shap, na.rm = TRUE)),
                  by = .(model, response, test_site, group)]

  totals <- grp[, .(total = sum(grp_shap)), by = .(model, response, test_site)]
  grp    <- merge(grp, totals, by = c("model", "response", "test_site"))
  grp[, rel_shap := grp_shap / total]

  dist_shap <- grp[group == "Disturbance",
                   .(model, response, test_site, dist_rel_shap = rel_shap)]

  # Join site metadata
  plot_dt <- merge(dist_shap,
                   site_meta[, .(SITE_ID, peak_mort, IGBP)],
                   by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)
  plot_dt[is.na(IGBP),     IGBP     := "Other"]
  plot_dt[is.na(peak_mort), peak_mort := 0]

  # Keep only IGBP classes that have colours defined
  igbp_present <- intersect(unique(plot_dt$IGBP), names(igbp_colours))
  col_scale    <- igbp_colours[igbp_present]

  # ============================================================
  # 4) One plot per model × EFP
  # ============================================================

  for (mod_key in c("M04", "M08")) {
    for (resp in c("GPPsat", "NEPmax", "ETmax", "uWUE")) {

      mod_pattern <- paste0("^", mod_key, "_12m_", resp)
      dt_sub <- plot_dt[grepl(mod_pattern, model) & response == resp]

      if (nrow(dt_sub) == 0) {
        cat("  No data:", mod_key, resp, mem_type, "\n"); next
      }

      mem_lab <- mem_labels[mem_type]
      pred_lab <- if (mod_key == "M04") "C + T + D" else
                    sprintf("C + T + D + M (%s)", mem_lab)

      title_str <- sprintf("%s  (%s)  |  %s", mod_key, pred_lab, efp_units[resp])

      # Spearman r for annotation
      r_val <- cor(dt_sub$dist_rel_shap, dt_sub$peak_mort,
                   method = "spearman", use = "complete.obs")
      n_val <- nrow(dt_sub[!is.na(dist_rel_shap) & !is.na(peak_mort)])
      anno  <- sprintf("ρ = %.2f  (n = %d)", r_val, n_val)

      p <- ggplot(dt_sub, aes(x = dist_rel_shap, y = peak_mort, colour = IGBP)) +
        geom_point(size = 2.2, alpha = 0.8) +
        geom_smooth(method = "lm", se = TRUE,
                    colour = "grey30", fill = "grey80",
                    linewidth = 0.7, linetype = "dashed") +
        annotate("text", x = Inf, y = Inf, label = anno,
                 hjust = 1.05, vjust = 1.5, size = 3.2,
                 colour = "grey20", fontface = "italic") +
        scale_colour_manual(values = col_scale, name = "IGBP",
                            drop = TRUE) +
        scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                           name   = "Disturbance SHAP share") +
        scale_y_continuous(name   = "Peak mortality intensity (%)") +
        labs(title = title_str) +
        theme_bw(base_size = 11) +
        theme(
          plot.title      = element_text(face = "bold", size = 10, hjust = 0.5),
          legend.position = "right",
          legend.key.size = unit(0.4, "cm"),
          panel.grid.minor = element_blank()
        )

      stem <- file.path(out_dir,
                        sprintf("scatter_dist_shap_%s_%s_%s", mod_key, mem_type, resp))
      ggsave(paste0(stem, ".png"), p, width = 6, height = 4.5, dpi = 180)
      ggsave(paste0(stem, ".pdf"), p, width = 6, height = 4.5)
      cat("  Saved:", mod_key, mem_type, resp, "\n")
    }
  }
}

cat("\n=== plot_05 DONE ===\n")
cat("Outputs in:", out_dir, "\n")

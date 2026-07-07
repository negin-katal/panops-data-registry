library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- "plots/manuscript_candidates"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")
IGBP_COL <- c(
  ENF = "#1F6B3A", EBF = "#33A14A", DNF = "#7BC87E", DBF = "#B2DF8A",
  MF  = "#FDBF6F", CSH = "#E5820B", OSH = "#D4A017", WSA = "#C4A85C",
  SAV = "#E8D44D", WET = "#4DAECC"
)

# ── 1) Load SHAP data (anomaly M04, 24m window) ────────────────────────────────
shap <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv")

# Keep M04 (C+T+D) models, 24m window
shap_m04 <- shap[grepl("^M04_24m_", model)]
shap_m04[, response := sub("M04_24m_", "", model)]

# Total SHAP per site × response
shap_total <- shap_m04[, .(total_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]

# Disturbance SHAP per site × response
shap_dist  <- shap_m04[group == "Disturbance",
  .(dist_shap = sum(mean_abs_shap)), by = .(SITE_ID = test_site, response)]

# Calculate percentage
shap_pct <- merge(shap_total, shap_dist, by = c("SITE_ID", "response"))
shap_pct[, dist_pct := dist_shap / total_shap * 100]

# ── 2) Load main dataset to get IGBP for each site ───────────────────────────────
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

# Get unique SITE_ID and IGBP
site_igbp <- unique(main_data[, .(SITE_ID, IGBP)])

# Merge with SHAP data
shap_pct <- merge(shap_pct, site_igbp, by = "SITE_ID")
shap_pct[, response := factor(response, levels = EFP_ORDER)]
shap_pct[, IGBP := factor(IGBP, levels = IGBP_ORDER)]

# ── 3) Theme ──────────────────────────────────────────────────────────────────
dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border     = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text       = element_text(colour = TEXT_COL, size = 8, face = "bold"),
    axis.text        = element_text(colour = AXIS_COL, size = 7.5),
    axis.title       = element_text(colour = AXIS_COL, size = 8.5),
    plot.tag         = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.title       = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle    = element_text(colour = AXIS_COL, size = 8),
    axis.text.x      = element_text(colour = AXIS_COL, size = 7, angle = 45, hjust = 1),
    legend.position  = "none"
  )

# ── 4) Create plot factory for each EFP ────────────────────────────────────────
make_efp_plot <- function(efp, tag_letter) {
  data <- shap_pct[response == efp, ]

  p <- ggplot(data, aes(x = IGBP, y = dist_pct, fill = IGBP)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4) +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    labs(
      tag = tag_letter,
      x = "IGBP Biome",
      y = "Disturbance SHAP (%)",
      title = efp
    ) +
    dark_theme

  p
}

# Generate plots for all 5 EFPs
plots <- lapply(seq_along(EFP_ORDER), function(i) {
  make_efp_plot(EFP_ORDER[i], letters[i])
})

# ── 5) Combine into single figure ────────────────────────────────────────────
fig_combined <- wrap_plots(plots, nrow = 1) +
  plot_annotation(
    title = "Disturbance SHAP Contribution by IGBP Biome",
    subtitle = "M04 (C+T+D) model | 24m window | Anomaly memory | % of total per-site SHAP explained by disturbance group",
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

# ── 6) Save figure ──────────────────────────────────────────────────────────
stem <- file.path(OUT_DIR, "fig_SHAP_disturbance_by_IGBP")
ggsave(paste0(stem, ".png"), fig_combined,
       width = 280, height = 90, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig_combined,
       width = 280, height = 90, units = "mm", bg = DARK_BG)

cat("\n=== Figure saved ===\n")
cat("PNG:", paste0(stem, ".png\n"))
cat("PDF:", paste0(stem, ".pdf\n"))

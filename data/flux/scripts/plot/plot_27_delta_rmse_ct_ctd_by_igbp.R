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

# ── 1) Load main dataset to get IGBP for each site ───────────────────────────────
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

# Get unique SITE_ID and IGBP
site_igbp <- unique(main_data[, .(SITE_ID, IGBP)])

# ── 2) Per-site RMSE from predictions (anomaly 24mbench) ────────────────────────
pred_file <- "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv"
preds <- fread(pred_file)

preds[, model_key := sub("_(12m|24m)_.*", "", model)]
preds[, window    := regmatches(model, regexpr("(12m|24m)", model))]
preds[, response  := sub(".*_(12m|24m)_", "", model)]

# Keep M03, M04 with 24m window
preds_sub <- preds[model_key %in% c("M03","M04") & window == "24m"]

site_rmse <- preds_sub[, .(
  rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))
), by = .(model_key, response, SITE_ID)]

# ── 3) Calculate Delta RMSE (M04 - M03) ────────────────────────────────────────
base <- site_rmse[model_key == "M03", .(SITE_ID, response, rmse_base = rmse)]
dist <- site_rmse[model_key == "M04", .(SITE_ID, response, rmse_dist = rmse)]
delta_rmse_data <- merge(base, dist, by = c("SITE_ID", "response"))
delta_rmse_data[, delta_rmse := rmse_dist - rmse_base]

# ── 4) Merge with IGBP ────────────────────────────────────────────────────────
delta_rmse_data <- merge(delta_rmse_data, site_igbp, by = "SITE_ID")
delta_rmse_data[, response := factor(response, levels = EFP_ORDER)]
delta_rmse_data[, IGBP := factor(IGBP, levels = IGBP_ORDER)]

# ── 5) Theme ──────────────────────────────────────────────────────────────────
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

# ── 6) Create plot factory for each EFP ────────────────────────────────────────
make_efp_plot <- function(efp, tag_letter) {
  data <- delta_rmse_data[response == efp, ]

  p <- ggplot(data, aes(x = IGBP, y = delta_rmse, fill = IGBP)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4, linetype = "dashed") +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    labs(
      tag = tag_letter,
      x = "IGBP Biome",
      y = expression(Delta*"RMSE  (C+T+D − C+T)"),
      title = efp
    ) +
    dark_theme

  p
}

# Generate plots for all 5 EFPs
plots <- lapply(seq_along(EFP_ORDER), function(i) {
  make_efp_plot(EFP_ORDER[i], letters[i])
})

# ── 7) Combine into single figure ────────────────────────────────────────────
fig_combined <- wrap_plots(plots, nrow = 1) +
  plot_annotation(
    title = "Delta RMSE by IGBP Biome: Climate+Traits vs Climate+Traits+Disturbance",
    subtitle = "M03 vs M04 (C+T vs C+T+D) | 24m window | Anomaly memory | negative dRMSE = D improved prediction",
    theme = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

# ── 8) Save figure ──────────────────────────────────────────────────────────
stem <- file.path(OUT_DIR, "fig_delta_RMSE_CT_vs_CTplusD_by_IGBP")
ggsave(paste0(stem, ".png"), fig_combined,
       width = 280, height = 90, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig_combined,
       width = 280, height = 90, units = "mm", bg = DARK_BG)

cat("\n=== Figure saved ===\n")
cat("PNG:", paste0(stem, ".png\n"))
cat("PDF:", paste0(stem, ".pdf\n"))

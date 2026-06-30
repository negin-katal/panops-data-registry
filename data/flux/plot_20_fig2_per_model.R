library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- file.path("plots/manuscript_candidates", "fig2_per_model")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

COL_BASE <- "#22D4EB"   # cyan  — without D
COL_DIST <- "#E8257A"   # pink  — with D
DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

TIER_LEVELS <- c("All sites", "Low (<5%)", "Medium (5-12%)", "High (>12%)")

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
EFP_UNITS <- c(
  GPPsat = expression(GPP[sat]~~(mu*mol~m^{-2}~s^{-1})),
  NEPmax = expression(NEP[max]~~(mu*mol~m^{-2}~s^{-1})),
  ETmax  = expression(ET[max]~~(mm~d^{-1})),
  uWUE  = expression(uWUE~~(g~C~mm^{-1})),
  WUE   = expression(WUE~~(g~C~mm^{-1}))
)

PAIRS <- list(
  list(base = "M01", dist = "M02", label = "C vs C+D",
       fname = "C_vs_CplusD"),
  list(base = "M03", dist = "M04", label = "C+T vs C+T+D",
       fname = "CT_vs_CTplusD"),
  list(base = "M05", dist = "M06", label = "C+M vs C+D+M",
       fname = "CM_vs_CDplusM"),
  list(base = "M07", dist = "M08", label = "C+T+M vs C+T+D+M",
       fname = "CTM_vs_CTDplusM")
)

PANEL_DEFS <- list(
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_predictions_LOSO.csv",
       win = "12m", mem = "Anomaly"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v2/RF_predictions_LOSO.csv",
       win = "24m", mem = "Anomaly"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_v2/RF_predictions_LOSO.csv",
       win = "12m", mem = "Raw-lag"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench_v2/RF_predictions_LOSO.csv",
       win = "24m", mem = "Raw-lag")
)

# ── 1) Site deadwood tier ──────────────────────────────────────────────────────
main <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv")
site_tier <- main[, .(dw_mean = mean(deadwood_mean_pct_500m, na.rm = TRUE)), by = SITE_ID]
site_tier[, tier := factor(fcase(
  dw_mean <  5, "Low (<5%)",
  dw_mean < 12, "Medium (5-12%)",
  default =     "High (>12%)"
), levels = TIER_LEVELS)]

# ── 2) Load all predictions → per-site RMSE ───────────────────────────────────
load_site_rmse <- function(pred_file, win_label, mem_label) {
  dt <- fread(pred_file)
  dt <- dt[grepl(paste0("_", win_label, "_"), model)]
  dt[, model_key := sub(paste0("_(", win_label, ")_.*"), "", model)]
  dt[, response  := sub(paste0(".*_", win_label, "_"),   "", model)]
  dt[, panel     := paste0(mem_label, " / ", win_label)]
  dt[model_key %in% c("M01","M02","M03","M04","M05","M06","M07","M08"),
    .(site_rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))),
    by = .(model_key, response, SITE_ID, panel)]
}

all_rmse <- rbindlist(lapply(PANEL_DEFS, function(p)
  load_site_rmse(p$file, p$win, p$mem)))

all_rmse <- merge(all_rmse, site_tier, by = "SITE_ID")

# Add "All sites" group by duplicating with tier = "All sites"
all_sites_copy <- copy(all_rmse)
all_sites_copy[, tier := "All sites"]
all_rmse <- rbindlist(list(all_sites_copy, all_rmse))

all_rmse[, tier     := factor(tier, levels = TIER_LEVELS)]
all_rmse[, response := factor(response, levels = EFP_ORDER)]
all_rmse[, panel    := factor(panel,
  levels = c("Anomaly / 12m","Anomaly / 24m","Raw-lag / 12m","Raw-lag / 24m"))]

# ── 3) Theme ──────────────────────────────────────────────────────────────────
dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background   = element_rect(fill = DARK_BG,  colour = NA),
    panel.background  = element_rect(fill = PANEL_BG, colour = NA),
    panel.border      = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major  = element_line(colour = GRID_COL, linewidth = 0.25),
    panel.grid.minor  = element_blank(),
    strip.background  = element_rect(fill = "#1A1A1A", colour = GRID_COL),
    strip.text        = element_text(colour = TEXT_COL, size = 8, face = "bold"),
    axis.text         = element_text(colour = AXIS_COL, size = 7.5),
    axis.title        = element_text(colour = AXIS_COL, size = 8.5),
    plot.tag          = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.title        = element_text(colour = TEXT_COL, size = 10, face = "bold"),
    plot.subtitle     = element_text(colour = AXIS_COL, size = 8),
    legend.background = element_rect(fill = NA),
    legend.key        = element_rect(fill = NA, colour = NA),
    legend.text       = element_text(colour = TEXT_COL, size = 9),
    legend.key.size   = unit(0.5, "cm")
  )

# ── 4) Panel factory: one EFP row ─────────────────────────────────────────────
make_efp_row <- function(pr, resp, tag, show_legend = FALSE, show_x = TRUE) {
  sub <- all_rmse[model_key %in% c(pr$base, pr$dist) & response == resp]
  sub[, model_type := factor(
    ifelse(model_key == pr$base, "Without D", "With D"),
    levels = c("Without D", "With D")
  )]

  p <- ggplot(sub,
    aes(x = tier, y = site_rmse,
        fill = model_type,
        group = interaction(tier, model_type))) +
    geom_violin(trim = TRUE, scale = "width", width = 0.7,
                colour = NA, alpha = 0.85,
                position = position_dodge(width = 0.8)) +
    geom_boxplot(width = 0.12, outlier.shape = NA, colour = "white",
                 fill = NA, linewidth = 0.35,
                 position = position_dodge(width = 0.8)) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 0.9,
                 position = position_dodge(width = 0.8)) +
    scale_fill_manual(
      values = c("Without D" = COL_BASE, "With D" = COL_DIST),
      name   = NULL
    ) +
    facet_wrap(~panel, nrow = 1) +
    labs(
      tag = tag,
      x   = if (show_x) "Deadwood tier  (deadwood_mean_pct_500m)" else NULL,
      y   = EFP_UNITS[[resp]]
    ) +
    dark_theme +
    theme(
      legend.position  = if (show_legend) "bottom" else "none",
      legend.direction = "horizontal",
      axis.text.x = if (show_x)
        element_text(colour = AXIS_COL, size = 7.5, angle = 12, hjust = 1)
      else element_blank(),
      axis.ticks.x = if (show_x) element_line() else element_blank()
    )

  if (show_legend) {
    p <- p + guides(fill = guide_legend(
      override.aes = list(alpha = 1, colour = NA), title = NULL
    ))
  }
  p
}

# ── 5) Build and save one figure per comparison pair ──────────────────────────
for (pr in PAIRS) {
  cat("Building:", pr$label, "\n")

  p1 <- make_efp_row(pr, "GPPsat", "a", show_legend = FALSE, show_x = FALSE)
  p2 <- make_efp_row(pr, "NEPmax", "b", show_legend = FALSE, show_x = FALSE)
  p3 <- make_efp_row(pr, "ETmax",  "c", show_legend = FALSE, show_x = FALSE)
  p4 <- make_efp_row(pr, "uWUE",  "d", show_legend = FALSE, show_x = FALSE)
  p5 <- make_efp_row(pr, "WUE",   "e", show_legend = TRUE,  show_x = TRUE)

  fig <- (p1 / p2 / p3 / p4 / p5) +
    plot_layout(heights = c(1, 1, 1, 1, 1.3)) +
    plot_annotation(
      title    = paste0("Per-site RMSE by deadwood tier  |  ", pr$label),
      subtitle = "Cyan = without D | Pink = with D | Leave-One-Site-Out | 166 sites",
      theme    = theme(
        plot.background = element_rect(fill = DARK_BG, colour = NA),
        plot.title      = element_text(colour = TEXT_COL, size = 11, face = "bold"),
        plot.subtitle   = element_text(colour = AXIS_COL, size = 8.5)
      )
    ) &
    theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

  stem <- file.path(OUT_DIR, paste0("fig2_threshold_", pr$fname))
  ggsave(paste0(stem, ".png"), fig,
         width = 220, height = 260, units = "mm", dpi = 300, bg = DARK_BG)
  ggsave(paste0(stem, ".pdf"), fig,
         width = 220, height = 260, units = "mm", bg = DARK_BG)
  cat("  Saved:", stem, "\n")
}

cat("\n=== All 4 figures saved to", OUT_DIR, "===\n")

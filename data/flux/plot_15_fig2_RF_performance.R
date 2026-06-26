library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- "plots/manuscript_candidates"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ── 0) Config ─────────────────────────────────────────────────────────────────
# Colours matching plot_07_R2_24mbench.R
COL_BASE <- "#22D4EB"   # cyan  — without disturbance
COL_DIST <- "#E8257A"   # hot pink — with disturbance
DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

# The 4 "add-D" comparison pairs:
#   base model (cyan) vs base + disturbance (pink)
PAIRS <- list(
  list(base = "M01", dist = "M02", label = "C vs C+D"),
  list(base = "M03", dist = "M04", label = "C+T vs\nC+T+D"),
  list(base = "M05", dist = "M06", label = "C+M vs\nC+D+M"),
  list(base = "M07", dist = "M08", label = "C+T+M vs\nC+T+D+M")
)

EFP_UNITS <- c(
  GPPsat = expression(GPP[sat]~~(mu*mol~m^{-2}~s^{-1})),
  NEPmax = expression(NEP[max]~~(mu*mol~m^{-2}~s^{-1})),
  ETmax  = expression(ET[max]~~(mm~d^{-1})),
  uWUE   = expression(uWUE~~(g~C~mm^{-1}))
)

PANEL_DEFS <- list(
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_predictions_LOSO.csv",
       win = "12m", mem = "Anomaly"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench/RF_predictions_LOSO.csv",
       win = "24m", mem = "Anomaly"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench/RF_predictions_LOSO.csv",
       win = "12m", mem = "Raw-lag"),
  list(file = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_24mbench/RF_predictions_LOSO.csv",
       win = "24m", mem = "Raw-lag")
)

# ── 1) Load predictions → per-site RMSE ───────────────────────────────────────
load_site_metrics <- function(pred_file, win_label, mem_label) {
  dt <- fread(pred_file)
  dt <- dt[grepl(paste0("^M0[1-8]_", win_label, "_"), model)]
  dt[, model_key := sub(paste0("_", win_label, "_.*"), "", model)]
  dt[, response  := sub(paste0(".*_", win_label, "_"), "", model)]

  site_dt <- dt[, .(
    site_rmse = sqrt(mean((predicted - observed)^2, na.rm = TRUE))
  ), by = .(model_key, response, SITE_ID)]

  site_dt[, window := win_label]
  site_dt[, memory := mem_label]
  site_dt
}

all_metrics <- rbindlist(lapply(PANEL_DEFS, function(p)
  load_site_metrics(p$file, p$win, p$mem)))

# ── 2) Reshape into paired format ─────────────────────────────────────────────
# For each pair: keep both base and dist model, tag them
pair_list <- lapply(PAIRS, function(pr) {
  sub <- all_metrics[model_key %in% c(pr$base, pr$dist)]
  sub[, pair_label := pr$label]
  sub[, model_type := ifelse(model_key == pr$base, "Without D", "With D")]
  sub
})
paired <- rbindlist(pair_list)

paired[, pair_label := factor(pair_label,
  levels = sapply(PAIRS, `[[`, "label"))]
paired[, model_type := factor(model_type, levels = c("Without D", "With D"))]
paired[, panel := factor(paste0(memory, " / ", window),
  levels = c("Anomaly / 12m","Anomaly / 24m","Raw-lag / 12m","Raw-lag / 24m"))]

cat("Paired rows:", nrow(paired), "\n")

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
    axis.text.x       = element_text(colour = AXIS_COL, size = 7),
    axis.title        = element_text(colour = AXIS_COL, size = 8.5),
    legend.position   = "none",
    plot.tag          = element_text(colour = TEXT_COL, face = "bold", size = 10),
    plot.tag.position = c(0.01, 0.98)
  )

# ── 4) Panel factory ──────────────────────────────────────────────────────────
make_panel <- function(resp, ylab, tag, show_legend = FALSE) {
  sub <- paired[response == resp]

  p <- ggplot(sub,
              aes(x = pair_label, y = site_rmse,
                  fill = model_type, group = interaction(pair_label, model_type))) +
    geom_violin(trim = TRUE, scale = "width", width = 0.75,
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
    labs(tag = tag, x = NULL, y = ylab) +
    dark_theme

  if (show_legend) {
    p <- p + theme(
      legend.position   = "bottom",
      legend.direction  = "horizontal",
      legend.text       = element_text(colour = TEXT_COL, size = 9),
      legend.key        = element_rect(fill = NA, colour = NA),
      legend.background = element_rect(fill = NA),
      legend.key.size   = unit(0.5, "cm")
    ) + guides(fill = guide_legend(
      override.aes = list(alpha = 1, colour = NA),
      title = NULL
    ))
  }
  p
}

# ── 5) Build figure ───────────────────────────────────────────────────────────
p_gpp  <- make_panel("GPPsat", EFP_UNITS[["GPPsat"]], "a")
p_nep  <- make_panel("NEPmax", EFP_UNITS[["NEPmax"]], "b")
p_et   <- make_panel("ETmax",  EFP_UNITS[["ETmax"]],  "c")
p_uwue <- make_panel("uWUE",   EFP_UNITS[["uWUE"]],   "d", show_legend = TRUE)

fig2 <- (p_gpp / p_nep / p_et / p_uwue) +
  plot_annotation(
    title    = "Effect of adding deadwood disturbance on per-site RMSE",
    subtitle = "Paired violin: cyan = without D, pink = with D | Leave-One-Site-Out cross-validation | 166 sites",
    theme    = theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      plot.title    = element_text(colour = TEXT_COL, size = 11, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8.5)
    )
  ) &
  theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

# ── 6) Save combined figure ───────────────────────────────────────────────────
stem <- file.path(OUT_DIR, "fig2_RF_RMSE_disturbance_effect")

ggsave(paste0(stem, ".png"), fig2,
       width = 220, height = 260, units = "mm", dpi = 300, bg = DARK_BG)
ggsave(paste0(stem, ".pdf"), fig2,
       width = 220, height = 260, units = "mm", bg = DARK_BG)

cat("\n=== Combined figure saved ===\n")

# ── 7) Save individual panels per EFP ─────────────────────────────────────────
panel_dir <- file.path(OUT_DIR, "fig2_panels")
dir.create(panel_dir, showWarnings = FALSE)

efp_list <- list(
  list(resp = "GPPsat", ylab = EFP_UNITS[["GPPsat"]], tag = "a"),
  list(resp = "NEPmax", ylab = EFP_UNITS[["NEPmax"]], tag = "b"),
  list(resp = "ETmax",  ylab = EFP_UNITS[["ETmax"]],  tag = "c"),
  list(resp = "uWUE",   ylab = EFP_UNITS[["uWUE"]],   tag = "d")
)

for (efp in efp_list) {
  p <- make_panel(efp$resp, efp$ylab, efp$tag, show_legend = TRUE)
  p <- p + plot_annotation(
    theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA))
  )
  fstem <- file.path(panel_dir, paste0("fig2_", efp$resp, "_RMSE_disturbance_effect"))
  ggsave(paste0(fstem, ".png"), p,
         width = 220, height = 70, units = "mm", dpi = 300, bg = DARK_BG)
  ggsave(paste0(fstem, ".pdf"), p,
         width = 220, height = 70, units = "mm", bg = DARK_BG)
  cat("Saved:", efp$resp, "\n")
}

cat("\n=== Individual panels saved to", panel_dir, "===\n")

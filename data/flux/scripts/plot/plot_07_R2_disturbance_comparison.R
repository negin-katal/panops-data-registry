library(data.table)
library(ggplot2)

# ============================================================
# PLOT 07: R² bar comparison — with vs without disturbance
#          Dark theme matching the EGU slide style.
#
# One plot per model-pair comparison × memory type × window:
#   M01 vs M02  (C vs C+D)
#   M03 vs M04  (C+T vs C+T+D)
#   M05 vs M06  (C+M vs C+D+M)
#   M07 vs M08  (C+T+M vs C+T+D+M)
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir <- "plots/disturbance_effects"

metrics_sources <- list(
  anomaly = "derived_tables/outputs_afterEGU_results/RF_outputs_fixed_v2/RF_metrics_LOSO.csv",
  rawlag  = "derived_tables/outputs_afterEGU_results/RF_outputs_rawmem_fixed_v2/RF_metrics_LOSO.csv"
)

# ============================================================
# Colour / style constants (match screenshot)
# ============================================================

BG_COL     <- "#0D0D0D"    # near-black background
COL_BASE   <- "#22D4EB"    # cyan  — model without disturbance
COL_DIST   <- "#E8257A"    # hot pink — model with disturbance
COL_PCT      <- "#39FF14"    # neon green — improvement
COL_PCT_BAD  <- "#FF3B30"    # red — performance got worse
COL_PCT_FLAT <- "#FFFFFF"    # white — no change
COL_TEXT   <- "#FFFFFF"    # white — bar value labels
COL_AXIS   <- "#CCCCCC"    # light grey — axis text / grid

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE")

# Model pairs: list(base = "Mxx", dist = "Myy", label_base, label_dist)
model_pairs <- list(
  list(base = "M01", dist = "M02",
       lbl_base = "C",     lbl_dist = "C + D"),
  list(base = "M03", dist = "M04",
       lbl_base = "C + T", lbl_dist = "C + T + D"),
  list(base = "M05", dist = "M06",
       lbl_base = "C + M", lbl_dist = "C + D + M"),
  list(base = "M07", dist = "M08",
       lbl_base = "C + T + M", lbl_dist = "C + T + D + M")
)

mem_title <- c(anomaly = "anomaly memory", rawlag = "raw-lag memory")

# ============================================================
# Plot factory
# ============================================================

make_r2_bar <- function(dt_pair, pair, window_str, mem_type) {

  dt_pair[, EFP := factor(EFP, levels = EFP_ORDER)]

  # % improvement
  wide <- dcast(dt_pair, EFP ~ type, value.var = "R2")
  wide[, pct_imp := round((dist - base) / abs(base) * 100)]

  # merge back for annotation positions
  dt_pair <- merge(dt_pair,
                   wide[, .(EFP, pct_imp, dist_r2 = dist)],
                   by = "EFP")

  # y upper limit: leave room for % label
  y_max <- max(dt_pair$R2, na.rm = TRUE) * 1.28

  title_str <- sprintf(
    "R² comparison: %s vs %s   [%s window, %s]",
    pair$lbl_base, pair$lbl_dist, window_str, mem_title[mem_type]
  )

  # annotation: one row per EFP (placed above the taller bar)
  ann_dt <- unique(dt_pair[, .(EFP, pct_imp, dist_r2)])
  ann_dt[, label := fcase(
    pct_imp > 0, sprintf("+%d%%", pct_imp),
    pct_imp < 0, sprintf("%d%%",  pct_imp),
    default     = "0%"
  )]
  ann_dt[, label_colour := fcase(
    pct_imp > 0, COL_PCT,
    pct_imp < 0, COL_PCT_BAD,
    default     = COL_PCT_FLAT
  )]
  ann_dt[, ypos := dist_r2 + (y_max - dist_r2) * 0.25]

  ggplot(dt_pair,
         aes(x = EFP, y = R2, fill = type, group = type)) +
    geom_col(position = position_dodge(width = 0.6),
             width = 0.55, colour = NA) +
    # R² value labels inside bars
    geom_text(aes(label = sprintf("%.2f", R2),
                  y     = R2 - 0.012),
              position  = position_dodge(width = 0.6),
              vjust = 1, size = 3.6, colour = COL_TEXT,
              fontface  = "bold") +
    # % improvement above each EFP group (green=better, red=worse, white=flat)
    geom_text(data = ann_dt,
              aes(x = EFP, y = ypos, label = label, colour = label_colour),
              inherit.aes = FALSE,
              size = 5, fontface = "bold") +
    scale_colour_identity(guide = "none") +
    scale_fill_manual(
      values = c(base = COL_BASE, dist = COL_DIST),
      labels = c(base = pair$lbl_base, dist = pair$lbl_dist),
      name   = NULL
    ) +
    scale_y_continuous(
      limits = c(0, y_max),
      breaks = seq(0, 1, 0.2),
      expand = expansion(mult = c(0, 0))
    ) +
    labs(title = title_str, x = NULL, y = expression(R^2)) +
    theme_void(base_size = 12) +
    theme(
      plot.background   = element_rect(fill = BG_COL, colour = NA),
      panel.background  = element_rect(fill = BG_COL, colour = NA),
      legend.background = element_rect(fill = "#1A1A1A", colour = COL_AXIS,
                                       linewidth = 0.4),
      legend.key        = element_rect(fill = NA, colour = NA),
      legend.key.size   = unit(0.5, "cm"),
      legend.text       = element_text(colour = COL_TEXT, size = 10),
      legend.position   = "top",
      legend.direction  = "horizontal",
      legend.margin     = margin(4, 8, 4, 8),
      plot.title        = element_text(colour = COL_TEXT, face = "bold",
                                       size = 11, hjust = 0.5,
                                       margin = margin(b = 10)),
      axis.title.y      = element_text(colour = COL_AXIS, size = 11,
                                       angle = 90, margin = margin(r = 6)),
      axis.text.x       = element_text(colour = COL_AXIS, size = 11,
                                       margin = margin(t = 4)),
      axis.text.y       = element_text(colour = COL_AXIS, size = 9,
                                       margin = margin(r = 4)),
      axis.line.x       = element_line(colour = COL_AXIS, linewidth = 0.4),
      panel.grid.major.y = element_line(colour = "#333333", linewidth = 0.3),
      panel.grid.minor.y = element_blank(),
      panel.grid.major.x = element_blank(),
      plot.margin       = margin(12, 16, 10, 16)
    )
}

# ============================================================
# Loop: memory type × model pair × window
# ============================================================

for (mem_type in names(metrics_sources)) {

  mfile <- metrics_sources[[mem_type]]
  if (!file.exists(mfile)) {
    cat("Skipping", mem_type, "— file not found\n"); next
  }

  met <- fread(mfile)
  met[, window := fifelse(grepl("_24m_", model), "24m", "12m")]
  met[, model_base := sub("_(12|24)m.*", "", model)]

  for (win in c("12m", "24m")) {
    met_w <- met[window == win]

    for (pair in model_pairs) {

      sub_base <- met_w[model_base == pair$base,
                        .(EFP = response, R2, type = "base")]
      sub_dist <- met_w[model_base == pair$dist,
                        .(EFP = response, R2, type = "dist")]

      if (nrow(sub_base) == 0 || nrow(sub_dist) == 0) next

      dt_pair <- rbind(sub_base, sub_dist)
      dt_pair[, type := factor(type, levels = c("base", "dist"))]

      p <- make_r2_bar(dt_pair, pair, win, mem_type)

      fname <- sprintf("R2_comparison_%s_vs_%s_%s_%s",
                       pair$base, pair$dist, win, mem_type)
      ggsave(file.path(out_dir, paste0(fname, ".png")),
             p, width = 7, height = 5, dpi = 200, bg = BG_COL)
      ggsave(file.path(out_dir, paste0(fname, ".pdf")),
             p, width = 7, height = 5, bg = BG_COL)
      cat("Saved:", fname, "\n")
    }
  }
}

cat("\n=== plot_07 DONE ===\n")

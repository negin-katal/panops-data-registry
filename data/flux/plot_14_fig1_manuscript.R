library(ggplot2)
library(patchwork)
library(maps)
library(RColorBrewer)
library(scales)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

# ── 0) Config ─────────────────────────────────────────────────────────────────
EFP_FILE <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
OUT_DIR  <- "plots/manuscript_candidates"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")

IGBP_COL <- c(
  ENF = "#1F6B3A", EBF = "#33A14A", DNF = "#7BC87E", DBF = "#B2DF8A",
  MF  = "#FDBF6F", CSH = "#E5820B", OSH = "#D4A017", WSA = "#C4A85C",
  SAV = "#E8D44D", WET = "#4DAECC"
)

EFP_LABELS <- c(
  GPPsat = expression(GPP[sat]~~(mu*mol~m^{-2}~s^{-1})),
  NEPmax = expression(NEP[max]~~(mu*mol~m^{-2}~s^{-1})),
  ETmax  = expression(ET[max]~~(mm~d^{-1})),
  uWUE   = expression(uWUE~~(g~C~mm^{-1}))
)

# ── 1) Load data ──────────────────────────────────────────────────────────────
dt <- read.csv(EFP_FILE, check.names = FALSE)
dt <- dt[, c("SITE_ID","YEAR","IGBP","LOCATION_LAT","LOCATION_LONG",
             "GPPsat","NEPmax","ETmax","uWUE")]

# Clip extreme outliers (>99th percentile per EFP) for display
clip99 <- function(x) { q <- quantile(x, 0.99, na.rm=TRUE); ifelse(x > q, NA, x) }
dt$GPPsat <- clip99(dt$GPPsat)
dt$NEPmax <- clip99(dt$NEPmax)
dt$ETmax  <- clip99(dt$ETmax)
dt$uWUE   <- clip99(dt$uWUE)

dt$IGBP <- factor(dt$IGBP, levels = IGBP_ORDER)

# One row per site for map
sites <- dt[!duplicated(dt$SITE_ID), c("SITE_ID","IGBP","LOCATION_LAT","LOCATION_LONG")]
sites <- sites[!is.na(sites$LOCATION_LAT), ]

cat(sprintf("Sites for map: %d\n", nrow(sites)))
cat(sprintf("Site-years for EFP panels: %d\n", nrow(dt)))

# ── 2) World map panel ────────────────────────────────────────────────────────
world <- map_data("world")

p_map <- ggplot() +
  geom_polygon(data = world,
               aes(x = long, y = lat, group = group),
               fill = "#1C2733", colour = "#2E3F50", linewidth = 0.15) +
  geom_point(data = sites,
             aes(x = LOCATION_LONG, y = LOCATION_LAT, fill = IGBP),
             shape = 21, size = 2.4, colour = "white", stroke = 0.3) +
  scale_fill_manual(values = IGBP_COL, name = "IGBP", drop = FALSE,
                    guide = guide_legend(nrow = 2, override.aes = list(size = 3))) +
  coord_fixed(1.3, xlim = c(-170, 175), ylim = c(-55, 75), expand = FALSE) +
  labs(tag = "a", x = NULL, y = NULL) +
  theme_void(base_size = 9) +
  theme(
    plot.background    = element_rect(fill = "#0D1117", colour = NA),
    panel.background   = element_rect(fill = "#0D1117", colour = NA),
    legend.position    = "bottom",
    legend.text        = element_text(colour = "#C9D1D9", size = 7.5),
    legend.title       = element_text(colour = "#C9D1D9", size = 8, face = "bold"),
    legend.key         = element_rect(fill = NA, colour = NA),
    legend.background  = element_rect(fill = NA, colour = NA),
    plot.tag           = element_text(colour = "#C9D1D9", face = "bold", size = 10),
    plot.tag.position  = c(0.01, 0.97)
  )

# ── 3) EFP violin panels ──────────────────────────────────────────────────────
make_violin <- function(efp_col, tag_label) {

  sub <- dt[!is.na(dt[[efp_col]]) & !is.na(dt$IGBP), ]

  # Median per IGBP for ordering (same as in main paper)
  med_order <- tapply(sub[[efp_col]], sub$IGBP, median, na.rm=TRUE)
  # Keep IGBP_ORDER but only those present
  present <- IGBP_ORDER[IGBP_ORDER %in% levels(droplevels(sub$IGBP))]

  sub$IGBP <- factor(sub$IGBP, levels = rev(present))   # flip for horizontal

  ggplot(sub, aes(x = IGBP, y = .data[[efp_col]], fill = IGBP)) +
    geom_violin(trim = TRUE, scale = "width", width = 0.85,
                colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA,
                 colour = "white", fill = NA, linewidth = 0.4) +
    stat_summary(fun = median, geom = "point",
                 colour = "white", size = 1.2) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    scale_y_continuous(labels = number_format(accuracy = 0.1)) +
    coord_flip() +
    labs(tag = tag_label, x = NULL, y = EFP_LABELS[[efp_col]]) +
    theme_bw(base_size = 9) +
    theme(
      plot.background  = element_rect(fill = "#0D1117", colour = NA),
      panel.background = element_rect(fill = "#131B24", colour = NA),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank(),
      panel.grid.major.x = element_line(colour = "#2E3F50", linewidth = 0.3),
      panel.border       = element_rect(colour = "#2E3F50", fill = NA),
      axis.text          = element_text(colour = "#C9D1D9", size = 8),
      axis.title.x       = element_text(colour = "#9CA3AF", size = 8.5),
      plot.tag           = element_text(colour = "#C9D1D9", face = "bold", size = 10),
      plot.tag.position  = c(0.01, 0.97)
    )
}

p_gpp  <- make_violin("GPPsat", "b")
p_nep  <- make_violin("NEPmax", "c")
p_et   <- make_violin("ETmax",  "d")
p_uwue <- make_violin("uWUE",   "e")

# ── 4) Compose layout ─────────────────────────────────────────────────────────
# Map on top spanning full width; 4 EFP violins in 2x2 grid below
layout <- "
AAAA
BBCC
DDEE
"

fig1 <- p_map + p_gpp + p_nep + p_et + p_uwue +
  plot_layout(design = layout, heights = c(1.6, 1, 1)) &
  theme(plot.background = element_rect(fill = "#0D1117", colour = NA))

# ── 5) Save ───────────────────────────────────────────────────────────────────
stem <- file.path(OUT_DIR, "fig1_site_map_EFP_distributions")

ggsave(paste0(stem, ".png"), fig1,
       width = 180, height = 200, units = "mm",
       dpi = 300, bg = "#0D1117")

ggsave(paste0(stem, ".pdf"), fig1,
       width = 180, height = 200, units = "mm",
       bg = "#0D1117")

cat("\n=== Fig 1 saved ===\n")
cat("PNG:", paste0(stem, ".png"), "\n")
cat("PDF:", paste0(stem, ".pdf"), "\n")

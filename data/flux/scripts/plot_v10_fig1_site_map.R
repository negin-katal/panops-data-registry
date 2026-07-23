#!/usr/bin/env Rscript
# ============================================================================
# V10: Fig 1 — site map + EFP distributions by IGBP (style = fig1 reference)
#   a) world map of V10 sites coloured by IGBP
#   b-f) horizontal violins of GPPsat/NEPmax/ETmax/uWUE/WUE by IGBP class
# ============================================================================

library(ggplot2)
library(patchwork)
library(maps)
library(scales)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript plot_v10_fig1_site_map.R <dataset_type>")
dataset_type <- args[1]

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 FIG1 SITE MAP: %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep = "")

if (dataset_type == "filtered") {
  harm_file <- "derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
  out_dir   <- "plots/V10/sites_with_high_Tcover"
} else if (dataset_type == "all_sites") {
  harm_file <- "derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_GPPsat_harmonized.csv"
  out_dir   <- "plots/V10/all_sites"
} else stop("Invalid dataset_type")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

EFP_FILE <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

IGBP_ORDER <- c("ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET")
IGBP_COL <- c(ENF="#1F6B3A", EBF="#33A14A", DNF="#7BC87E", DBF="#B2DF8A",
              MF="#FDBF6F", CSH="#E5820B", OSH="#D4A017", WSA="#C4A85C",
              SAV="#E8D44D", WET="#4DAECC")
EFP_LABELS <- c(
  GPPsat = expression(GPP[sat]~~(mu*mol~m^{-2}~s^{-1})),
  NEPmax = expression(NEP[max]~~(mu*mol~m^{-2}~s^{-1})),
  ETmax  = expression(ET[max]~~(mm~d^{-1})),
  uWUE   = expression(uWUE~~(g~C~mm^{-1})),
  WUE    = expression(WUE~~(g~C~mm^{-1}))
)

# ── V10 site list ────────────────────────────────────────────
v10_sites <- unique(read.csv(harm_file)$SITE_ID)

# ── EFP data (filter to V10 sites) ───────────────────────────
dt <- read.csv(EFP_FILE, check.names = FALSE)
dt <- dt[, c("SITE_ID","YEAR","IGBP","LOCATION_LAT","LOCATION_LONG",
             "GPPsat","NEPmax","ETmax","uWUE","WUE")]
dt <- dt[dt$SITE_ID %in% v10_sites, ]

clip99 <- function(x) { q <- quantile(x, 0.99, na.rm = TRUE); ifelse(x > q, NA, x) }
for (e in c("GPPsat","NEPmax","ETmax","uWUE","WUE")) dt[[e]] <- clip99(dt[[e]])
dt$IGBP <- factor(dt$IGBP, levels = IGBP_ORDER)

sites <- dt[!duplicated(dt$SITE_ID), c("SITE_ID","IGBP","LOCATION_LAT","LOCATION_LONG")]
sites <- sites[!is.na(sites$LOCATION_LAT), ]
cat(sprintf("Sites for map: %d | site-years for violins: %d\n", nrow(sites), nrow(dt)))

# ── map panel ────────────────────────────────────────────────
world <- map_data("world")
p_map <- ggplot() +
  geom_polygon(data = world, aes(x = long, y = lat, group = group),
               fill = "#1C2733", colour = "#2E3F50", linewidth = 0.15) +
  geom_point(data = sites, aes(x = LOCATION_LONG, y = LOCATION_LAT, fill = IGBP),
             shape = 21, size = 2.4, colour = "white", stroke = 0.3) +
  scale_fill_manual(values = IGBP_COL, name = "IGBP", drop = FALSE,
                    guide = guide_legend(nrow = 2, override.aes = list(size = 3))) +
  coord_fixed(1.3, xlim = c(-170, 175), ylim = c(-55, 75), expand = FALSE) +
  labs(tag = "a", x = NULL, y = NULL) +
  theme_void(base_size = 9) +
  theme(
    plot.background = element_rect(fill = "#0D1117", colour = NA),
    panel.background = element_rect(fill = "#0D1117", colour = NA),
    legend.position = "bottom",
    legend.text = element_text(colour = "#C9D1D9", size = 7.5),
    legend.title = element_text(colour = "#C9D1D9", size = 8, face = "bold"),
    legend.key = element_rect(fill = NA, colour = NA),
    legend.background = element_rect(fill = NA, colour = NA),
    plot.tag = element_text(colour = "#C9D1D9", face = "bold", size = 10),
    plot.tag.position = c(0.01, 0.97)
  )

# ── violin panels ────────────────────────────────────────────
make_violin <- function(efp_col, tag_label, acc = 0.1, nbrk = 4) {
  sub <- dt[!is.na(dt[[efp_col]]) & !is.na(dt$IGBP), ]
  present <- IGBP_ORDER[IGBP_ORDER %in% levels(droplevels(sub$IGBP))]
  sub$IGBP <- factor(sub$IGBP, levels = rev(present))
  ggplot(sub, aes(x = IGBP, y = .data[[efp_col]], fill = IGBP)) +
    geom_violin(trim = TRUE, scale = "width", width = 0.85, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.4) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    scale_fill_manual(values = IGBP_COL, guide = "none") +
    scale_y_continuous(breaks = breaks_pretty(n = nbrk),
                       labels = number_format(accuracy = acc)) +
    coord_flip() +
    labs(tag = tag_label, x = NULL, y = EFP_LABELS[[efp_col]]) +
    theme_bw(base_size = 9) +
    theme(
      plot.background = element_rect(fill = "#0D1117", colour = NA),
      panel.background = element_rect(fill = "#131B24", colour = NA),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(colour = "#2E3F50", linewidth = 0.3),
      panel.border = element_rect(colour = "#2E3F50", fill = NA),
      axis.text.y = element_text(colour = "#C9D1D9", size = 8),
      axis.text.x = element_text(colour = "#C9D1D9", size = 6.5),
      axis.title.x = element_text(colour = "#9CA3AF", size = 8.5),
      plot.tag = element_text(colour = "#C9D1D9", face = "bold", size = 10),
      plot.tag.position = c(0.01, 0.97)
    )
}

p_gpp  <- make_violin("GPPsat", "b", acc = 1,   nbrk = 3)
p_nep  <- make_violin("NEPmax", "c", acc = 1,   nbrk = 3)
p_et   <- make_violin("ETmax",  "d", acc = 0.1, nbrk = 3)
p_uwue <- make_violin("uWUE",   "e", acc = 1,   nbrk = 4)
p_wue  <- make_violin("WUE",    "f", acc = 1,   nbrk = 4)

layout <- "
AAAAA
BCDEF
"
fig1 <- p_map + p_gpp + p_nep + p_et + p_uwue + p_wue +
  plot_layout(design = layout, heights = c(1.4, 1)) &
  theme(plot.background = element_rect(fill = "#0D1117", colour = NA))

stem <- file.path(out_dir, "fig1_site_map_EFP_distributions")
ggsave(paste0(stem, ".png"), fig1, width = 180, height = 200, units = "mm", dpi = 300, bg = "#0D1117")
ggsave(paste0(stem, ".pdf"), fig1, width = 180, height = 200, units = "mm", bg = "#0D1117")
cat("\n=== V10 Fig 1 saved ===\n")
cat("PNG:", paste0(stem, ".png"), "\n")

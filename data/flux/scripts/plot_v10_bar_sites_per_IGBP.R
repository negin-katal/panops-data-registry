#!/usr/bin/env Rscript
# ============================================================================
# V10 Plot: Bar chart - Number of sites per IGBP class
# Similar to: plots/disturbance_effects/bar_sites_per_IGBP.png
# ============================================================================

library(data.table)
library(ggplot2)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_dir <- "plots/V10"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# IGBP color scheme
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

# ============================================================
# Load v10 harmonized data to get IGBP info per site
# ============================================================

cat("Loading V10 data...\n")

# Load main data to get IGBP info
model_file <- 'derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv'
df_main <- fread(model_file, select = c('SITE_ID', 'IGBP'))

# Load v10 harmonized data to get sites used
df_b1 <- fread('derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv')
v10_sites <- unique(df_b1$SITE_ID)

# Get unique sites with their IGBP (only v10 sites)
site_dt <- df_main[SITE_ID %in% v10_sites][, .(IGBP = first(IGBP)), by = SITE_ID]

cat(sprintf("Total sites: %d\n", nrow(site_dt)))

# Factor IGBP in frequency order for bar chart
igbp_freq <- site_dt[, .N, by = IGBP][order(-N), IGBP]
site_dt[, IGBP_f := factor(IGBP, levels = igbp_freq)]

# ============================================================
# Create bar chart - N sites per IGBP class
# ============================================================

cat("Creating bar plot...\n")

bar_dt <- site_dt[, .N, by = .(IGBP, IGBP_f)][order(-N)]

p_bar <- ggplot(bar_dt, aes(x = reorder(IGBP_f, -N), y = N, fill = IGBP)) +
  geom_col(width = 0.7, colour = "white", linewidth = 0.3) +
  geom_text(aes(label = N), vjust = -0.4, size = 3.5, fontface = "bold") +
  scale_fill_manual(values = igbp_colours, guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = sprintf("Sites per IGBP class (n = %d total)", nrow(site_dt)),
       x = NULL, y = "Number of sites") +
  theme_bw(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 11, hjust = 0.5),
    axis.text.x = element_text(size = 8),
    axis.text.y = element_text(size = 9),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank()
  )

# Save plot (PNG and PDF)
ggsave(file.path(out_dir, "bar_sites_per_IGBP.png"),
       p_bar, width = 8, height = 4.5, dpi = 200)
ggsave(file.path(out_dir, "bar_sites_per_IGBP.pdf"),
       p_bar, width = 8, height = 4.5)

cat(sprintf("✓ Saved: %s/bar_sites_per_IGBP.png\n", out_dir))

cat("\nDone!\n")

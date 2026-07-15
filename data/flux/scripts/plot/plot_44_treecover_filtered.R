#!/usr/bin/env Rscript
# Bar plot: tree cover by site, excluding bottom 10% (low tree cover sites)

library(data.table)
library(ggplot2)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

# Create output directory
OUT_DIR <- "plots/tree_cover_summary"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# Dark theme colors
DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

cat("Loading RF v3 harmonized dataset...\n")
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

cat("Loading 164 RF+SHAP analysis sites...\n")
dist_analysis <- fread("derived_tables/disturbance_metric_test/tertiles_method.csv")
rf_shap_sites <- unique(dist_analysis$SITE_ID)

# Filter to RF+SHAP sites
main_data <- main_data[SITE_ID %in% rf_shap_sites]

cat("Loading IGBP data...\n")
igbp_map <- fread("Flux4Daniel/fluxnet_site_metadata_clean_with_elevation.csv")[, .(SITE_ID, IGBP)]

# Calculate mean tree cover per site
site_summary <- main_data[, .(
  mean_tree_cover = mean(forest_mean_pct_500m, na.rm = TRUE)
), by = SITE_ID]

# Add IGBP data
site_summary <- igbp_map[site_summary, on = "SITE_ID"]

# Apply threshold: remove bottom 10% (tree cover < 19%)
threshold <- quantile(site_summary$mean_tree_cover, 0.10)
cat("\nThreshold (10th percentile):", round(threshold, 2), "%\n")

excluded_sites <- site_summary[mean_tree_cover < threshold]
site_summary_filtered <- site_summary[mean_tree_cover >= threshold]

cat("Sites excluded:", nrow(excluded_sites), "\n")
cat("Sites retained:", nrow(site_summary_filtered), "\n\n")

cat("Excluded sites:\n")
excluded_sorted <- excluded_sites[order(mean_tree_cover)]
for (i in 1:nrow(excluded_sorted)) {
  row <- excluded_sorted[i]
  cat(sprintf("  %s | %s | %.2f%%\n", row$SITE_ID, row$IGBP, row$mean_tree_cover))
}

# Sort filtered sites by tree cover
site_summary_filtered <- site_summary_filtered[order(mean_tree_cover)]

# Define dark theme
dark_theme <- theme_bw(base_size = 10) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border     = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.5),
    panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
    panel.grid.minor = element_blank(),
    axis.text        = element_text(colour = AXIS_COL, size = 6),
    axis.title       = element_text(colour = AXIS_COL, size = 9),
    axis.ticks       = element_line(colour = GRID_COL),
    plot.title       = element_text(colour = TEXT_COL, size = 12, face = "bold"),
    plot.subtitle    = element_text(colour = AXIS_COL, size = 9),
    legend.background = element_rect(fill = PANEL_BG, colour = GRID_COL),
    legend.text      = element_text(colour = AXIS_COL, size = 8),
    legend.title     = element_text(colour = AXIS_COL, size = 9)
  )

# Define IGBP colors
igbp_colors <- c(
  "ENF" = "#2ecc71",  # green
  "DBF" = "#27ae60",  # darker green
  "MF"  = "#16a085",  # teal
  "EBF" = "#1abc9c",  # turquoise
  "CSH" = "#e67e22",  # orange
  "OSH" = "#f39c12",  # golden
  "WSA" = "#d4a373",  # tan
  "SAV" = "#c9a961",  # khaki
  "WET" = "#3498db",  # blue
  "DNF" = "#8e44ad"   # purple
)

# Create bar plot (filtered)
p <- ggplot(site_summary_filtered, aes(x = reorder(SITE_ID, mean_tree_cover), y = mean_tree_cover, fill = IGBP)) +
  geom_bar(stat = "identity", width = 0.8) +
  scale_fill_manual(
    name = "IGBP",
    values = igbp_colors
  ) +
  coord_flip() +
  labs(
    title = "Mean Tree Cover by Site (Filtered: bottom 10% removed)",
    subtitle = paste0("147 sites retained | ", nrow(excluded_sites), " sites excluded (tree cover < ", round(threshold, 1), "%)"),
    x = "Site ID",
    y = "Mean Tree Cover (%)"
  ) +
  dark_theme +
  theme(
    axis.text.y = element_text(size = 5),
    axis.text.x = element_text(size = 7),
    legend.position = "right"
  )

# Save as PDF and PNG
pdf_file <- file.path(OUT_DIR, "treecover_by_site_filtered_bottom10.pdf")
png_file <- file.path(OUT_DIR, "treecover_by_site_filtered_bottom10.png")

ggsave(pdf_file, p, width = 14, height = 26, units = "cm", dpi = 300, bg = DARK_BG)
ggsave(png_file, p, width = 14, height = 26, units = "cm", dpi = 300, bg = DARK_BG)

# Save excluded sites list
excluded_csv <- file.path(OUT_DIR, "excluded_sites_bottom10_low_treecover.csv")
fwrite(excluded_sorted[, .(SITE_ID, IGBP, mean_tree_cover)], excluded_csv)

cat(sprintf("\n✅ Completed!\n"))
cat(sprintf("   Filtered plot PDF: %s\n", pdf_file))
cat(sprintf("   Filtered plot PNG: %s\n", png_file))
cat(sprintf("   Excluded sites list: %s\n", excluded_csv))

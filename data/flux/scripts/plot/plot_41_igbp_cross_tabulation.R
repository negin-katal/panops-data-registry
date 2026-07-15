#!/usr/bin/env Rscript
# IGBP Cross-Tabulation: Check if disturbance categories confound with biome types

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- "plots/disturbance_metric_test/synthesis"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

cat("Loading data...\n")
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")
cat_data <- fread("derived_tables/disturbance_metric_test/tertiles_method.csv")

# Get IGBP from main data
igbp_map <- unique(main_data[, .(SITE_ID, IGBP)])

# Merge all together
analysis_data <- merge(cat_data, igbp_map, by.x = "SITE_ID", by.y = "SITE_ID")

cat("IGBP types found:\n")
print(unique(analysis_data$IGBP))

dark_theme <- theme_bw(base_size = 9) +
  theme(
    plot.background  = element_rect(fill = DARK_BG,  colour = NA),
    panel.background = element_rect(fill = PANEL_BG, colour = NA),
    panel.border     = element_rect(colour = GRID_COL, fill = NA),
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    axis.text        = element_text(colour = AXIS_COL, size = 7),
    axis.title       = element_text(colour = AXIS_COL, size = 8),
    plot.title       = element_text(colour = TEXT_COL, size = 11, face = "bold"),
    plot.subtitle    = element_text(colour = AXIS_COL, size = 8),
    legend.text      = element_text(colour = AXIS_COL, size = 7),
    legend.title     = element_text(colour = AXIS_COL, size = 7)
  )

# Helper function to create IGBP analysis for any metric
create_igbp_analysis <- function(metric_name, metric_col, metric_cat_col, out_dir) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # --- Visualization 1: Heatmap of IGBP × Disturbance ---
  p1_data <- analysis_data[, .N, by = .(IGBP, get(metric_cat_col))]
  setnames(p1_data, "get", metric_cat_col)
  p1_data[[metric_cat_col]] <- factor(p1_data[[metric_cat_col]],
                                      levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))

  p1 <- ggplot(p1_data, aes(x = get(metric_cat_col), y = IGBP, fill = N)) +
    geom_tile(colour = AXIS_COL, linewidth = 0.3) +
    geom_text(aes(label = N), colour = TEXT_COL, size = 2.5) +
    scale_fill_gradient(low = "#1a1a1a", high = "#e74c3c", name = "N sites") +
    labs(
      title = "IGBP Distribution across Disturbance Categories",
      subtitle = sprintf("Count of sites by biome type and %s tertile", metric_name),
      x = sprintf("Disturbance Level (%s)", metric_name),
      y = "IGBP Biome Type"
    ) +
    dark_theme +
    theme(axis.text.x = element_text(angle = 20, hjust = 1))

  ggsave(file.path(out_dir, "igbp_disturbance_heatmap.png"),
         p1, width = 180, height = 120, units = "mm", dpi = 300, bg = DARK_BG)
  cat(sprintf("✓ Saved: %s/igbp_disturbance_heatmap.png\n", out_dir))

  # --- Visualization 2: Stacked bar chart ---
  p2_data <- analysis_data[, .N, by = .(get(metric_cat_col), IGBP)]
  setnames(p2_data, "get", metric_cat_col)
  p2_data[[metric_cat_col]] <- factor(p2_data[[metric_cat_col]],
                                      levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))
  p2_data[, pct := N / sum(N) * 100, by = metric_cat_col]

  p2 <- ggplot(p2_data, aes(x = get(metric_cat_col), y = pct, fill = IGBP)) +
    geom_col(colour = "white", linewidth = 0.3) +
    scale_fill_brewer(palette = "Set3") +
    labs(
      title = "IGBP Composition by Disturbance Level",
      subtitle = "Are certain biomes concentrated in high-disturbance categories?",
      x = "Disturbance Level",
      y = "Percentage of Sites"
    ) +
    dark_theme +
    theme(axis.text.x = element_text(angle = 20, hjust = 1),
          legend.position = "right")

  ggsave(file.path(out_dir, "igbp_composition_stacked.png"),
         p2, width = 180, height = 120, units = "mm", dpi = 300, bg = DARK_BG)
  cat(sprintf("✓ Saved: %s/igbp_composition_stacked.png\n", out_dir))

  # --- Visualization 3: Mean disturbance by IGBP ---
  p3_data <- analysis_data[, .(mean_value = mean(get(metric_col), na.rm = TRUE),
                               n_sites = .N),
                           by = IGBP]
  p3_data <- p3_data[order(-mean_value)]

  p3 <- ggplot(p3_data, aes(x = reorder(IGBP, mean_value), y = mean_value, fill = IGBP)) +
    geom_col(colour = "white", linewidth = 0.3) +
    geom_text(aes(label = sprintf("n=%d", n_sites)), angle = 90, hjust = -0.1,
              colour = TEXT_COL, size = 2.5) +
    scale_fill_brewer(palette = "Set3", guide = "none") +
    labs(
      title = "Mean Disturbance Level by IGBP",
      subtitle = "Which biome types have highest average disturbance?",
      x = "IGBP Biome Type",
      y = sprintf("Mean %s (%%)", metric_name)
    ) +
    dark_theme +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))

  ggsave(file.path(out_dir, "igbp_mean_disturbance.png"),
         p3, width = 160, height = 120, units = "mm", dpi = 300, bg = DARK_BG)
  cat(sprintf("✓ Saved: %s/igbp_mean_disturbance.png\n", out_dir))

  # --- Summary table ---
  summary_table <- analysis_data[, .(
    n_sites = .N,
    mean_value = round(mean(get(metric_col), na.rm = TRUE), 2),
    sd_value = round(sd(get(metric_col), na.rm = TRUE), 2),
    min_value = round(min(get(metric_col), na.rm = TRUE), 2),
    max_value = round(max(get(metric_col), na.rm = TRUE), 2),
    pct_high_dist = round(sum(get(metric_cat_col) == "Tertile 3 (High)") / .N * 100, 1)
  ), by = IGBP]

  summary_table <- summary_table[order(-n_sites)]

  cat(sprintf("\n=== Summary: %s Statistics by IGBP ===\n", metric_name))
  print(summary_table)

  fwrite(summary_table, file.path(out_dir, "igbp_disturbance_summary.csv"))

  # Create cross-tabulation
  crosstab <- analysis_data[, .N, by = .(IGBP, get(metric_cat_col))]
  setnames(crosstab, "get", metric_cat_col)
  crosstab[, pct := round(N / sum(N) * 100, 1), by = IGBP]
  fwrite(crosstab, file.path(out_dir, "crosstab_igbp_vs_metric.csv"))
}

# --- GENERATE ANALYSIS FOR EACH METRIC ---
cat("\n╔════════════════════════════════════════════════════════════╗\n")
cat("║ ABSOLUTE MORTALITY - IGBP CONFOUNDING ANALYSIS             ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
create_igbp_analysis("Absolute Mortality", "abs_mort", "abs_mort_cat",
                     "plots/disturbance_metric_test/abs_mort_analysis")

cat("\n╔════════════════════════════════════════════════════════════╗\n")
cat("║ RELATIVE MORTALITY - IGBP CONFOUNDING ANALYSIS             ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
create_igbp_analysis("Relative Mortality", "rel_mort", "rel_mort_cat",
                     "plots/disturbance_metric_test/rel_mort_analysis")

cat("\n╔════════════════════════════════════════════════════════════╗\n")
cat("║ RELATIVE DISTURBANCE - IGBP CONFOUNDING ANALYSIS           ║\n")
cat("╚════════════════════════════════════════════════════════════╝\n")
create_igbp_analysis("Relative Disturbance", "rel_dist", "rel_dist_cat",
                     "plots/disturbance_metric_test/rel_dist_analysis")

cat("\n✓ IGBP analysis complete for all three metrics!\n")
cat("\n=== INTERPRETATION ===\n")
cat("Check these patterns across all three metrics:\n")
cat("1. Are certain IGBP types concentrated in high disturbance?\n")
cat("2. Do carbon flux improvements correlate with specific biomes?\n")
cat("3. Could IGBP be confounding the carbon/water flux difference?\n")
cat("   → If forests show improvement but grasslands don't,\n")
cat("   → maybe the IGBP type (not disturbance) is driving the effect\n")

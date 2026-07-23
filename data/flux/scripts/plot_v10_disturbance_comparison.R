#!/usr/bin/env Rscript
# ============================================================================
# V10: Disturbance Metric Distribution Comparison (3 Methods)
# Creates comparison plots showing Tertiles, Equal-Width, and Natural Breaks
# ============================================================================

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript plot_v10_disturbance_comparison.R <dataset_type>")
}

dataset_type <- args[1]  # "filtered" or "all_sites"

cat("\n", strrep("=", 80), "\n", sep="")
cat(sprintf("V10 DISTURBANCE METRIC COMPARISON (3 METHODS): %s\n", toupper(dataset_type)))
cat(strrep("=", 80), "\n\n", sep="")

# ============================================================================
# Load data
# ============================================================================

if (dataset_type == "filtered") {
  harm_file <- 'derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv'
  output_dir <- 'plots/V10/sites_with_high_Tcover'
} else if (dataset_type == "all_sites") {
  harm_file <- 'derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_GPPsat_harmonized.csv'
  output_dir <- 'plots/V10/all_sites'
} else {
  stop("Invalid dataset_type")
}

df_harm <- as.data.frame(fread(harm_file))

# Use 500m buffer for disturbance metrics
abs_mort <- df_harm$absolute_mortality_500m
rel_mort <- df_harm$relative_mortality_500m
rel_dist <- df_harm$relative_disturbance_500m

# Remove NAs
abs_mort <- abs_mort[!is.na(abs_mort)]
rel_mort <- rel_mort[!is.na(rel_mort)]
rel_dist <- rel_dist[!is.na(rel_dist)]

sites_v10 <- unique(df_harm$SITE_ID)

cat(sprintf("N observations: %d\n", length(abs_mort)))

# ============================================================================
# Categorization methods
# ============================================================================

categorize_metric <- function(metric, metric_name) {
  # METHOD 1: Tertiles
  tertiles <- quantile(metric, c(0.3333, 0.6667), na.rm = TRUE)
  method1 <- cut(metric, breaks = c(-Inf, tertiles[1], tertiles[2], Inf),
                 labels = c("Tertile 1", "Tertile 2", "Tertile 3"))

  # METHOD 2: Equal-Width
  min_val <- min(metric, na.rm = TRUE)
  max_val <- max(metric, na.rm = TRUE)
  width <- (max_val - min_val) / 3
  breaks_ew <- c(-Inf, min_val + width, min_val + 2*width, Inf)
  method2 <- cut(metric, breaks = breaks_ew,
                 labels = c("Bin 1", "Bin 2", "Bin 3"))

  # METHOD 3: Natural Breaks (mean ± 0.5*SD)
  m <- mean(metric, na.rm = TRUE)
  s <- sd(metric, na.rm = TRUE)
  breaks_nb <- c(-Inf, m - 0.5*s, m + 0.5*s, Inf)
  method3 <- cut(metric, breaks = breaks_nb,
                 labels = c("Cluster 1", "Cluster 2", "Cluster 3"))

  cat(sprintf("\n%s:\n", metric_name))
  cat(sprintf("  Tertiles: %.2f, %.2f\n", tertiles[1], tertiles[2]))
  cat(sprintf("  Equal-Width: %.2f, %.2f\n", min_val + width, min_val + 2*width))
  cat(sprintf("  Natural Breaks: %.2f, %.2f\n", m - 0.5*s, m + 0.5*s))

  return(list(method1 = method1, method2 = method2, method3 = method3))
}

# ============================================================================
# Create comparison plot (3 methods side by side)
# ============================================================================

create_comparison_plot <- function(metric, metric_name, filename) {
  cats <- categorize_metric(metric, metric_name)

  # Prepare data
  df_plot <- data.frame(
    value = metric,
    method1 = cats$method1,
    method2 = cats$method2,
    method3 = cats$method3
  )

  # Remove NAs
  df_plot <- df_plot[complete.cases(df_plot), ]

  # Calculate breaks for histogram
  n_breaks <- 30
  breaks <- seq(min(df_plot$value, na.rm = TRUE),
                max(df_plot$value, na.rm = TRUE),
                length.out = n_breaks + 1)

  # Theme
  dark_theme <- theme(
    plot.title = element_text(size = 13, face = "bold", hjust = 0.5, color = "white"),
    axis.title = element_text(size = 10, color = "white"),
    axis.text = element_text(color = "white", size = 9),
    panel.background = element_rect(fill = "#1a1a1a", color = NA),
    plot.background = element_rect(fill = "#1a1a1a", color = NA),
    panel.grid.major = element_line(color = "white", linewidth = 0.3),
    panel.grid.minor = element_line(color = "gray30", linewidth = 0.15),
    legend.position = "bottom",
    legend.background = element_rect(fill = "#1a1a1a", color = NA),
    legend.text = element_text(color = "white", size = 9),
    legend.key = element_rect(fill = "#1a1a1a", color = NA),
    legend.title = element_blank()
  )

  # Plot 1: Tertiles
  p1 <- ggplot(df_plot, aes(x = value, fill = method1)) +
    geom_histogram(breaks = breaks, color = "white", linewidth = 0.5, alpha = 0.95) +
    scale_fill_manual(values = c("Tertile 1" = "#2E7D8C", "Tertile 2" = "#D4A942", "Tertile 3" = "#D61E7A")) +
    labs(title = "METHOD 1: Tertiles",
         x = paste(metric_name, "(%)"),
         y = "Count") +
    theme_minimal() + dark_theme +
    theme(legend.position = "none")

  # Plot 2: Equal-Width
  p2 <- ggplot(df_plot, aes(x = value, fill = method2)) +
    geom_histogram(breaks = breaks, color = "white", linewidth = 0.5, alpha = 0.95) +
    scale_fill_manual(values = c("Bin 1" = "#2E7D8C", "Bin 2" = "#D4A942", "Bin 3" = "#D61E7A")) +
    labs(title = "METHOD 2: Equal-Width",
         x = paste(metric_name, "(%)"),
         y = "Count") +
    theme_minimal() + dark_theme +
    theme(axis.title.y = element_blank(), axis.text.y = element_blank(),
          legend.position = "none")

  # Plot 3: Natural Breaks
  p3 <- ggplot(df_plot, aes(x = value, fill = method3)) +
    geom_histogram(breaks = breaks, color = "white", linewidth = 0.5, alpha = 0.95) +
    scale_fill_manual(values = c("Cluster 1" = "#2E7D8C", "Cluster 2" = "#D4A942", "Cluster 3" = "#D61E7A")) +
    labs(title = "METHOD 3: Natural Breaks",
         x = paste(metric_name, "(%)"),
         y = "Count") +
    theme_minimal() + dark_theme +
    theme(axis.title.y = element_blank(), axis.text.y = element_blank(),
          legend.position = "none")

  # Combine with shared legend
  combined <- p1 + p2 + p3 +
    plot_layout(ncol = 3, widths = c(1, 1, 1)) +
    plot_annotation(theme = theme(plot.background = element_rect(fill = "#1a1a1a", color = NA)))

  ggsave(filename, combined, width = 16, height = 5.5, dpi = 300, bg = "#1a1a1a")
  cat(sprintf("✓ %s\n", filename))

  # Also save as PDF
  pdf_filename <- sub('\\.png$', '.pdf', filename)
  ggsave(pdf_filename, combined, width = 16, height = 5.5, bg = "#1a1a1a")
  cat(sprintf("✓ %s\n", pdf_filename))
}

# Create plots
create_comparison_plot(abs_mort, "Absolute Mortality (500m buffer)",
                       file.path(output_dir, "01_abs_mort_comparison.png"))

create_comparison_plot(rel_mort, "Relative Mortality (500m buffer)",
                       file.path(output_dir, "02_rel_mort_comparison.png"))

create_comparison_plot(rel_dist, "Relative Disturbance (500m buffer)",
                       file.path(output_dir, "03_rel_dist_comparison.png"))

cat(sprintf("\n✅ V10 DISTURBANCE COMPARISON PLOTS COMPLETE (3 METHODS)\n"))
cat(sprintf("   Dataset: %s (%d sites)\n", dataset_type, length(sites_v10)))
cat(sprintf("   Output: %s/\n", output_dir))

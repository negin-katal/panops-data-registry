#!/usr/bin/env Rscript
# Master script for Delta RMSE and comprehensive analysis plots

library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

METHODS <- c("tertiles_method", "equal_width_method", "natural_breaks_method")
OUT_BASE <- "plots/disturbance_metric_test"

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
MODELS <- c("M02", "M04", "M06", "M08")
COMPARISON_PAIRS <- list(c("M01", "M02"), c("M03", "M04"), c("M05", "M06"), c("M07", "M08"))

get_dark_theme <- function() {
  theme_bw(base_size = 9) +
    theme(
      plot.background  = element_rect(fill = DARK_BG,  colour = NA),
      panel.background = element_rect(fill = PANEL_BG, colour = NA),
      panel.border     = element_rect(colour = GRID_COL, fill = NA),
      panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
      panel.grid.minor = element_blank(),
      axis.text        = element_text(colour = AXIS_COL, size = 7.5),
      axis.title       = element_text(colour = AXIS_COL, size = 8.5),
      plot.title       = element_text(colour = TEXT_COL, size = 10, face = "bold"),
      plot.subtitle    = element_text(colour = AXIS_COL, size = 8)
    )
}

# Load metrics
cat("Loading RF metrics...\n")
metrics <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_metrics_LOSO.csv")

# Loop through methods
for (method in METHODS) {
  cat("\n╔════════════════════════════════════════════════════════════╗\n")
  cat("║ DELTA RMSE - METHOD:", method, "\n")
  cat("╚════════════════════════════════════════════════════════════╝\n")

  out_dir <- file.path(OUT_BASE, method)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Load categorization data
  cat_data <- fread(paste0("derived_tables/disturbance_metric_test/", method, ".csv"))

  # Load site predictions for Delta RMSE
  predictions <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_predictions_LOSO.csv")

  # Calculate RMSE per site and model
  predictions[, residual := (predicted - observed)^2]
  metrics_with_site <- predictions[, .(rmse = sqrt(mean(residual, na.rm = TRUE))),
                                     by = .(model, response, SITE_ID)]

  # Extract window and model parts
  metrics_with_site[, c("model_part", "window_part", "response") := tstrsplit(model, "_")]
  metrics_with_site[, model := model_part]
  metrics_with_site[, window := window_part]

  # Merge with categorization
  metrics_with_site <- merge(metrics_with_site, cat_data, by = "SITE_ID", all.x = TRUE)

  # Color scheme
  cat_names <- unique(c(cat_data$abs_mort_cat, cat_data$rel_mort_cat, cat_data$rel_dist_cat))
  tier_cols <- setNames(
    rep(c("#4DAECC", "#F0A500", "#E8257A"), length.out = length(cat_names)),
    sort(unique(cat_names))
  )

  # Create Delta RMSE plots for each comparison pair
  cat("Generating Delta RMSE plots...\n")

  for (resp in EFP_ORDER) {
    for (window in c("12m", "24m")) {
      for (i in seq_along(COMPARISON_PAIRS)) {
        m_without <- COMPARISON_PAIRS[[i]][1]
        m_with <- COMPARISON_PAIRS[[i]][2]

        data_without <- metrics_with_site[model == m_without & window == window & response == resp, .(SITE_ID, rmse_without = rmse)]
        data_with <- metrics_with_site[model == m_with & window == window & response == resp, .(SITE_ID, rmse_with = rmse)]

        if (nrow(data_without) == 0 || nrow(data_with) == 0) next

        delta <- merge(data_without, data_with, by = "SITE_ID")
        delta <- merge(delta, cat_data, by = "SITE_ID")
        delta[, delta_rmse := rmse_with - rmse_without]

        p <- ggplot(delta, aes(y = delta_rmse, x = abs_mort_cat, fill = abs_mort_cat)) +
          geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.5, linetype = "dashed") +
          geom_boxplot(outlier.shape = NA, colour = "white", linewidth = 0.4) +
          geom_jitter(width = 0.2, alpha = 0.3, size = 1, colour = "white") +
          scale_fill_manual(values = tier_cols, guide = "none") +
          labs(
            title = sprintf("%s vs %s | %s | %s window", m_with, m_without, resp, window),
            x = "",
            y = "Delta RMSE (with D - without D)"
          ) +
          get_dark_theme() +
          theme(axis.text.x = element_text(angle = 20, hjust = 1))

        stem <- file.path(out_dir, sprintf("03_DeltaRMSE_%s_%s_%s_%s", m_with, m_without, resp, window))
        ggsave(paste0(stem, ".png"), p, width = 140, height = 100, units = "mm", dpi = 300, bg = DARK_BG)
      }
    }
  }

  cat("✓ Delta RMSE plots complete for", method, "\n")
}

cat("\n✓ All Delta RMSE plots complete!\n")

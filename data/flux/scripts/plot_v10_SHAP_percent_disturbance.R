#!/usr/bin/env Rscript
# ============================================================================
# V10: SHAP Percent Distribution (Matching plot_35 style)
# Violin plots for M4, M6, M8 × 12m/24m × Tertiles/Equal-Width/Natural Breaks
# ============================================================================

library(data.table)
library(ggplot2)
library(patchwork)
library(dplyr)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript plot_v10_SHAP_percent_disturbance.R <dataset_type>")
}

dataset_type <- args[1]
MERGE <- length(args) >= 2 && args[2] == "merge"

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("V10 SHAP PERCENT (3 METHODS): %s%s\n", toupper(dataset_type),
            if (MERGE) " [MERGED LOW+MID]" else ""))
cat(strrep("=", 80), "\n\n", sep = "")

# Color scheme matching plot_35
DARK_BG <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

# Category levels + fill colors depend on merge mode
if (MERGE) {
  LEVELS <- c("Low+Mid", "High")
  FILL_MAP <- setNames(c("#4DAECC", "#E8257A"), LEVELS)
} else {
  LEVELS <- c("Low", "Mid", "High")
  FILL_MAP <- setNames(c("#4DAECC", "#F0A500", "#E8257A"), LEVELS)
}

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

get_dark_theme <- function() {
  theme_bw(base_size = 9) +
    theme(
      plot.background = element_rect(fill = DARK_BG, colour = NA),
      panel.background = element_rect(fill = PANEL_BG, colour = NA),
      panel.border = element_rect(colour = GRID_COL, fill = NA),
      panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.25),
      panel.grid.minor = element_blank(),
      strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
      strip.text = element_text(colour = TEXT_COL, size = 8, face = "bold"),
      axis.text = element_text(colour = AXIS_COL, size = 7.5),
      axis.title = element_text(colour = AXIS_COL, size = 8.5),
      plot.title = element_text(colour = TEXT_COL, size = 10, face = "bold"),
      plot.subtitle = element_text(colour = AXIS_COL, size = 8)
    )
}

# Load data
if (dataset_type == "filtered") {
  harm_file <- "derived_tables/outputs_afterEGU_results/v10/v10_B1_GPPsat_harmonized.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10/RF_site_shap_M04_M08.csv"
  output_dir <- "plots/V10/sites_with_high_Tcover/SHAP_percent"
} else if (dataset_type == "all_sites") {
  harm_file <- "derived_tables/outputs_afterEGU_results/v10_all_sites/v10_all_B1_GPPsat_harmonized.csv"
  shap_file <- "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_site_shap_M04_M08.csv"
  output_dir <- "plots/V10/all_sites/SHAP_percent"
} else {
  stop("Invalid dataset_type")
}

if (MERGE) {
  output_dir <- file.path(output_dir, "merged_low_disturbance")
}
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

df_harm <- as.data.frame(fread(harm_file))
df_shap <- as.data.frame(fread(shap_file))

# Create categorizations for all three methods
abs_mort <- df_harm$absolute_mortality_500m
rel_mort <- df_harm$relative_mortality_500m
rel_dist <- df_harm$relative_disturbance_500m

# TERTILES
t_am <- quantile(abs_mort, c(0.3333, 0.6667), na.rm = TRUE)
t_rm <- quantile(rel_mort, c(0.3333, 0.6667), na.rm = TRUE)
t_rd <- quantile(rel_dist, c(0.3333, 0.6667), na.rm = TRUE)

# EQUAL-WIDTH
ew_am_w <- (max(abs_mort, na.rm = TRUE) - min(abs_mort, na.rm = TRUE)) / 3
ew_am <- c(min(abs_mort, na.rm = TRUE) + ew_am_w, min(abs_mort, na.rm = TRUE) + 2 * ew_am_w)
ew_rm_w <- (max(rel_mort, na.rm = TRUE) - min(rel_mort, na.rm = TRUE)) / 3
ew_rm <- c(min(rel_mort, na.rm = TRUE) + ew_rm_w, min(rel_mort, na.rm = TRUE) + 2 * ew_rm_w)
ew_rd_w <- (max(rel_dist, na.rm = TRUE) - min(rel_dist, na.rm = TRUE)) / 3
ew_rd <- c(min(rel_dist, na.rm = TRUE) + ew_rd_w, min(rel_dist, na.rm = TRUE) + 2 * ew_rd_w)

# NATURAL BREAKS
nb_am_m <- mean(abs_mort, na.rm = TRUE)
nb_am_s <- sd(abs_mort, na.rm = TRUE)
nb_am <- c(nb_am_m - 0.5 * nb_am_s, nb_am_m + 0.5 * nb_am_s)
nb_rm_m <- mean(rel_mort, na.rm = TRUE)
nb_rm_s <- sd(rel_mort, na.rm = TRUE)
nb_rm <- c(nb_rm_m - 0.5 * nb_rm_s, nb_rm_m + 0.5 * nb_rm_s)
nb_rd_m <- mean(rel_dist, na.rm = TRUE)
nb_rd_s <- sd(rel_dist, na.rm = TRUE)
nb_rd <- c(nb_rd_m - 0.5 * nb_rd_s, nb_rd_m + 0.5 * nb_rd_s)

# Create categories
df_cat <- data.frame(
  SITE_ID = df_harm$SITE_ID,
  am_t = factor(cut(abs_mort, c(-Inf, t_am[1], t_am[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  rm_t = factor(cut(rel_mort, c(-Inf, t_rm[1], t_rm[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  rd_t = factor(cut(rel_dist, c(-Inf, t_rd[1], t_rd[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  am_ew = factor(cut(abs_mort, c(-Inf, ew_am[1], ew_am[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  rm_ew = factor(cut(rel_mort, c(-Inf, ew_rm[1], ew_rm[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  rd_ew = factor(cut(rel_dist, c(-Inf, ew_rd[1], ew_rd[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  am_nb = factor(cut(abs_mort, c(-Inf, nb_am[1], nb_am[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  rm_nb = factor(cut(rel_mort, c(-Inf, nb_rm[1], nb_rm[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High")),
  rd_nb = factor(cut(rel_dist, c(-Inf, nb_rd[1], nb_rd[2], Inf), c("Low", "Mid", "High")), levels = c("Low", "Mid", "High"))
)

# If merge mode, collapse Low + Mid into a single "Low+Mid" group
if (MERGE) {
  cat_cols_all <- setdiff(names(df_cat), "SITE_ID")
  for (cc in cat_cols_all) {
    v <- as.character(df_cat[[cc]])
    v[v %in% c("Low", "Mid")] <- "Low+Mid"
    df_cat[[cc]] <- factor(v, levels = LEVELS)
  }
}

# Calculate SHAP percent
df_shap$is_dist <- grepl("^(absolute_|relative_|new_mortality|disturbance_)", df_shap$variable)

df_shap_sum <- df_shap %>%
  group_by(model, response, test_site) %>%
  summarise(
    total = sum(mean_abs_shap, na.rm = TRUE),
    dist = sum(mean_abs_shap[is_dist], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(dist_pct = (dist / total) * 100) %>%
  filter(!is.na(dist_pct) & is.finite(dist_pct))

# Merge
df_plot <- merge(df_shap_sum, df_cat, by.x = "test_site", by.y = "SITE_ID", all.x = TRUE)
df_plot$response <- factor(df_plot$response, levels = EFP_ORDER)

cat(sprintf("Prepared data: %d rows\n\n", nrow(df_plot)))

# Create plots
make_plot <- function(data, cat_col, metric_name, method_name) {
  data[[cat_col]] <- factor(data[[cat_col]], levels = LEVELS)

  p <- ggplot(data, aes_string(x = cat_col, y = "dist_pct", fill = cat_col)) +
    geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.4) +
    geom_violin(trim = TRUE, scale = "width", width = 0.75, colour = NA, alpha = 0.85) +
    geom_boxplot(width = 0.18, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.35) +
    stat_summary(fun = median, geom = "point", colour = "white", size = 1.2) +
    scale_fill_manual(values = FILL_MAP, guide = "none") +
    facet_wrap(~response, nrow = 1) +
    labs(title = sprintf("Disturbance SHAP %% by %s (%s)", metric_name, method_name),
         x = "", y = "Disturbance SHAP (%)") +
    get_dark_theme() +
    theme(axis.text.x = element_text(colour = AXIS_COL, size = 7, angle = 20, hjust = 1))

  return(p)
}

models <- c("M4_12m", "M4_24m", "M6_raw_12m", "M6_raw_24m", "M6_anom_12m", "M6_anom_24m",
            "M8_raw_12m", "M8_raw_24m", "M8_anom_12m", "M8_anom_24m")

methods <- list(
  list(name = "tertiles", label = "Tertiles", cols = c("am_t", "rm_t", "rd_t")),
  list(name = "equal_width", label = "Equal-Width", cols = c("am_ew", "rm_ew", "rd_ew")),
  list(name = "natural_breaks", label = "Natural Breaks", cols = c("am_nb", "rm_nb", "rd_nb"))
)

metrics <- list(
  list(name = "Absolute Mortality", col_idx = 1),
  list(name = "Relative Mortality", col_idx = 2),
  list(name = "Relative Disturbance", col_idx = 3)
)

cat("Generating plots:\n")
for (model in models) {
  model_label <- sub("_12m$|_24m$", "", model)
  window <- if (grepl("12m$", model)) "12m" else "24m"

  for (method in methods) {
    df_model <- df_plot[df_plot$model == model, ]
    if (nrow(df_model) == 0) next

    # Create three row plots for this model/method
    p_list <- list()
    for (m_idx in seq_along(metrics)) {
      metric <- metrics[[m_idx]]
      cat_col <- method$cols[m_idx]
      p <- make_plot(df_model, cat_col, metric$name, paste(model_label, window))
      p_list[[m_idx]] <- p
    }

    # Stack rows
    combined <- (p_list[[1]] / p_list[[2]] / p_list[[3]]) +
      plot_annotation(theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA))) &
      theme(plot.background = element_rect(fill = DARK_BG, colour = NA))

    fname <- file.path(output_dir, sprintf("SHAP_percent_%s_%s_%s.png", model_label, window, method$name))
    ggsave(fname, combined, width = 220, height = 240, units = "mm", dpi = 300, bg = DARK_BG)
    cat(sprintf("  ✓ %s\n", basename(fname)))

    pdf_fname <- sub("\\.png$", ".pdf", fname)
    ggsave(pdf_fname, combined, width = 220, height = 240, units = "mm", bg = DARK_BG)
    cat(sprintf("  ✓ %s\n", basename(pdf_fname)))
  }
}

cat(sprintf("\n✅ V10 SHAP PERCENT PLOTS COMPLETE (plot_35 STYLE)\n"))

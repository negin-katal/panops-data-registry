library(data.table)
library(ggplot2)
library(patchwork)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT_DIR <- "plots/disturbance_metric_test"
DATA_DIR <- "derived_tables/disturbance_metric_test"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

DARK_BG  <- "#0D0D0D"
PANEL_BG <- "#111111"
GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"
AXIS_COL <- "#CCCCCC"

# Load v3 harmonized dataset
main_data <- fread("derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags_v3_harmonized.csv")

# Get common sites from M06 and M08 SHAP data (164 sites)
shap_m06 <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M06.csv")
shap_m08 <- fread("derived_tables/outputs_afterEGU_results/RF_outputs_anomaly_24mbench_v3/RF_site_shap_M04_M08.csv")[grepl("^M08_", model)]

m06_sites <- unique(shap_m06$test_site)
m08_sites <- unique(shap_m08$test_site)
common_sites <- intersect(m06_sites, m08_sites)

cat("Using", length(common_sites), "common sites for categorization\n\n")

# Calculate site-level metrics (only for common sites)
site_metrics <- main_data[SITE_ID %in% common_sites, .(
  abs_mort = mean(deadwood_mean_pct_500m, na.rm = TRUE),
  rel_mort = mean((deadwood_mean_pct_500m / forest_mean_pct_500m * 100), na.rm = TRUE),
  rel_dist = mean(((deadwood_mean_pct_500m + loss_area_frac_500m * 100) /
                    (forest_mean_pct_500m + loss_area_frac_500m * 100) * 100), na.rm = TRUE)
), by = SITE_ID]

site_metrics <- site_metrics[is.finite(abs_mort) & is.finite(rel_mort) & is.finite(rel_dist)]

# ── METHOD 1: TERTILES (Equal-sized, 33.33 and 66.67 percentiles) ─────────────
cat("=== METHOD 1: TERTILES (Equal-Sized Groups) ===\n")
abs_mort_q33 <- as.numeric(quantile(site_metrics$abs_mort, 0.3333, na.rm = TRUE))
abs_mort_q67 <- as.numeric(quantile(site_metrics$abs_mort, 0.6667, na.rm = TRUE))

rel_mort_q33 <- as.numeric(quantile(site_metrics$rel_mort, 0.3333, na.rm = TRUE))
rel_mort_q67 <- as.numeric(quantile(site_metrics$rel_mort, 0.6667, na.rm = TRUE))

rel_dist_q33 <- as.numeric(quantile(site_metrics$rel_dist, 0.3333, na.rm = TRUE))
rel_dist_q67 <- as.numeric(quantile(site_metrics$rel_dist, 0.6667, na.rm = TRUE))

cat("Absolute Mortality: Q33 =", sprintf("%.2f", abs_mort_q33), "%, Q67 =", sprintf("%.2f", abs_mort_q67), "%\n")
cat("Relative Mortality:  Q33 =", sprintf("%.2f", rel_mort_q33), "%, Q67 =", sprintf("%.2f", rel_mort_q67), "%\n")
cat("Relative Disturbance: Q33 =", sprintf("%.2f", rel_dist_q33), "%, Q67 =", sprintf("%.2f", rel_dist_q67), "%\n\n")

tertiles <- copy(site_metrics)
tertiles[, abs_mort_cat := fcase(
  abs_mort <= abs_mort_q33,  "Tertile 1 (Low)",
  abs_mort <= abs_mort_q67,  "Tertile 2 (Mid)",
  default =                   "Tertile 3 (High)"
)]
tertiles[, rel_mort_cat := fcase(
  rel_mort <= rel_mort_q33,  "Tertile 1 (Low)",
  rel_mort <= rel_mort_q67,  "Tertile 2 (Mid)",
  default =                   "Tertile 3 (High)"
)]
tertiles[, rel_dist_cat := fcase(
  rel_dist <= rel_dist_q33,  "Tertile 1 (Low)",
  rel_dist <= rel_dist_q67,  "Tertile 2 (Mid)",
  default =                   "Tertile 3 (High)"
)]
fwrite(tertiles[, .(SITE_ID, abs_mort, rel_mort, rel_dist, abs_mort_cat, rel_mort_cat, rel_dist_cat)],
       paste0(DATA_DIR, "/tertiles_method.csv"))

# ── METHOD 2: EQUAL-WIDTH (Divide min-max into 3 equal intervals) ─────────────
cat("=== METHOD 2: EQUAL-WIDTH ===\n")
abs_mort_min <- min(site_metrics$abs_mort, na.rm = TRUE)
abs_mort_max <- max(site_metrics$abs_mort, na.rm = TRUE)
abs_mort_width <- (abs_mort_max - abs_mort_min) / 3
abs_mort_cut1 <- abs_mort_min + abs_mort_width
abs_mort_cut2 <- abs_mort_min + 2 * abs_mort_width

rel_mort_min <- min(site_metrics$rel_mort, na.rm = TRUE)
rel_mort_max <- max(site_metrics$rel_mort, na.rm = TRUE)
rel_mort_width <- (rel_mort_max - rel_mort_min) / 3
rel_mort_cut1 <- rel_mort_min + rel_mort_width
rel_mort_cut2 <- rel_mort_min + 2 * rel_mort_width

rel_dist_min <- min(site_metrics$rel_dist, na.rm = TRUE)
rel_dist_max <- max(site_metrics$rel_dist, na.rm = TRUE)
rel_dist_width <- (rel_dist_max - rel_dist_min) / 3
rel_dist_cut1 <- rel_dist_min + rel_dist_width
rel_dist_cut2 <- rel_dist_min + 2 * rel_dist_width

cat("Absolute Mortality: Cut1 =", sprintf("%.2f", abs_mort_cut1), "%, Cut2 =", sprintf("%.2f", abs_mort_cut2), "%\n")
cat("Relative Mortality:  Cut1 =", sprintf("%.2f", rel_mort_cut1), "%, Cut2 =", sprintf("%.2f", rel_mort_cut2), "%\n")
cat("Relative Disturbance: Cut1 =", sprintf("%.2f", rel_dist_cut1), "%, Cut2 =", sprintf("%.2f", rel_dist_cut2), "%\n\n")

equal_width <- copy(site_metrics)
equal_width[, abs_mort_cat := fcase(
  abs_mort <= abs_mort_cut1,  "Bin 1 (Low)",
  abs_mort <= abs_mort_cut2,  "Bin 2 (Mid)",
  default =                   "Bin 3 (High)"
)]
equal_width[, rel_mort_cat := fcase(
  rel_mort <= rel_mort_cut1,  "Bin 1 (Low)",
  rel_mort <= rel_mort_cut2,  "Bin 2 (Mid)",
  default =                   "Bin 3 (High)"
)]
equal_width[, rel_dist_cat := fcase(
  rel_dist <= rel_dist_cut1,  "Bin 1 (Low)",
  rel_dist <= rel_dist_cut2,  "Bin 2 (Mid)",
  default =                   "Bin 3 (High)"
)]
fwrite(equal_width[, .(SITE_ID, abs_mort, rel_mort, rel_dist, abs_mort_cat, rel_mort_cat, rel_dist_cat)],
       paste0(DATA_DIR, "/equal_width_method.csv"))

# ── METHOD 3: NATURAL BREAKS (Jenks algorithm via clustering) ──────────────────
cat("=== METHOD 3: NATURAL BREAKS (Clustering-based) ===\n")

# Simple natural breaks using standard deviation
abs_mort_mean <- mean(site_metrics$abs_mort, na.rm = TRUE)
abs_mort_sd <- sd(site_metrics$abs_mort, na.rm = TRUE)
abs_mort_cut1_nb <- abs_mort_mean - 0.5 * abs_mort_sd
abs_mort_cut2_nb <- abs_mort_mean + 0.5 * abs_mort_sd

rel_mort_mean <- mean(site_metrics$rel_mort, na.rm = TRUE)
rel_mort_sd <- sd(site_metrics$rel_mort, na.rm = TRUE)
rel_mort_cut1_nb <- rel_mort_mean - 0.5 * rel_mort_sd
rel_mort_cut2_nb <- rel_mort_mean + 0.5 * rel_mort_sd

rel_dist_mean <- mean(site_metrics$rel_dist, na.rm = TRUE)
rel_dist_sd <- sd(site_metrics$rel_dist, na.rm = TRUE)
rel_dist_cut1_nb <- rel_dist_mean - 0.5 * rel_dist_sd
rel_dist_cut2_nb <- rel_dist_mean + 0.5 * rel_dist_sd

cat("Absolute Mortality: Cut1 =", sprintf("%.2f", abs_mort_cut1_nb), "%, Cut2 =", sprintf("%.2f", abs_mort_cut2_nb), "%\n")
cat("Relative Mortality:  Cut1 =", sprintf("%.2f", rel_mort_cut1_nb), "%, Cut2 =", sprintf("%.2f", rel_mort_cut2_nb), "%\n")
cat("Relative Disturbance: Cut1 =", sprintf("%.2f", rel_dist_cut1_nb), "%, Cut2 =", sprintf("%.2f", rel_dist_cut2_nb), "%\n\n")

natural_breaks <- copy(site_metrics)
natural_breaks[, abs_mort_cat := fcase(
  abs_mort <= abs_mort_cut1_nb,  "Cluster 1 (Low)",
  abs_mort <= abs_mort_cut2_nb,  "Cluster 2 (Mid)",
  default =                       "Cluster 3 (High)"
)]
natural_breaks[, rel_mort_cat := fcase(
  rel_mort <= rel_mort_cut1_nb,  "Cluster 1 (Low)",
  rel_mort <= rel_mort_cut2_nb,  "Cluster 2 (Mid)",
  default =                       "Cluster 3 (High)"
)]
natural_breaks[, rel_dist_cat := fcase(
  rel_dist <= rel_dist_cut1_nb,  "Cluster 1 (Low)",
  rel_dist <= rel_dist_cut2_nb,  "Cluster 2 (Mid)",
  default =                       "Cluster 3 (High)"
)]
fwrite(natural_breaks[, .(SITE_ID, abs_mort, rel_mort, rel_dist, abs_mort_cat, rel_mort_cat, rel_dist_cat)],
       paste0(DATA_DIR, "/natural_breaks_method.csv"))

# ── Create comparison visualizations ──────────────────────────────────────────
dark_theme <- theme_bw(base_size = 9) +
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

COLS_TERTILE <- c("Tertile 1 (Low)" = "#4DAECC", "Tertile 2 (Mid)" = "#F0A500", "Tertile 3 (High)" = "#E8257A")
COLS_EQUAL <- c("Bin 1 (Low)" = "#4DAECC", "Bin 2 (Mid)" = "#F0A500", "Bin 3 (High)" = "#E8257A")
COLS_NATURAL <- c("Cluster 1 (Low)" = "#4DAECC", "Cluster 2 (Mid)" = "#F0A500", "Cluster 3 (High)" = "#E8257A")

# Absolute Mortality comparison
tertiles[, abs_mort_cat := factor(abs_mort_cat, levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
equal_width[, abs_mort_cat := factor(abs_mort_cat, levels = c("Bin 1 (Low)", "Bin 2 (Mid)", "Bin 3 (High)"))]
natural_breaks[, abs_mort_cat := factor(natural_breaks$abs_mort_cat, levels = c("Cluster 1 (Low)", "Cluster 2 (Mid)", "Cluster 3 (High)"))]

p1 <- ggplot(tertiles, aes(x = abs_mort, fill = abs_mort_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_TERTILE) +
  labs(title = "METHOD 1: Tertiles (Equal-Sized)",
       x = "Absolute Mortality (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

p2 <- ggplot(equal_width, aes(x = abs_mort, fill = abs_mort_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_EQUAL) +
  labs(title = "METHOD 2: Equal-Width",
       x = "Absolute Mortality (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

p3 <- ggplot(natural_breaks, aes(x = abs_mort, fill = abs_mort_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_NATURAL) +
  labs(title = "METHOD 3: Natural Breaks (±0.5 SD)",
       x = "Absolute Mortality (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

fig1 <- (p1 | p2 | p3) + plot_annotation(title = "Absolute Mortality Categorization Methods",
                                          theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA)))

ggsave(file.path(OUT_DIR, "01_abs_mort_comparison.png"), fig1,
       width = 280, height = 100, units = "mm", dpi = 300, bg = DARK_BG)

# Relative Mortality comparison
rel_mort_q33 <- as.numeric(quantile(site_metrics$rel_mort, 0.3333, na.rm = TRUE))
rel_mort_q67 <- as.numeric(quantile(site_metrics$rel_mort, 0.6667, na.rm = TRUE))
tertiles[, rel_mort_cat := factor(rel_mort_cat, levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
equal_width[, rel_mort_cat := factor(rel_mort_cat, levels = c("Bin 1 (Low)", "Bin 2 (Mid)", "Bin 3 (High)"))]
natural_breaks[, rel_mort_cat := factor(natural_breaks$rel_mort_cat, levels = c("Cluster 1 (Low)", "Cluster 2 (Mid)", "Cluster 3 (High)"))]

p4 <- ggplot(tertiles, aes(x = rel_mort, fill = rel_mort_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_TERTILE) +
  labs(title = "METHOD 1: Tertiles", x = "Relative Mortality (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

p5 <- ggplot(equal_width, aes(x = rel_mort, fill = rel_mort_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_EQUAL) +
  labs(title = "METHOD 2: Equal-Width", x = "Relative Mortality (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

p6 <- ggplot(natural_breaks, aes(x = rel_mort, fill = rel_mort_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_NATURAL) +
  labs(title = "METHOD 3: Natural Breaks", x = "Relative Mortality (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

fig2 <- (p4 | p5 | p6) + plot_annotation(title = "Relative Mortality Categorization Methods",
                                          theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA)))

ggsave(file.path(OUT_DIR, "02_rel_mort_comparison.png"), fig2,
       width = 280, height = 100, units = "mm", dpi = 300, bg = DARK_BG)

# Relative Disturbance comparison
rel_dist_q33 <- as.numeric(quantile(site_metrics$rel_dist, 0.3333, na.rm = TRUE))
rel_dist_q67 <- as.numeric(quantile(site_metrics$rel_dist, 0.6667, na.rm = TRUE))
tertiles[, rel_dist_cat := factor(rel_dist_cat, levels = c("Tertile 1 (Low)", "Tertile 2 (Mid)", "Tertile 3 (High)"))]
equal_width[, rel_dist_cat := factor(rel_dist_cat, levels = c("Bin 1 (Low)", "Bin 2 (Mid)", "Bin 3 (High)"))]
natural_breaks[, rel_dist_cat := factor(natural_breaks$rel_dist_cat, levels = c("Cluster 1 (Low)", "Cluster 2 (Mid)", "Cluster 3 (High)"))]

p7 <- ggplot(tertiles, aes(x = rel_dist, fill = rel_dist_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_TERTILE) +
  labs(title = "METHOD 1: Tertiles", x = "Relative Disturbance (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

p8 <- ggplot(equal_width, aes(x = rel_dist, fill = rel_dist_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_EQUAL) +
  labs(title = "METHOD 2: Equal-Width", x = "Relative Disturbance (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

p9 <- ggplot(natural_breaks, aes(x = rel_dist, fill = rel_dist_cat)) +
  geom_histogram(bins = 25, alpha = 0.7, colour = TEXT_COL, linewidth = 0.2) +
  scale_fill_manual(values = COLS_NATURAL) +
  labs(title = "METHOD 3: Natural Breaks", x = "Relative Disturbance (%)", y = "Count", fill = "") +
  dark_theme + theme(legend.position = "bottom")

fig3 <- (p7 | p8 | p9) + plot_annotation(title = "Relative Disturbance Categorization Methods",
                                          theme = theme(plot.background = element_rect(fill = DARK_BG, colour = NA)))

ggsave(file.path(OUT_DIR, "03_rel_dist_comparison.png"), fig3,
       width = 280, height = 100, units = "mm", dpi = 300, bg = DARK_BG)

cat("=== Categorization CSVs saved to derived_tables/disturbance_metric_test/ ===\n")
cat("- tertiles_method.csv\n")
cat("- equal_width_method.csv\n")
cat("- natural_breaks_method.csv\n\n")
cat("Comparison plots saved to", OUT_DIR, "\n")

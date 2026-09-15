#!/usr/bin/env Rscript
# ============================================================================
# Does spatial clustering of mortality (Moran's I, deadwood layer, 500m
# circular buffer) predict the DIRECTION of the disturbance SHAP effect?
# Same design/stats convention as Fig 5 panels D/E (linear fit + Spearman,
# BH-FDR across all tests in this figure). Exploratory, not yet folded into
# Fig 5 - kept as its own output until a decision is made on that.
# ============================================================================
suppressMessages({library(data.table); library(ggplot2); library(ggh4x)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B <- "derived_tables/outputs_afterEGU_results"
OUT <- "plots/V10/disturbance_split"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

BG <- "white"; GRID <- "#D9D9D9"; TXT <- "#111111"; AX <- "#444444"
EFP_ORDER <- c("GPPsat","NEPmax","ETmax","WUE")
EFP_LAB <- c(GPPsat="GPPsat  (µmol m⁻² s⁻¹)", NEPmax="NEPmax  (µmol m⁻² s⁻¹)",
             ETmax="ETmax  (mm d⁻¹)", WUE="WUE  (g C mm⁻¹)")

moran <- fread(sprintf("%s/morans_i_mortality_tc30.csv", B))
moran_site <- moran[, .(morans_i = mean(morans_i_500m, na.rm = TRUE)), by = SITE_ID]

sh <- fread(sprintf("%s/XGB_v10_true24m_optuna/XGB_site_signed_shap_M4.csv", B))
sh <- sh[group == "Disturbance" & response %in% EFP_ORDER]
setnames(sh, "mean_signed_shap", "dist_signed")
sh <- merge(sh, moran_site, by.x = "test_site", by.y = "SITE_ID")
sh[, window := factor(sub("M4_", "", model), levels = c("12m","24m"), labels = c("12 months","24 months"))]
sh[, response := factor(response, EFP_ORDER)]

stat <- sh[, {
  ct <- cor.test(morans_i, dist_signed, method = "spearman", exact = FALSE)
  list(rho = unname(ct$estimate), p = ct$p.value, n = .N)
}, by = .(window, response)]
stat[, q := p.adjust(p, method = "BH")]
stars <- function(q) fifelse(is.na(q), "", fifelse(q<0.001,"***", fifelse(q<0.01,"**", fifelse(q<0.05,"*"," ns"))))
stat[, lab := sprintf("rho=%.2f%s\nn=%d", rho, stars(q), n)]

th <- theme_bw(base_size = 11) + theme(
  plot.background = element_rect(fill = BG, colour = NA),
  panel.background = element_rect(fill = BG, colour = NA),
  panel.border = element_rect(colour = GRID, fill = NA, linewidth = 0.4),
  panel.grid.major = element_line(colour = GRID, linewidth = 0.2),
  panel.grid.minor = element_blank(),
  strip.background = element_rect(fill = "#EFEFEF", colour = GRID),
  strip.text = element_text(colour = TXT, size = 10, face = "bold"),
  axis.text = element_text(colour = AX, size = 9),
  axis.title = element_text(colour = AX, size = 10, face = "bold"),
  plot.title = element_text(colour = TXT, size = 14, face = "bold"),
  plot.subtitle = element_text(colour = AX, size = 9),
  plot.caption = element_text(colour = AX, size = 8, hjust = 0))

p <- ggplot(sh, aes(morans_i, dist_signed)) +
  geom_hline(yintercept = 0, colour = "#888888", linewidth = 0.35, linetype = "dashed") +
  geom_point(size = 1.3, alpha = 0.6, colour = "#2A6F97") +
  geom_smooth(method = "lm", formula = y ~ x, colour = "#222222", fill = "#444444",
              linewidth = 0.7, se = TRUE) +
  geom_text(data = stat, aes(x = -Inf, y = Inf, label = lab), inherit.aes = FALSE,
            hjust = -0.08, vjust = 1.3, size = 2.8, colour = TXT, fontface = "bold") +
  facet_grid2(window ~ response, scales = "free_y", independent = "y", labeller = labeller(response = EFP_LAB)) +
  labs(title = "Does spatial clustering of mortality predict the direction of the disturbance effect?",
       subtitle = "Moran's I (deadwood layer, rook contiguity, 500m circular buffer, site-level mean across years) vs net signed disturbance SHAP\ntree cover >= 30% (93 sites) | XGBoost-Optuna, M4 | linear fit with 95% CI | Spearman rho, BH-FDR across all 8 tests",
       x = "Moran's I of deadwood (500m buffer) — higher = more spatially clustered mortality",
       y = "Net signed disturbance SHAP (effect on PREDICTED value)",
       caption = "Below zero = model predicts a LOWER EFP value where mortality is present (not worse accuracy, see Fig 4).") +
  th

ggsave(file.path(OUT, "morans_i_vs_signed_shap.png"), p, width = 13, height = 7, dpi = 300, bg = BG)
ggsave(file.path(OUT, "morans_i_vs_signed_shap.pdf"), p, width = 13, height = 7, bg = BG)
fwrite(stat[order(window, response)], file.path(OUT, "morans_i_vs_signed_shap_stats.csv"))
cat("Saved:", file.path(OUT, "morans_i_vs_signed_shap.png"), "\n")
print(stat[order(window, response), .(window, response, rho = round(rho,3), q = signif(q,3), n)])

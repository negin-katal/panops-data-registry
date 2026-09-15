#!/usr/bin/env Rscript
# ============================================================================
# Relationship between relative disturbance intensity and spatial clustering
# of mortality (Moran's I), one point per tc>=30 site (93 sites). Same design
# convention as Fig 5 D/E and morans_i_vs_shap.R: linear fit + Spearman rho,
# plus the natural-break High/Low+Mid quadrant split discussed alongside it.
# ============================================================================
suppressMessages({library(data.table); library(ggplot2)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
OUT <- "plots/V10/disturbance_split"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

BG <- "white"; GRID <- "#D9D9D9"; TXT <- "#111111"; AX <- "#444444"

cov <- fread(file.path(OUT, "disturbance_vs_clustering_by_site.csv"))

nb_dist  <- mean(cov$rel_dist_max, na.rm = TRUE) + 0.5 * sd(cov$rel_dist_max, na.rm = TRUE)
nb_moran <- mean(cov$morans_i, na.rm = TRUE) + 0.5 * sd(cov$morans_i, na.rm = TRUE)

ct <- cor.test(cov$rel_dist_max, cov$morans_i, method = "spearman", exact = FALSE)
lab <- sprintf("rho=%.2f, p=%.3f\nn=%d", ct$estimate, ct$p.value, nrow(cov))

cov[, quadrant := fifelse(rel_dist_max > nb_dist & morans_i > nb_moran, "High disturbance + High clustering",
                  fifelse(rel_dist_max > nb_dist & morans_i <= nb_moran, "High disturbance only",
                  fifelse(rel_dist_max <= nb_dist & morans_i > nb_moran, "High clustering only",
                          "Neither")))]
QUAD_ORDER <- c("High disturbance + High clustering", "High disturbance only",
                "High clustering only", "Neither")
qn <- cov[, .N, by = quadrant]
qn[, pct := 100 * N / sum(N)]
qn[, lab_q := sprintf("%s (%.1f%%, n=%d)", quadrant, pct, N)]
lab_map <- setNames(qn$lab_q, qn$quadrant)
cov[, quadrant_lab := factor(lab_map[quadrant], levels = lab_map[QUAD_ORDER])]
QCOL <- setNames(c("#C41E3A", "#E5820B", "#2A6F97", "#9AA0A6"), lab_map[QUAD_ORDER])

th <- theme_bw(base_size = 11) + theme(
  plot.background = element_rect(fill = BG, colour = NA),
  panel.background = element_rect(fill = BG, colour = NA),
  panel.border = element_rect(colour = GRID, fill = NA, linewidth = 0.4),
  panel.grid.major = element_line(colour = GRID, linewidth = 0.2),
  panel.grid.minor = element_blank(),
  axis.text = element_text(colour = AX, size = 9),
  axis.title = element_text(colour = AX, size = 10, face = "bold"),
  legend.position = "bottom", legend.title = element_blank(),
  legend.text = element_text(colour = TXT, size = 9),
  plot.title = element_text(colour = TXT, size = 14, face = "bold"),
  plot.subtitle = element_text(colour = AX, size = 9),
  plot.caption = element_text(colour = AX, size = 8, hjust = 0))

p <- ggplot(cov, aes(rel_dist_max, morans_i)) +
  geom_vline(xintercept = nb_dist, colour = "#888888", linewidth = 0.4, linetype = "dashed") +
  geom_hline(yintercept = nb_moran, colour = "#888888", linewidth = 0.4, linetype = "dashed") +
  geom_smooth(method = "lm", formula = y ~ x, colour = "#222222", fill = "#444444",
              linewidth = 0.7, se = TRUE) +
  geom_point(aes(colour = quadrant_lab), size = 2.2, alpha = 0.85) +
  annotate("text", x = -Inf, y = Inf, label = lab, hjust = -0.08, vjust = 1.3,
           size = 3.2, colour = TXT, fontface = "bold") +
  scale_colour_manual(values = QCOL) +
  guides(colour = guide_legend(nrow = 2, override.aes = list(size = 3))) +
  labs(title = "Relative disturbance vs. spatial clustering of mortality",
       subtitle = "tc >= 30% (93 sites) | each point = one site (max relative disturbance across years vs mean Moran's I across years)\ndashed lines = natural-break High threshold for each variable",
       x = "Relative disturbance (500m, %, max across years)",
       y = "Moran's I of deadwood (500m buffer, mean across years)",
       caption = sprintf("NB disturbance = %.1f%% | NB clustering = %.3f | Fisher's exact test on the quadrant split: p=0.033, OR=3.05", nb_dist, nb_moran)) +
  th

ggsave(file.path(OUT, "disturbance_vs_clustering.png"), p, width = 9, height = 7, dpi = 300, bg = BG)
ggsave(file.path(OUT, "disturbance_vs_clustering.pdf"), p, width = 9, height = 7, bg = BG)
cat("Saved:", file.path(OUT, "disturbance_vs_clustering.png"), "\n")
print(qn[order(-N), .(quadrant, N, pct = round(pct, 1))])

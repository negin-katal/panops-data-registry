#!/usr/bin/env Rscript
# ============================================================================
# Coauthor draft — Fig 4: disturbance SHAP share grouped by disturbance category
# M4 (C+T+D), 93 sites, 4 EFPs, 3 Optuna learners. Tertile thresholds on the
# three 500 m mortality metrics, matching plots/V10 Section 9.
# ============================================================================
suppressMessages({library(data.table); library(ggplot2)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B <- "derived_tables/outputs_afterEGU_results"
OUT <- "manuscript_coauthor_draft/figures"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
CAT_COLS <- c(Low = "#22C4E0", Mid = "#F5A623", High = "#E8257A")

EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "WUE")
LEARNERS <- list(list(lab = "Random forest (Optuna)", d = "RF_v10_optuna",  fam = "RF"),
                 list(lab = "XGBoost (Optuna)",       d = "XGB_v10_optuna", fam = "XGB"),
                 list(lab = "LightGBM (Optuna)",      d = "LGB_v10_optuna", fam = "LGB"))
WIN <- "12m"

# ── disturbance categories: tertiles of each 500 m metric (as in Section 9) ──
h <- as.data.frame(fread(sprintf("%s/v10/v10_B1_GPPsat_harmonized.csv", B)))
mk <- function(v) { q <- quantile(v, c(1/3, 2/3), na.rm = TRUE)
                    factor(cut(v, c(-Inf, q[1], q[2], Inf), c("Low","Mid","High")),
                           levels = c("Low","Mid","High")) }
cats <- data.table(SITE_ID = h$SITE_ID,
                   `Absolute mortality`   = mk(h$absolute_mortality_500m),
                   `Relative mortality`   = mk(h$relative_mortality_500m),
                   `Relative disturbance` = mk(h$relative_disturbance_500m))
cats <- unique(cats, by = "SITE_ID")
catl <- melt(cats, id.vars = "SITE_ID", variable.name = "metric", value.name = "cat")

# ── per-site disturbance share of |SHAP| ────────────────────────────────────
dt <- rbindlist(lapply(LEARNERS, function(L) {
  s <- fread(sprintf("%s/%s/%s_site_shap_M04_M08.csv", B, L$d, L$fam))
  s <- s[model == paste0("M4_", WIN) & response %in% EFP_ORDER]
  # same RF_v10_optuna blank-trait-name fix as Fig 3 (see that script for the audit)
  s[variable == "" | is.na(variable), group := "Traits"]
  g <- s[, .(sh = sum(mean_abs_shap, na.rm = TRUE)), by = .(response, test_site, group)]
  g[, pct := 100 * sh / sum(sh), by = .(response, test_site)]
  g[group == "Disturbance", .(response, SITE_ID = test_site, dist_pct = pct, learner = L$lab)]
}))
dt <- merge(dt, catl, by = "SITE_ID", allow.cartesian = TRUE)
dt <- dt[!is.na(cat)]
dt[, response := factor(response, levels = EFP_ORDER)]
dt[, learner  := factor(learner, levels = sapply(LEARNERS, `[[`, "lab"))]

# Kruskal-Wallis across the three categories, BH-FDR over the whole figure
st <- dt[, .(p = tryCatch(kruskal.test(dist_pct ~ cat)$p.value, error = function(e) NA_real_)),
         by = .(learner, response, metric)]
st[, q := p.adjust(p, method = "BH")]
st[, sig := ifelse(is.na(q), "", ifelse(q < 0.001, "***", ifelse(q < 0.01, "**",
             ifelse(q < 0.05, "*", "ns"))))]
ytop <- dt[, .(yt = quantile(dist_pct, 0.98, na.rm = TRUE)), by = response]
st <- merge(st, ytop, by = "response")

th <- theme_bw(base_size = 11) + theme(
  plot.background = element_rect(fill = DARK_BG, colour = NA),
  panel.background = element_rect(fill = PANEL_BG, colour = NA),
  panel.border = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.4),
  panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
  panel.grid.minor = element_blank(),
  strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
  strip.text = element_text(colour = TEXT_COL, size = 9.5, face = "bold"),
  axis.text = element_text(colour = AXIS_COL, size = 9),
  axis.title = element_text(colour = AXIS_COL, size = 10, face = "bold"),
  legend.background = element_rect(fill = NA, colour = NA),
  legend.key = element_rect(fill = NA, colour = NA),
  legend.text = element_text(colour = TEXT_COL, size = 11),
  legend.title = element_blank(), legend.position = "bottom",
  plot.title = element_text(colour = TEXT_COL, size = 14, face = "bold"),
  plot.subtitle = element_text(colour = AXIS_COL, size = 9))

p <- ggplot(dt, aes(x = metric, y = dist_pct, fill = cat)) +
  geom_violin(position = position_dodge(width = 0.85), colour = NA, width = 0.8,
              alpha = 0.75, trim = TRUE) +
  geom_boxplot(aes(group = interaction(metric, cat)), position = position_dodge(width = 0.85),
               width = 0.13, outlier.shape = NA, colour = "white", fill = NA, linewidth = 0.28) +
  geom_text(data = st, aes(x = metric, y = yt * 1.06, label = sig), inherit.aes = FALSE,
            colour = "white", size = 3, fontface = "bold") +
  scale_fill_manual(values = CAT_COLS) +
  facet_grid(response ~ learner, scales = "free_y", switch = "y") +
  labs(x = NULL, y = "Disturbance share of |SHAP| (%)",
       title = sprintf("Disturbance SHAP share by disturbance category — M4, %s window", WIN),
       subtitle = paste0("Tree cover ≥30 % (93 sites) · tertile thresholds on each 500 m mortality metric · ",
                         "stars = Kruskal-Wallis across Low/Mid/High, BH-FDR across the figure")) +
  th + theme(strip.placement = "outside") +
  guides(fill = guide_legend(override.aes = list(alpha = 0.9)))

ggsave(file.path(OUT, "fig4_grouped_disturbance_shap.png"), p, width = 15, height = 11, dpi = 300, bg = DARK_BG)
ggsave(file.path(OUT, "fig4_grouped_disturbance_shap.pdf"), p, width = 15, height = 11, bg = DARK_BG)
fwrite(st[, .(learner, response, metric, p = signif(p,3), q = signif(q,3), sig)],
       "manuscript_coauthor_draft/fig4_statistics.csv")
cat(sprintf("\nFig 4 saved | %d sites | %d tests\n", uniqueN(dt$SITE_ID), nrow(st)))

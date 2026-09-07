#!/usr/bin/env Rscript
# ============================================================================
# Coauthor draft — Fig 3: per-site SHAP composition for M4 (C+T+D)
# Filtered from the existing V10 SHAP tables. 93 sites, 4 EFPs, 3 Optuna learners.
# SHAP comes from full-data models, so it is identical under both CV structures.
# ============================================================================
suppressMessages({library(data.table); library(ggplot2)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B <- "derived_tables/outputs_afterEGU_results"
OUT <- "manuscript_coauthor_draft/figures"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
GRP_COLS <- c(Climate = "#4A90D9", Traits = "#F5A623", Disturbance = "#E8257A")

EFP_ORDER  <- c("GPPsat", "NEPmax", "ETmax", "WUE")
EFP_LABELS <- c(GPPsat = "GPPsat", NEPmax = "NEPmax", ETmax = "ETmax", WUE = "WUE")
LEARNERS <- list(list(lab = "Random forest (Optuna)", d = "RF_v10_optuna",  fam = "RF"),
                 list(lab = "XGBoost (Optuna)",       d = "XGB_v10_optuna", fam = "XGB"),
                 list(lab = "LightGBM (Optuna)",      d = "LGB_v10_optuna", fam = "LGB"))
WIN <- "12m"

dt <- rbindlist(lapply(LEARNERS, function(L) {
  s <- fread(sprintf("%s/%s/%s_site_shap_M04_M08.csv", B, L$d, L$fam))
  s <- s[model == paste0("M4_", WIN) & response %in% EFP_ORDER]
  # DATA FIX: RF_v10_optuna's SHAP table lost the names of the 14 trait columns whose
  # names contain spaces, parentheses or slashes ("Leaf C", "Leaf N (area)", ...), so
  # treeshap emitted them blank and they fell into an "Other" group carrying ~35% of the
  # attribution. Verified: 14 blank per site + 7 named traits = the 21 traits the clean
  # learners show. Group membership is therefore unambiguous even though the individual
  # names are gone, and these figures are group-level, so reassign them to Traits.
  s[variable == "" | is.na(variable), group := "Traits"]
  g <- s[, .(sh = sum(mean_abs_shap, na.rm = TRUE)), by = .(response, test_site, group)]
  g[, pct := 100 * sh / sum(sh), by = .(response, test_site)]
  g[, learner := L$lab][]
}))

# order sites by disturbance share within each EFP (pooled across learners) so the
# gradient is comparable left-to-right in every panel
ord <- dt[group == "Disturbance", .(m = mean(pct)), by = .(response, test_site)]
dt <- merge(dt, ord, by = c("response", "test_site"))
dt[, site_f := factor(test_site, levels = unique(test_site[order(m)])), by = response]

dt[, response := factor(response, levels = EFP_ORDER)]
dt[, learner := factor(learner, levels = sapply(LEARNERS, `[[`, "lab"))]
dt[, group := factor(group, levels = c("Climate", "Traits", "Disturbance"))]

med <- dt[group == "Disturbance", .(lab = sprintf("median D = %.0f%%", median(pct))),
          by = .(response, learner)]

th <- theme_bw(base_size = 11) + theme(
  plot.background = element_rect(fill = DARK_BG, colour = NA),
  panel.background = element_rect(fill = PANEL_BG, colour = NA),
  panel.border = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.4),
  panel.grid = element_blank(),
  strip.background = element_rect(fill = "#1A1A1A", colour = GRID_COL),
  strip.text = element_text(colour = TEXT_COL, size = 10, face = "bold"),
  axis.text.x = element_blank(), axis.ticks.x = element_blank(),
  axis.text.y = element_text(colour = AXIS_COL, size = 9),
  axis.title = element_text(colour = AXIS_COL, size = 10, face = "bold"),
  legend.background = element_rect(fill = NA, colour = NA),
  legend.key = element_rect(fill = NA, colour = NA),
  legend.text = element_text(colour = TEXT_COL, size = 11),
  legend.title = element_blank(), legend.position = "bottom",
  plot.title = element_text(colour = TEXT_COL, size = 14, face = "bold"),
  plot.subtitle = element_text(colour = AXIS_COL, size = 9))

p <- ggplot(dt, aes(x = site_f, y = pct, fill = group)) +
  geom_col(width = 1) +
  geom_text(data = med, aes(x = 4, y = 92, label = lab), inherit.aes = FALSE,
            colour = "white", size = 3, hjust = 0, fontface = "bold") +
  scale_fill_manual(values = GRP_COLS) +
  scale_y_continuous(expand = c(0, 0)) +
  facet_grid(response ~ learner, labeller = labeller(response = EFP_LABELS), switch = "y") +
  labs(x = "Sites (93), ordered by disturbance share", y = "Share of |SHAP| (%)",
       title = sprintf("Per-site SHAP composition — M4 (climate + traits + disturbance), %s window", WIN),
       subtitle = paste0("Tree cover ≥30 % (93 sites) · each bar is one site · SHAP from full-data models, ",
                         "so identical under both cross-validation structures")) +
  th + theme(strip.placement = "outside")

ggsave(file.path(OUT, "fig3_site_shap_composition.png"), p, width = 15, height = 10, dpi = 300, bg = DARK_BG)
ggsave(file.path(OUT, "fig3_site_shap_composition.pdf"), p, width = 15, height = 10, bg = DARK_BG)
fwrite(dcast(dt[, .(pct = mean(pct)), by = .(learner, response, group)],
             learner + response ~ group, value.var = "pct"),
       "manuscript_coauthor_draft/fig3_shap_shares.csv")
cat(sprintf("\nFig 3 saved | %d sites | %d panels\n", uniqueN(dt$test_site),
            uniqueN(dt$response) * uniqueN(dt$learner)))

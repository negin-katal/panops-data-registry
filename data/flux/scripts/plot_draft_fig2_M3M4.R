#!/usr/bin/env Rscript
# ============================================================================
# Coauthor draft — Fig 2: effect of adding disturbance (M3 -> M4) on per-site RMSE
#
# Filtered from the existing V10 results. Scope fixed for this draft:
#   dataset  tree cover >=30 % (93 sites)
#   models   M3 (C+T) vs M4 (C+T+D) only
#   EFPs     GPPsat, NEPmax, ETmax, WUE   (uWUE dropped)
#   learners RF / XGBoost / LightGBM, all Optuna-tuned
#   windows  12 m and 24 m, under BOTH leave-one-site-out and repeated CV
#
# Style follows plots/V10 Section 3 (paired violin, same colours and statistics).
# ============================================================================
suppressMessages({library(data.table); library(ggplot2); library(ggh4x)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

B <- "derived_tables/outputs_afterEGU_results"
OUT <- "manuscript_coauthor_draft/figures"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

DARK_BG <- "white"; PANEL_BG <- "white"; GRID_COL <- "#D9D9D9"
TEXT_COL <- "#111111"; AXIS_COL <- "#444444"
COL_WO <- "#22C4E0"; COL_W <- "#E8257A"
COL_UP <- "#2ECC71"; COL_NC <- "#9AA0A6"; COL_DN <- "#E74C3C"

EFP_ORDER  <- c("GPPsat", "NEPmax", "ETmax", "WUE")
EFP_LABELS <- c(GPPsat = "GPPsat  (µmol m⁻² s⁻¹)", NEPmax = "NEPmax  (µmol m⁻² s⁻¹)",
                ETmax  = "ETmax  (mm d⁻¹)",         WUE    = "WUE  (g C mm⁻¹)")

LEARNERS <- list(
  list(lab = "Random forest (Optuna)", loo = "RF_v10_optuna",  rep = "RF_optuna_repCV",  fam = "RF"),
  list(lab = "XGBoost (Optuna)",       loo = "XGB_v10_optuna", rep = "XGB_optuna_repCV", fam = "XGB"),
  list(lab = "LightGBM (Optuna)",      loo = "LGB_v10_optuna", rep = "LGB_optuna_repCV", fam = "LGB"))

site_rmse <- function(f) {
  p <- fread(f)
  p[, .(rmse = sqrt(mean((observed - predicted)^2))), by = .(model, response, SITE_ID)]
}

rows <- list(); labs <- list(); k <- 1; lk <- 1
for (L in LEARNERS) {
  for (cv in c("LOSO", "Repeated CV")) {
    d <- if (cv == "LOSO") L$loo else L$rep
    sr <- site_rmse(sprintf("%s/%s/%s_predictions_LOSO.csv", B, d, L$fam))
    for (w in c("12m", "24m")) {
      for (resp in EFP_ORDER) {
        a <- sr[model == paste0("M3_", w) & response == resp, .(SITE_ID, wo = rmse)]
        b <- sr[model == paste0("M4_", w) & response == resp, .(SITE_ID, wd = rmse)]
        pw <- merge(a, b, by = "SITE_ID")          # pair explicitly on site
        pw <- pw[is.finite(wo) & is.finite(wd)]
        if (!nrow(pw)) next
        grp <- sprintf("%s\n%s", w, ifelse(cv == "LOSO", "LOO", "rep"))
        rows[[k]] <- data.table(response = resp, learner = L$lab, grp = grp,
                                model_type = "Without D (M3)", rmse = pw$wo); k <- k + 1
        rows[[k]] <- data.table(response = resp, learner = L$lab, grp = grp,
                                model_type = "With D (M4)",    rmse = pw$wd); k <- k + 1
        pct  <- median((pw$wd - pw$wo) / pw$wo * 100)
        pval <- wilcox.test(pw$wd, pw$wo, paired = TRUE, alternative = "less", exact = FALSE)$p.value
        labs[[lk]] <- data.table(response = resp, learner = L$lab, grp = grp,
                                 pct = pct, p = pval,
                                 imp = mean(pw$wd < pw$wo) * 100); lk <- lk + 1
      }
    }
  }
}
dt   <- rbindlist(rows)
labs <- rbindlist(labs)
labs[, q := p.adjust(p, method = "BH")]            # FDR across every test in the figure
labs[, sig := ifelse(q < 0.001, "***", ifelse(q < 0.01, "**", ifelse(q < 0.05, "*", "ns")))]
labs[, lcol := ifelse(pct < 0 & q < 0.05, COL_UP, ifelse(pct > 0, COL_DN, COL_NC))]
labs[, label := sprintf("%+.1f%%%s\n%.0f%%↓", pct, sig, imp)]

dt[, response := factor(response, levels = EFP_ORDER)]
labs[, response := factor(response, levels = EFP_ORDER)]
LEV <- c("12m\nLOO", "24m\nLOO", "12m\nrep", "24m\nrep")
dt[, grp := factor(grp, levels = LEV)]; labs[, grp := factor(grp, levels = LEV)]
dt[, learner := factor(learner, levels = sapply(LEARNERS, `[[`, "lab"))]
labs[, learner := factor(learner, levels = sapply(LEARNERS, `[[`, "lab"))]
dt[, model_type := factor(model_type, levels = c("Without D (M3)", "With D (M4)"))]

# view limit: p95 per EFP row, applied as a ZOOM (oob_keep) so densities and all
# statistics are still computed on every site
ymax <- dt[, .(ytop = quantile(rmse, 0.95, na.rm = TRUE)), by = response]
labs <- merge(labs, ymax, by = "response")
labs[, ylab := ytop * 0.94]

th <- theme_bw(base_size = 11) + theme(
  plot.background = element_rect(fill = DARK_BG, colour = NA),
  panel.background = element_rect(fill = PANEL_BG, colour = NA),
  panel.border = element_rect(colour = GRID_COL, fill = NA, linewidth = 0.4),
  panel.grid.major = element_line(colour = GRID_COL, linewidth = 0.2),
  panel.grid.minor = element_blank(),
  strip.background = element_rect(fill = "#EFEFEF", colour = GRID_COL),
  strip.text = element_text(colour = TEXT_COL, size = 10, face = "bold"),
  axis.text.x = element_text(colour = AXIS_COL, size = 8),
  axis.text.y = element_text(colour = AXIS_COL, size = 9),
  legend.background = element_rect(fill = NA, colour = NA),
  legend.key = element_rect(fill = NA, colour = NA),
  legend.text = element_text(colour = TEXT_COL, size = 11),
  legend.title = element_blank(), legend.position = "bottom",
  plot.title = element_text(colour = TEXT_COL, size = 14, face = "bold"),
  plot.subtitle = element_text(colour = AXIS_COL, size = 9))

p <- ggplot(dt, aes(x = grp, y = rmse, fill = model_type)) +
  geom_violin(position = position_dodge(width = 0.8), colour = NA,
              width = 0.78, alpha = 0.75, trim = TRUE) +
  geom_boxplot(aes(group = interaction(grp, model_type)),
               position = position_dodge(width = 0.8), width = 0.15,
               outlier.shape = NA, colour = "#222222", fill = NA, linewidth = 0.3) +
  geom_text(data = labs, aes(x = grp, y = ylab, label = label, colour = lcol),
            inherit.aes = FALSE, size = 2.5, fontface = "bold") +
  scale_fill_manual(values = setNames(c(COL_WO, COL_W), c("Without D (M3)", "With D (M4)"))) +
  scale_colour_identity() +
  facet_grid(response ~ learner, scales = "free_y",
             labeller = labeller(response = EFP_LABELS), switch = "y") +
  ggh4x::facetted_pos_scales(
    y = lapply(EFP_ORDER, function(r)
      scale_y_continuous(limits = c(0, ymax[response == r, ytop] * 1.08),
                         oob = scales::oob_keep))) +
  coord_cartesian(clip = "on") +
  labs(x = NULL, y = NULL,
       title = "Effect of adding disturbance predictors (M3 → M4) on per-site RMSE",
       subtitle = paste0("Tree cover ≥30 % (93 sites) · C+T vs C+T+D · cyan = without D, pink = with D\n",
                         "% = median PAIRED change in per-site RMSE (negative = less error) · ",
                         "stars = one-sided paired Wilcoxon, BH-FDR across the figure (*** q<0.001, ** q<0.01, * q<0.05)\n",
                         "%↓ = share of sites whose RMSE improved · y axis zoomed to the 95th percentile (no data removed)")) +
  th + theme(strip.placement = "outside") +
  guides(colour = "none", fill = guide_legend(override.aes = list(alpha = 0.9)))

ggsave(file.path(OUT, "fig2_disturbance_effect_M3M4.png"), p, width = 15, height = 12, dpi = 300, bg = DARK_BG)
ggsave(file.path(OUT, "fig2_disturbance_effect_M3M4.pdf"), p, width = 15, height = 12, bg = DARK_BG)
fwrite(labs[, .(learner, response, grp, median_pct = round(pct,2), sites_improved = round(imp,1),
                p = signif(p,3), q = signif(q,3), sig)],
       "manuscript_coauthor_draft/fig2_statistics.csv")
cat(sprintf("\nFig 2 saved | %d sites | %d panels | %d tests\n",
            uniqueN(fread(sprintf("%s/XGB_v10_optuna/XGB_predictions_LOSO.csv", B))$SITE_ID),
            uniqueN(dt$response) * uniqueN(dt$learner), nrow(labs)))

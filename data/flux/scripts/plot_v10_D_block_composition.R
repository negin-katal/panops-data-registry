#!/usr/bin/env Rscript
# ============================================================================
# Composition of the disturbance block: how much of the D-block SHAP comes from
# forest-cover-change information vs standing-mortality information?
#
# No retraining. Re-aggregates the variable-level TreeSHAP already written by
# the M4 runs ({FAM}_site_shap_M04_M08.csv), renormalised so the D block = 100%.
#
# Two normalisations are plotted side by side, because they answer different
# questions and disagree:
#   share      - how much of the disturbance signal the block carries in total
#   per var    - share / number of variables in the block; removes the fact that
#                mortality simply contributes more columns (60 vs 30)
#
# Output: plots/V10/disturbance_split/   (its own folder - the report tree and
#         the manuscript figures are never touched)
# ============================================================================
suppressMessages({library(data.table); library(ggplot2)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B   <- "derived_tables/outputs_afterEGU_results"
OUT <- "plots/V10/disturbance_split"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

BG <- "white"; GRID <- "#D9D9D9"; TXT <- "#111111"; AX <- "#444444"
EFP_ORDER <- c("GPPsat", "NEPmax", "ETmax", "WUE")
LEARNERS <- list(list(lab = "XGBoost (Optuna)",  d = "XGB_v10_optuna", fam = "XGB"),
                 list(lab = "Random Forest (Optuna)", d = "RF_v10_optuna", fam = "RF"),
                 list(lab = "LightGBM (Optuna)", d = "LGB_v10_optuna", fam = "LGB"))

D_RE <- "^(absolute_|relative_|new_|mortality_|disturbance_)"
# family = drop the buffer and lag suffix, keep the _thresh distinction
famof <- function(v) sub("_[0-9]+00m(_lag[12])?$", "", v)
concept <- function(f)
  fifelse(grepl("^absolute_mortality|^relative_mortality|^new_mortality_rate|^new_deadwood_gain", f),
          "Standing mortality / deadwood",
  fifelse(grepl("^relative_tree_loss|^mortality_loss_severity", f),
          "Forest cover change",
          "Combined index (rho = 0.97 with rel. mortality)"))
CC_ORDER <- c("Standing mortality / deadwood", "Forest cover change",
              "Combined index (rho = 0.97 with rel. mortality)")
CC_COLS  <- c("#D1495B", "#2A9D8F", "#9AA0A6"); names(CC_COLS) <- CC_ORDER

th <- theme_bw(base_size = 11) + theme(
  plot.background = element_rect(fill = BG, colour = NA),
  panel.background = element_rect(fill = BG, colour = NA),
  panel.border = element_rect(colour = GRID, fill = NA, linewidth = 0.4),
  panel.grid.major.y = element_blank(),
  panel.grid.major.x = element_line(colour = GRID, linewidth = 0.2),
  panel.grid.minor = element_blank(),
  strip.background = element_rect(fill = "#EFEFEF", colour = GRID),
  strip.text = element_text(colour = TXT, size = 10, face = "bold"),
  axis.text = element_text(colour = AX, size = 9),
  axis.title = element_text(colour = AX, size = 10, face = "bold"),
  legend.position = "bottom", legend.title = element_blank(),
  legend.background = element_rect(fill = NA, colour = NA),
  legend.key = element_rect(fill = NA, colour = NA),
  legend.text = element_text(colour = TXT, size = 10),
  plot.title = element_text(colour = TXT, size = 14, face = "bold"),
  plot.subtitle = element_text(colour = AX, size = 9),
  plot.caption = element_text(colour = AX, size = 8, hjust = 0))

tables <- list()
for (L in LEARNERS) {
  f <- sprintf("%s/%s/%s_site_shap_M04_M08.csv", B, L$d, L$fam)
  if (!file.exists(f)) { message("missing: ", f); next }
  s <- fread(f)[model %in% c("M4_12m", "M4_24m") & response %in% EFP_ORDER]
  s <- s[grepl(D_RE, variable)]
  stopifnot(nrow(s) > 0)
  s[, family := famof(variable)][, cc := concept(family)]

  nvar <- unique(s[, .(variable, family, cc)])
  nv_fam <- nvar[, .(n_vars = .N), by = .(family, cc)]
  nv_cc  <- nvar[, .(n_vars = .N), by = cc]

  s[, window := factor(sub("M4_", "", model), levels = c("12m", "24m"),
                       labels = c("12 months", "24 months"))]
  tot <- s[, .(tot = sum(mean_abs_shap)), by = .(window, response, test_site)]

  agg <- function(by) {
    a <- s[, .(v = sum(mean_abs_shap)), by = c("window", "response", "test_site", by)]
    a <- merge(a, tot, by = c("window", "response", "test_site"))
    a[, share := 100 * v / tot]
    a[, .(share = mean(share), se = sd(share) / sqrt(.N)),
      by = c("window", "response", by)]
  }
  by_cc  <- merge(agg("cc"),     nv_cc,  by = "cc")
  by_fam <- merge(agg("family"), nv_fam, by = "family")
  by_cc[,  per_var := share / n_vars]
  by_fam[, per_var := share / n_vars]
  by_cc[,  learner := L$lab]; by_fam[, learner := L$lab]
  tables[[L$lab]] <- list(cc = by_cc, fam = by_fam)

  ## ---- Figure 1: two sub-blocks, both normalisations ----------------------
  m <- melt(by_cc, id.vars = c("window", "response", "cc", "n_vars"),
            measure.vars = c("share", "per_var"), variable.name = "norm")
  m[, norm := factor(norm, c("share", "per_var"),
                     c("% of D-block |SHAP|",
                       "per variable  (% / variable)"))]
  m[, response := factor(response, EFP_ORDER)]
  m[, cc := factor(cc, CC_ORDER)]
  m[, lab := sprintf("%s (%d vars)", sub(" /.*| \\(rho.*", "", cc), n_vars)]

  p <- ggplot(m, aes(response, value, fill = cc)) +
    geom_col(position = position_dodge(0.78), width = 0.7) +
    geom_text(aes(label = sprintf("%.1f", value)), position = position_dodge(0.78),
              vjust = -0.35, size = 2.5, colour = AX) +
    facet_grid(norm ~ window, scales = "free_y", switch = "y") +
    scale_fill_manual(values = CC_COLS) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.14))) +
    labs(title = "What kind of disturbance information does the model use?",
         subtitle = paste0(L$lab, " · M4 (C+T+D) · tree cover >= 30% (93 sites, 395 site-years)",
                           "\nDisturbance block renormalised to 100%; mean over the 93 held-out sites"),
         x = NULL, y = NULL,
         caption = paste("Top row: total share of the disturbance signal. Mortality carries more variables (60 vs 30),",
                         "so the bottom row divides\nby block size - the fair comparison. |SHAP| is magnitude only, not direction.")) +
    th + theme(panel.grid.major.x = element_blank(),
               panel.grid.major.y = element_line(colour = GRID, linewidth = 0.2),
               strip.placement = "outside",
               strip.background.y = element_blank(),
               strip.text.y.left = element_text(angle = 90, size = 10, face = "bold",
                                                colour = TXT, margin = margin(r = 6)),
               plot.margin = margin(10, 14, 8, 10))
  ggsave(sprintf("%s/D_composition_concept_%s.png", OUT, L$fam), p,
         width = 10, height = 7.5, dpi = 320, bg = BG)

  ## ---- Figure 2: metric-family detail -------------------------------------
  by_fam[, response := factor(response, EFP_ORDER)]
  by_fam[, cc := factor(cc, CC_ORDER)]
  ord <- by_fam[, .(m = mean(share)), by = family][order(m)]$family
  by_fam[, family := factor(family, ord)]
  p2 <- ggplot(by_fam, aes(family, share, fill = cc)) +
    geom_col(width = 0.72) +
    geom_errorbar(aes(ymin = share - se, ymax = share + se), width = 0, linewidth = 0.3,
                  colour = AX) +
    geom_text(aes(label = sprintf("%.1f  (n=%d)", share, n_vars)), hjust = -0.1,
              size = 2.3, colour = AX) +
    coord_flip() +
    facet_grid(response ~ window) +
    scale_fill_manual(values = CC_COLS) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.30))) +
    labs(title = "Disturbance block, metric by metric",
         subtitle = paste0(L$lab, " · M4 · tree cover >= 30% · share of the disturbance-block |SHAP| (%)",
                           "\nn = variables contributed by that metric (5 buffers x current+lag1)"),
         x = NULL, y = "% of disturbance-block |SHAP|") +
    th
  ggsave(sprintf("%s/D_composition_family_%s.png", OUT, L$fam), p2,
         width = 11, height = 9.5, dpi = 320, bg = BG)
  message("  written: ", L$fam)
}

cc  <- rbindlist(lapply(tables, `[[`, "cc"))
fam <- rbindlist(lapply(tables, `[[`, "fam"))
fwrite(cc,  sprintf("%s/D_composition_by_concept.csv", OUT))
fwrite(fam, sprintf("%s/D_composition_by_family.csv", OUT))

cat("\n=== XGBoost (Optuna), share of the disturbance block (%) ===\n")
print(dcast(cc[learner == "XGBoost (Optuna)"], window + response ~ cc,
            value.var = "share"), digits = 3)
cat("\n=== same, per variable ===\n")
print(dcast(cc[learner == "XGBoost (Optuna)"], window + response ~ cc,
            value.var = "per_var"), digits = 3)
cat("\nfigures + csv in", OUT, "\n")

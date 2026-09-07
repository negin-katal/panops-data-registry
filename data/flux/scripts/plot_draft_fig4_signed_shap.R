#!/usr/bin/env Rscript
# ============================================================================
# Coauthor draft — directional counterpart to Figure 4.
#
# Figure 4 plots the disturbance share of |SHAP|: how much the block matters.
# This plots the NET SIGNED contribution of the disturbance block, in response
# units, so the y axis runs negative to positive:
#   negative = disturbance pulls the prediction DOWN at that site
#   positive = disturbance pushes it UP
# Categories and thresholds match Figure 4 (natural breaks, Low+Mid vs High).
# ============================================================================
suppressMessages({library(data.table); library(ggplot2)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B <- "derived_tables/outputs_afterEGU_results"
OUT <- "manuscript_coauthor_draft/figures"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

DARK_BG <- "#0D0D0D"; PANEL_BG <- "#111111"; GRID_COL <- "#333333"
TEXT_COL <- "#FFFFFF"; AXIS_COL <- "#CCCCCC"
CAT_COLS <- c("Low+Mid" = "#22C4E0", "High" = "#E8257A")
EFP_ORDER <- c("GPPsat","NEPmax","ETmax","WUE")
EFP_LAB <- c(GPPsat="GPPsat  (µmol m⁻² s⁻¹)", NEPmax="NEPmax  (µmol m⁻² s⁻¹)",
             ETmax="ETmax  (mm d⁻¹)", WUE="WUE  (g C mm⁻¹)")

LEARNERS <- list(list(lab="Random forest (Optuna)", d="RF_v10_optuna",  fam="RF"),
                 list(lab="XGBoost (Optuna)",       d="XGB_v10_optuna", fam="XGB"),
                 list(lab="LightGBM (Optuna)",      d="LGB_v10_optuna", fam="LGB"))
d <- rbindlist(lapply(LEARNERS, function(L) {
  f <- sprintf("%s/%s/%s_site_signed_shap_M4.csv", B, L$d, L$fam)
  if (!file.exists(f)) { message("missing: ", f); return(NULL) }
  x <- fread(f); x[, learner := L$lab][]
}))
d <- d[group == "Disturbance" & response %in% EFP_ORDER]
d[, learner := factor(learner, levels = sapply(LEARNERS, `[[`, "lab"))]

# natural-breaks categories on the three 500 m metrics, as in Figure 4
h <- as.data.frame(fread(sprintf("%s/v10/v10_B1_GPPsat_harmonized.csv", B)))
nb <- function(v){m<-mean(v,na.rm=TRUE); s<-sd(v,na.rm=TRUE)
  factor(cut(v, c(-Inf, m-0.5*s, m+0.5*s, Inf), c("Low","Mid","High")), levels=c("Low","Mid","High"))}
cats <- unique(data.table(SITE_ID = h$SITE_ID,
                          `Absolute\nmortality`   = nb(h$absolute_mortality_500m),
                          `Relative\nmortality`   = nb(h$relative_mortality_500m),
                          `Relative\ndisturbance` = nb(h$relative_disturbance_500m)), by="SITE_ID")
catl <- melt(cats, id.vars="SITE_ID", variable.name="metric", value.name="cat")
catl[, cat2 := factor(ifelse(cat=="High","High","Low+Mid"), levels=c("Low+Mid","High"))]

dt <- merge(d, catl, by.x="test_site", by.y="SITE_ID", allow.cartesian=TRUE)[!is.na(cat2)]
dt[, response := factor(response, levels=EFP_ORDER)]
dt[, window := factor(sub("M4_","",model), levels=c("12m","24m"))]

# one-sample test: is the net contribution different from zero?
st <- dt[, .(p = tryCatch(wilcox.test(mean_signed_shap, mu=0)$p.value, error=function(e) NA_real_),
             med = median(mean_signed_shap), neg = mean(mean_signed_shap < 0)*100),
         by=.(response, window, metric, cat2, learner)]
st[, q := p.adjust(p, "BH")]
st[, sig := ifelse(is.na(q),"",ifelse(q<0.001,"***",ifelse(q<0.01,"**",ifelse(q<0.05,"*","ns"))))]
yr <- dt[, .(lo=quantile(mean_signed_shap,0.02), hi=quantile(mean_signed_shap,0.98)), by=.(response,learner)]
st <- merge(st, yr, by=c("response","learner"))

th <- theme_bw(base_size=11) + theme(
  plot.background=element_rect(fill=DARK_BG,colour=NA), panel.background=element_rect(fill=PANEL_BG,colour=NA),
  panel.border=element_rect(colour=GRID_COL,fill=NA,linewidth=0.4),
  panel.grid.major=element_line(colour=GRID_COL,linewidth=0.2), panel.grid.minor=element_blank(),
  strip.background=element_rect(fill="#1A1A1A",colour=GRID_COL),
  strip.text=element_text(colour=TEXT_COL,size=9.5,face="bold"),
  axis.text.x=element_text(colour=AXIS_COL,size=8,lineheight=0.9),
  axis.text.y=element_text(colour=AXIS_COL,size=8.5), axis.title=element_text(colour=AXIS_COL,size=10,face="bold"),
  legend.background=element_rect(fill=NA,colour=NA), legend.key=element_rect(fill=NA,colour=NA),
  legend.text=element_text(colour=TEXT_COL,size=11), legend.title=element_blank(), legend.position="bottom",
  plot.title=element_text(colour=TEXT_COL,size=14,face="bold"),
  plot.subtitle=element_text(colour=AXIS_COL,size=9))

for (w in c("12m","24m")) {
  sub <- dt[window==w]; sst <- st[window==w]
  p <- ggplot(sub, aes(x=metric, y=mean_signed_shap, fill=cat2)) +
    geom_hline(yintercept=0, colour="#888888", linewidth=0.5) +
    geom_violin(position=position_dodge(width=0.85), colour=NA, width=0.8, alpha=0.75, trim=TRUE) +
    geom_boxplot(aes(group=interaction(metric,cat2)), position=position_dodge(width=0.85),
                 width=0.13, outlier.shape=NA, colour="white", fill=NA, linewidth=0.28) +
    geom_text(data=sst, aes(x=metric, y=hi*1.10, label=sig, group=cat2),
              position=position_dodge(width=0.85), inherit.aes=FALSE, colour="white", size=3, fontface="bold") +
    scale_fill_manual(values=CAT_COLS) +
    facet_grid(learner ~ response, scales="free_y",
               labeller=labeller(response=EFP_LAB)) +
    labs(x=NULL, y="Net signed disturbance SHAP  (response units)",
         title=sprintf("Direction of the disturbance effect — M4, %s window", w),
         subtitle=paste0("Tree cover ≥30 % (93 sites) · net signed contribution of the ",
                         "disturbance block per site\nbelow zero = disturbance pulls the prediction DOWN · ",
                         "natural-breaks thresholds · stars = Wilcoxon vs zero, BH-FDR")) +
    th
  ggsave(file.path(OUT, sprintf("fig4_signed_shap_%s.png", w)), p, width=15, height=13, dpi=300, bg=DARK_BG)
  ggsave(file.path(OUT, sprintf("fig4_signed_shap_%s.pdf", w)), p, width=15, height=13, bg=DARK_BG)
}
fwrite(st[, .(learner,response,window,metric,cat2,median=round(med,3),pct_negative=round(neg,1),
              p=signif(p,3), q=signif(q,3), sig)], "manuscript_coauthor_draft/fig4_statistics.csv")
cat("\nFig 4 (directional) saved for both windows\n")

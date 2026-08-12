#!/usr/bin/env Rscript
# ============================================================================
# Delta RMSE from adding disturbance - TEN variants
#   RF baseline | RF exp01 (high mtry) | RF exp02 (always.split) | XGBoost | LightGBM
# Same data, same variables, same 24 model configs, same LOSO folds.
#
# Sign convention (as used elsewhere in this project):
#   dRMSE % = (RMSE_withD - RMSE_withoutD) / RMSE_withoutD * 100
#   NEGATIVE = less error = disturbance improves the model.
#
#   1) deltaRMSE_10way.png         - mean dRMSE % per with-D/without-D pair
#   2) deltaRMSE_by_EFP_10way.png  - same, broken out by response
#   3) RMSE_paired_10way.png       - absolute RMSE without vs with D (normalised)
# Output: plots/V10/LightGBM/
# ============================================================================
library(data.table); library(ggplot2)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
OUT <- "plots/V10/LightGBM"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

DARK<-"#0D0D0D"; PANEL<-"#111111"; GRID<-"#333333"; TXT<-"#FFFFFF"; AXIS<-"#CCCCCC"
COL <- c("RF"="#4DAECC", "RF exp01"="#E8257A", "RF exp02"="#B07AFF",
         "XGBoost"="#F0A500", "LightGBM"="#7ED957", "LightGBM tuned"="#2E9E4F", "XGBoost tuned"="#C77800",
         "RF Optuna"="#00C2A8", "XGBoost Optuna"="#FF8C42", "LightGBM Optuna"="#4CAF50")
LEV <- names(COL)
thm <- theme_bw(base_size = 9) +
  theme(plot.background=element_rect(fill=DARK,colour=NA),
        panel.background=element_rect(fill=PANEL,colour=NA),
        panel.border=element_rect(colour=GRID,fill=NA),
        panel.grid.major=element_line(colour=GRID,linewidth=0.2),
        panel.grid.minor=element_blank(),
        strip.background=element_rect(fill="#1A1A1A",colour=GRID),
        strip.text=element_text(colour=TXT,size=8,face="bold"),
        axis.text=element_text(colour=AXIS,size=7),
        axis.title=element_text(colour=AXIS,size=9),
        plot.title=element_text(colour=TXT,face="bold"),
        plot.subtitle=element_text(colour=AXIS,size=8.5),
        legend.position="bottom", legend.background=element_rect(fill=NA),
        legend.text=element_text(colour=TXT), legend.title=element_text(colour=AXIS))

base <- "derived_tables/outputs_afterEGU_results"
DS <- list(list(lab="All sites (112)", all=TRUE), list(lab="High tree cover (93)", all=FALSE))
LR <- list(
  list(n="RF",       a="RF_v10_all_sites",        f="RF_v10",        p="RF"),
  list(n="RF exp01", a="RF_v10_all_sites_tuned",  f="RF_v10_tuned",  p="RF"),
  list(n="RF exp02", a="RF_v10_all_sites_exp02",  f="RF_v10_exp02",  p="RF"),
  list(n="XGBoost",  a="XGB_v10_all_sites",       f="XGB_v10",       p="XGB"),
  list(n="LightGBM", a="LGB_v10_all_sites",       f="LGB_v10",       p="LGB"),
  list(n="LightGBM tuned", a="LGB_v10_all_sites_tuned", f="LGB_v10_tuned", p="LGB"),
  list(n="XGBoost tuned",  a="XGB_v10_all_sites_tuned", f="XGB_v10_tuned", p="XGB"),
  list(n="RF Optuna",       a="RF_v10_all_sites_optuna",  f="RF_v10_optuna",  p="RF"),
  list(n="XGBoost Optuna",  a="XGB_v10_all_sites_optuna", f="XGB_v10_optuna", p="XGB"),
  list(n="LightGBM Optuna", a="LGB_v10_all_sites_optuna", f="LGB_v10_optuna", p="LGB"))

met <- rbindlist(lapply(DS, function(d) rbindlist(lapply(LR, function(l) {
  f <- sprintf("%s/%s/%s_metrics_LOSO.csv", base, if (d$all) l$a else l$f, l$p)
  if (!file.exists(f)) { message("missing: ", f); return(NULL) }
  fread(f)[, .(model, response, RMSE, R2)][, `:=`(learner=l$n, dataset=d$lab)][]
}), fill=TRUE)), fill=TRUE)

PAIRS <- list(
  list(lab="M1→M2\nC → C+D",         wo="M1_%s",      wd="M2_%s",      mem="no memory"),
  list(lab="M3→M4\nC+T → +D",        wo="M3_%s",      wd="M4_%s",      mem="no memory"),
  list(lab="M5→M6 raw\nC+M → +D",    wo="M5_raw_%s",  wd="M6_raw_%s",  mem="raw memory"),
  list(lab="M5→M6 anom\nC+M → +D",   wo="M5_anom_%s", wd="M6_anom_%s", mem="anomaly memory"),
  list(lab="M7→M8 raw\nC+T+M → +D",  wo="M7_raw_%s",  wd="M8_raw_%s",  mem="raw memory"),
  list(lab="M7→M8 anom\nC+T+M → +D", wo="M7_anom_%s", wd="M8_anom_%s", mem="anomaly memory"))
PAIR_LEVELS <- sapply(PAIRS, `[[`, "lab")

long <- rbindlist(lapply(c("12m","24m"), function(w) rbindlist(lapply(PAIRS, function(p) {
  a <- met[model == sprintf(p$wo, w)]; b <- met[model == sprintf(p$wd, w)]
  m <- merge(a[, .(response, learner, dataset, RMSE_wo=RMSE, R2_wo=R2)],
             b[, .(response, learner, dataset, RMSE_wd=RMSE, R2_wd=R2)],
             by=c("response","learner","dataset"))
  m[, `:=`(pair=p$lab, mem=p$mem, window=w,
           dRMSE_pct = (RMSE_wd - RMSE_wo)/RMSE_wo*100,
           dR2       = R2_wd - R2_wo)][]
}), fill=TRUE)), fill=TRUE)

long[, learner := factor(learner, levels=LEV)]
long[, pair    := factor(pair, levels=PAIR_LEVELS)]
long[, window  := factor(window, levels=c("12m","24m"), labels=c("12-month window","24-month window"))]

# --------------------------------------------------- 1) mean dRMSE % --------
agg <- long[, .(dRMSE=mean(dRMSE_pct)), by=.(dataset, window, pair, learner)]

p1 <- ggplot(agg, aes(pair, dRMSE, fill=learner)) +
  geom_hline(yintercept=0, colour="#777777", linewidth=0.4) +
  geom_col(position=position_dodge(0.92), width=0.88) +
  facet_grid(window ~ dataset) +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Delta RMSE from adding disturbance - ten variants: RF/XGBoost/LightGBM, each untuned, grid-tuned and Optuna-tuned (+ RF exp01/exp02)",
       subtitle="Mean % change in LOSO RMSE when the disturbance block D is added, averaged over the 5 EFPs.\nNEGATIVE = less error = disturbance helps. M5-M8 split by memory type. Same data, same variables, same folds.",
       x=NULL, y="mean dRMSE (%)  -  negative is better") +
  thm + theme(axis.text.x=element_text(size=6.5))
ggsave(file.path(OUT,"deltaRMSE_10way.png"), p1, width=15, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"deltaRMSE_10way.pdf"), p1, width=15, height=6.5, bg=DARK)

# ------------------------------------------------------ 2) per response -----
p2 <- ggplot(long[dataset=="All sites (112)"], aes(pair, dRMSE_pct, fill=learner)) +
  geom_hline(yintercept=0, colour="#777777", linewidth=0.4) +
  geom_col(position=position_dodge(0.92), width=0.88) +
  facet_grid(window ~ response) +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Delta RMSE per EFP - all sites (112)",
       subtitle="% change in LOSO RMSE from adding D. Negative = less error = disturbance helps.",
       x=NULL, y="dRMSE (%)") +
  thm + theme(axis.text.x=element_text(angle=45, hjust=1, size=5.5))
ggsave(file.path(OUT,"deltaRMSE_by_EFP_10way.png"), p2, width=16, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"deltaRMSE_by_EFP_10way.pdf"), p2, width=16, height=6.5, bg=DARK)

# --------------------------------- 3) absolute RMSE, normalised per response -
# RMSE units differ per EFP, so express each as % of that EFP's RF-without-D RMSE
ref <- long[learner=="RF", .(ref=mean(RMSE_wo)), by=.(dataset, response)]
pr  <- merge(long, ref, by=c("dataset","response"))
pr  <- melt(pr[, .(wo=mean(RMSE_wo/ref*100), wd=mean(RMSE_wd/ref*100)),
               by=.(dataset, window, pair, learner)],
            id.vars=c("dataset","window","pair","learner"),
            variable.name="D", value.name="RMSE_rel")
pr[, D := factor(D, levels=c("wo","wd"), labels=c("without D","with D"))]

p3 <- ggplot(pr, aes(pair, RMSE_rel, fill=learner, alpha=D)) +
  geom_col(position=position_dodge(0.92), width=0.88, colour="#FFFFFF", linewidth=0.18) +
  facet_grid(window ~ dataset) +
  scale_fill_manual(values=COL, name=NULL) +
  scale_alpha_manual(values=c("without D"=0.30, "with D"=1), name=NULL) +
  labs(title="LOSO RMSE without vs with disturbance, ten variants",
       subtitle="RMSE normalised per EFP to the RF without-D baseline (=100%), then averaged. Lower = better.\nPale bar = without D, solid bar = with D.",
       x=NULL, y="relative RMSE (% of RF without-D)") +
  thm + theme(axis.text.x=element_text(size=6.5))
ggsave(file.path(OUT,"RMSE_paired_10way.png"), p3, width=15, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"RMSE_paired_10way.pdf"), p3, width=15, height=6.5, bg=DARK)

# ------------------------------------------------ 4) dR2, ten variants -----
aggR <- long[, .(dR2=mean(dR2)), by=.(dataset, window, pair, learner)]
p4 <- ggplot(aggR, aes(pair, dR2, fill=learner)) +
  geom_hline(yintercept=0, colour="#777777", linewidth=0.4) +
  geom_col(position=position_dodge(0.92), width=0.88) +
  facet_grid(window ~ dataset) +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Delta R2 from adding disturbance - ten variants: RF/XGBoost/LightGBM, each untuned, grid-tuned and Optuna-tuned (+ RF exp01/exp02)",
       subtitle="Mean change in LOSO R2 when the disturbance block D is added, averaged over the 5 EFPs.\nPOSITIVE = D improves the model. M5-M8 split by memory type. Same data, same variables, same folds.",
       x=NULL, y="mean dR2 from adding D  -  positive is better") +
  thm + theme(axis.text.x=element_text(size=6.5))
ggsave(file.path(OUT,"deltaR2_10way.png"), p4, width=15, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"deltaR2_10way.pdf"), p4, width=15, height=6.5, bg=DARK)

# ------------------------------------------- 5) dR2 per EFP, ten variants --
p5 <- ggplot(long[dataset=="All sites (112)"], aes(pair, dR2, fill=learner)) +
  geom_hline(yintercept=0, colour="#777777", linewidth=0.4) +
  geom_col(position=position_dodge(0.92), width=0.88) +
  facet_grid(window ~ response) +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Delta R2 per EFP - all sites (112)",
       subtitle="Change in LOSO R2 from adding D, per response. Positive = disturbance improves the model.",
       x=NULL, y="dR2 from adding D") +
  thm + theme(axis.text.x=element_text(angle=45, hjust=1, size=5.5))
ggsave(file.path(OUT,"deltaR2_by_EFP_10way.png"), p5, width=16, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"deltaR2_by_EFP_10way.pdf"), p5, width=16, height=6.5, bg=DARK)

# same, high tree cover
p6 <- ggplot(long[dataset=="High tree cover (93)"], aes(pair, dR2, fill=learner)) +
  geom_hline(yintercept=0, colour="#777777", linewidth=0.4) +
  geom_col(position=position_dodge(0.92), width=0.88) +
  facet_grid(window ~ response) +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Delta R2 per EFP - high tree cover (93)",
       subtitle="Change in LOSO R2 from adding D, per response. Positive = disturbance improves the model.",
       x=NULL, y="dR2 from adding D") +
  thm + theme(axis.text.x=element_text(angle=45, hjust=1, size=5.5))
ggsave(file.path(OUT,"deltaR2_by_EFP_6way_highTcover.png"), p6, width=16, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"deltaR2_by_EFP_6way_highTcover.pdf"), p6, width=16, height=6.5, bg=DARK)

cat("saved deltaRMSE_10way.png, deltaRMSE_by_EFP_10way.png, RMSE_paired_10way.png, deltaR2_10way.png, deltaR2_by_EFP_10way.png\n\n")
cat("=== mean dRMSE %% from adding D (avg over EFPs + windows; negative = D helps) ===\n")
print(dcast(long[, .(d=round(mean(dRMSE_pct),2)), by=.(dataset,pair,learner)],
            pair + dataset ~ learner, value.var="d"))
cat("\n=== collapsed by memory type ===\n")
print(dcast(long[, .(d=round(mean(dRMSE_pct),2)), by=.(dataset,mem,learner)],
            mem + dataset ~ learner, value.var="d"))

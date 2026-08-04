#!/usr/bin/env Rscript
# ============================================================================
# Disturbance effect across learners (RF / XGBoost / LightGBM)
# Organised around the WITH-D vs WITHOUT-D contrast - the actual research
# question - rather than by memory type. Every model pair that differs only by
# the disturbance block D:
#     M1 vs M2   (C        -> C+D)          no memory
#     M3 vs M4   (C+T      -> C+T+D)        no memory
#     M5 vs M6   (C+M      -> C+D+M)        raw AND anomaly memory, separately
#     M7 vs M8   (C+T+M    -> C+T+D+M)      raw AND anomaly memory, separately
#
#   1) disturbance_effect_3way.png        - mean dR2 from adding D, per pair
#   2) disturbance_effect_by_EFP_3way.png - same, broken out by response
#   3) disturbance_R2_paired_3way.png     - absolute R2 without vs with D
# Output: plots/V10/LightGBM/
# ============================================================================
library(data.table); library(ggplot2)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
OUT <- "plots/V10/LightGBM"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

DARK<-"#0D0D0D"; PANEL<-"#111111"; GRID<-"#333333"; TXT<-"#FFFFFF"; AXIS<-"#CCCCCC"
COL <- c(RF="#4DAECC", XGBoost="#F0A500", LightGBM="#7ED957")
LEV <- c("RF","XGBoost","LightGBM")
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
LR <- list(list(n="RF",       a="RF_v10_all_sites",  f="RF_v10",  p="RF"),
           list(n="XGBoost",  a="XGB_v10_all_sites", f="XGB_v10", p="XGB"),
           list(n="LightGBM", a="LGB_v10_all_sites", f="LGB_v10", p="LGB"))

met <- rbindlist(lapply(DS, function(d) rbindlist(lapply(LR, function(l) {
  f <- sprintf("%s/%s/%s_metrics_LOSO.csv", base, if (d$all) l$a else l$f, l$p)
  if (!file.exists(f)) return(NULL)
  fread(f)[, .(model, response, R2)][, `:=`(learner=l$n, dataset=d$lab)][]
}), fill=TRUE)), fill=TRUE)

# --- define the with-D / without-D pairs ------------------------------------
# label, model WITHOUT D, model WITH D   (%s = window)
PAIRS <- list(
  list(lab="M1\u2192M2\nC \u2192 C+D",            wo="M1_%s",      wd="M2_%s",      mem="no memory"),
  list(lab="M3\u2192M4\nC+T \u2192 +D",           wo="M3_%s",      wd="M4_%s",      mem="no memory"),
  list(lab="M5\u2192M6 raw\nC+M \u2192 +D",       wo="M5_raw_%s",  wd="M6_raw_%s",  mem="raw memory"),
  list(lab="M5\u2192M6 anom\nC+M \u2192 +D",      wo="M5_anom_%s", wd="M6_anom_%s", mem="anomaly memory"),
  list(lab="M7\u2192M8 raw\nC+T+M \u2192 +D",     wo="M7_raw_%s",  wd="M8_raw_%s",  mem="raw memory"),
  list(lab="M7\u2192M8 anom\nC+T+M \u2192 +D",    wo="M7_anom_%s", wd="M8_anom_%s", mem="anomaly memory")
)
PAIR_LEVELS <- sapply(PAIRS, `[[`, "lab")

long <- rbindlist(lapply(c("12m","24m"), function(w) rbindlist(lapply(PAIRS, function(p) {
  wo <- met[model == sprintf(p$wo, w)]
  wd <- met[model == sprintf(p$wd, w)]
  m  <- merge(wo[, .(response, learner, dataset, R2_wo=R2)],
              wd[, .(response, learner, dataset, R2_wd=R2)],
              by=c("response","learner","dataset"))
  m[, `:=`(pair=p$lab, mem=p$mem, window=w, dR2=R2_wd-R2_wo)][]
}), fill=TRUE)), fill=TRUE)

long[, learner := factor(learner, levels=LEV)]
long[, pair    := factor(pair, levels=PAIR_LEVELS)]
long[, window  := factor(window, levels=c("12m","24m"), labels=c("12-month window","24-month window"))]

# ---------------------------------------------- 1) mean dR2 from adding D ---
agg <- long[, .(dR2=mean(dR2)), by=.(dataset, window, pair, learner)]

p1 <- ggplot(agg, aes(pair, dR2, fill=learner)) +
  geom_hline(yintercept=0, colour="#777777", linewidth=0.4) +
  geom_col(position=position_dodge(0.8), width=0.72) +
  facet_grid(window ~ dataset) +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Does adding disturbance help? Every with-D / without-D model pair, three learners",
       subtitle="Mean change in LOSO R2 when the disturbance block D is added (positive = D improves the model), averaged over the 5 EFPs.\nM5-M8 are split by memory type. Same data, same variables, same folds - only the learner differs.",
       x=NULL, y="mean dR2 from adding D") +
  thm + theme(axis.text.x=element_text(size=6.5))
ggsave(file.path(OUT,"disturbance_effect_3way.png"), p1, width=12, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"disturbance_effect_3way.pdf"), p1, width=12, height=6.5, bg=DARK)

# ------------------------------------------------------ 2) per-response ------
p2 <- ggplot(long[dataset=="All sites (112)"], aes(pair, dR2, fill=learner)) +
  geom_hline(yintercept=0, colour="#777777", linewidth=0.4) +
  geom_col(position=position_dodge(0.8), width=0.72) +
  facet_grid(window ~ response) +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Disturbance effect per EFP - all sites (112)",
       subtitle="Change in LOSO R2 from adding D, per response. Positive = disturbance improves the model.",
       x=NULL, y="dR2 from adding D") +
  thm + theme(axis.text.x=element_text(angle=45, hjust=1, size=5.5))
ggsave(file.path(OUT,"disturbance_effect_by_EFP_3way.png"), p2, width=14, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"disturbance_effect_by_EFP_3way.pdf"), p2, width=14, height=6.5, bg=DARK)

# ------------------------------------------- 3) absolute R2 without vs with --
pr <- melt(long[, .(R2_wo=mean(R2_wo), R2_wd=mean(R2_wd)), by=.(dataset, window, pair, learner)],
           id.vars=c("dataset","window","pair","learner"),
           variable.name="D", value.name="R2")
pr[, D := factor(D, levels=c("R2_wo","R2_wd"), labels=c("without D","with D"))]

p3 <- ggplot(pr, aes(pair, R2, fill=learner, alpha=D)) +
  geom_col(position=position_dodge(0.8), width=0.72, colour="#FFFFFF", linewidth=0.18) +
  facet_grid(window ~ dataset) +
  scale_fill_manual(values=COL, name=NULL) +
  scale_alpha_manual(values=c("without D"=0.30, "with D"=1), name=NULL) +
  labs(title="Absolute skill without vs with disturbance, by learner",
       subtitle="Mean LOSO R2 over the 5 EFPs. Pale bar = without D, solid bar = with D.",
       x=NULL, y="mean LOSO R2") +
  thm + theme(axis.text.x=element_text(size=6.5))
ggsave(file.path(OUT,"disturbance_R2_paired_3way.png"), p3, width=12, height=6.5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"disturbance_R2_paired_3way.pdf"), p3, width=12, height=6.5, bg=DARK)

cat("saved disturbance_effect_3way.png, disturbance_effect_by_EFP_3way.png, disturbance_R2_paired_3way.png\n\n")
cat("=== mean dR2 from adding D (averaged over EFPs and windows) ===\n")
print(dcast(long[, .(dR2=round(mean(dR2),3)), by=.(dataset,pair,learner)],
            pair + dataset ~ learner, value.var="dR2"))

#!/usr/bin/env Rscript
# ============================================================================
# RF vs XGBoost comparison figures (same data, same variables, same LOSO folds)
#   1) skill_RF_vs_XGB.png       - LOSO R2 by model group, both datasets
#   2) attribution_RF_vs_XGB.png - disturbance/memory SHAP share shift
# ============================================================================
library(data.table); library(ggplot2)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
OUT <- "plots/V10/XGBoost"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

DARK<-"#0D0D0D"; PANEL<-"#111111"; GRID<-"#333333"; TXT<-"#FFFFFF"; AXIS<-"#CCCCCC"
COL <- c(RF = "#4DAECC", XGB = "#F0A500")
thm <- theme_bw(base_size = 9) +
  theme(plot.background=element_rect(fill=DARK,colour=NA),
        panel.background=element_rect(fill=PANEL,colour=NA),
        panel.border=element_rect(colour=GRID,fill=NA),
        panel.grid.major=element_line(colour=GRID,linewidth=0.2),
        panel.grid.minor=element_blank(),
        strip.background=element_rect(fill="#1A1A1A",colour=GRID),
        strip.text=element_text(colour=TXT,size=8.5,face="bold"),
        axis.text=element_text(colour=AXIS,size=7.5),
        axis.title=element_text(colour=AXIS,size=9),
        plot.title=element_text(colour=TXT,face="bold"),
        plot.subtitle=element_text(colour=AXIS,size=8.5),
        legend.position="bottom", legend.background=element_rect(fill=NA),
        legend.text=element_text(colour=TXT), legend.title=element_text(colour=AXIS))

DS <- list(list(k="all_sites", lab="All sites (112)",
                xgb="XGB_v10_all_sites", rf="RF_v10_all_sites"),
           list(k="filtered",  lab="High tree cover (93)",
                xgb="XGB_v10",           rf="RF_v10"))
grp_of <- function(m) fifelse(grepl("_raw_",m),"raw memory",
                       fifelse(grepl("_anom_",m),"anomaly memory","no memory"))

# ---------------------------------------------------------------- 1) skill --
met <- rbindlist(lapply(DS, function(d) {
  x <- fread(sprintf("derived_tables/outputs_afterEGU_results/%s/XGB_metrics_LOSO.csv", d$xgb))
  r <- fread(sprintf("derived_tables/outputs_afterEGU_results/%s/RF_metrics_LOSO.csv",  d$rf))
  m <- merge(x[,.(model,response,XGB=R2)], r[,.(model,response,RF=R2)], by=c("model","response"))
  m[, `:=`(dataset=d$lab, grp=grp_of(model))][]
}))
agg <- melt(met[, .(RF=mean(RF), XGB=mean(XGB)), by=.(dataset,grp)],
            id.vars=c("dataset","grp"), variable.name="learner", value.name="R2")
agg[, grp := factor(grp, levels=c("no memory","anomaly memory","raw memory"))]

p1 <- ggplot(agg, aes(grp, R2, fill=learner)) +
  geom_col(position=position_dodge(0.72), width=0.66) +
  geom_text(aes(label=sprintf("%.3f", R2)), position=position_dodge(0.72),
            vjust=-0.45, size=2.7, colour=TXT) +
  facet_wrap(~dataset) +
  scale_fill_manual(values=COL, name=NULL) +
  scale_y_continuous(expand=expansion(mult=c(0,0.14))) +
  labs(title="Predictive skill: random forest vs XGBoost",
       subtitle="Mean LOSO R² by model group. Same data, same variables, same folds - only the learner differs.\nXGBoost wins decisively where a dominant raw-memory predictor exists; RF is better on the weak-diffuse predictor sets.",
       x=NULL, y="mean LOSO R²") + thm
ggsave(file.path(OUT,"skill_RF_vs_XGB.png"), p1, width=10, height=5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"skill_RF_vs_XGB.pdf"), p1, width=10, height=5, bg=DARK)

# ---------------------------------------------------------- 2) attribution --
shp <- rbindlist(lapply(DS, function(d) {
  f <- function(path, lab) {
    if (!file.exists(path)) return(NULL)
    s <- fread(path)[, .(v=sum(mean_abs_shap)), by=.(model,group)]
    s[, pct := 100*v/sum(v), by=model][, learner := lab][]
  }
  rbindlist(list(
    f(sprintf("derived_tables/outputs_afterEGU_results/%s/XGB_site_shap_M04_M08.csv", d$xgb), "XGB"),
    f(sprintf("derived_tables/outputs_afterEGU_results/%s/RF_site_shap_M04_M08.csv",  d$rf),  "RF")
  ), fill=TRUE)[, dataset := d$lab][]
}), fill=TRUE)

sub <- shp[group %in% c("Disturbance","Memory")]
sub[, grp := grp_of(model)]
sub[, model := factor(model, levels=sort(unique(model)))]

p2 <- ggplot(sub, aes(model, pct, fill=learner)) +
  geom_col(position=position_dodge(0.72), width=0.66) +
  facet_grid(group ~ dataset, scales="free_y") +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Driver attribution shifts with the learner",
       subtitle="Share of total |SHAP| per driver group. In the RAW-memory models XGBoost reassigns 14-25 percentage points\nfrom Disturbance to Memory - better prediction, weaker-looking disturbance signal. Anomaly / no-memory models move only 4-7 pts.",
       x=NULL, y="% of total |SHAP|") +
  thm + theme(axis.text.x=element_text(angle=45, hjust=1, size=6.5))
ggsave(file.path(OUT,"attribution_RF_vs_XGB.png"), p2, width=11, height=6, dpi=200, bg=DARK)
ggsave(file.path(OUT,"attribution_RF_vs_XGB.pdf"), p2, width=11, height=6, bg=DARK)

cat("saved skill_RF_vs_XGB.png and attribution_RF_vs_XGB.png\n")

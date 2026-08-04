#!/usr/bin/env Rscript
# ============================================================================
# Three-way learner comparison: RF (ranger) vs XGBoost vs LightGBM
# Same data, same variables, same LOSO folds - only the learner differs.
#   1) skill_3way.png       - LOSO R2 by model group, both datasets
#   2) attribution_3way.png - Disturbance / Memory SHAP share by model
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
        strip.text=element_text(colour=TXT,size=8.5,face="bold"),
        axis.text=element_text(colour=AXIS,size=7.5),
        axis.title=element_text(colour=AXIS,size=9),
        plot.title=element_text(colour=TXT,face="bold"),
        plot.subtitle=element_text(colour=AXIS,size=8.5),
        legend.position="bottom", legend.background=element_rect(fill=NA),
        legend.text=element_text(colour=TXT), legend.title=element_text(colour=AXIS))

# dataset key -> (label, dir suffix)
DS <- list(list(lab="All sites (112)",      all=TRUE),
           list(lab="High tree cover (93)", all=FALSE))
# learner -> (output dir stem, file prefix)
LR <- list(list(n="RF",       d_all="RF_v10_all_sites",  d_flt="RF_v10",  p="RF"),
           list(n="XGBoost",  d_all="XGB_v10_all_sites", d_flt="XGB_v10", p="XGB"),
           list(n="LightGBM", d_all="LGB_v10_all_sites", d_flt="LGB_v10", p="LGB"))

grp_of <- function(m) fifelse(grepl("_raw_",m),"raw memory",
                       fifelse(grepl("_anom_",m),"anomaly memory","no memory"))
base <- "derived_tables/outputs_afterEGU_results"

# ---------------------------------------------------------------- 1) skill --
met <- rbindlist(lapply(DS, function(d) rbindlist(lapply(LR, function(l) {
  f <- sprintf("%s/%s/%s_metrics_LOSO.csv", base, if (d$all) l$d_all else l$d_flt, l$p)
  if (!file.exists(f)) return(NULL)
  x <- fread(f)[, .(model, response, R2)]
  x[, `:=`(learner=l$n, dataset=d$lab)][]
}), fill=TRUE)), fill=TRUE)
met[, grp := grp_of(model)]
met[, learner := factor(learner, levels=LEV)]

agg <- met[, .(R2=mean(R2)), by=.(dataset, grp, learner)]
agg[, grp := factor(grp, levels=c("no memory","anomaly memory","raw memory"))]

p1 <- ggplot(agg, aes(grp, R2, fill=learner)) +
  geom_col(position=position_dodge(0.8), width=0.72) +
  geom_text(aes(label=sprintf("%.3f", R2)), position=position_dodge(0.8),
            vjust=-0.45, size=2.5, colour=TXT) +
  facet_wrap(~dataset) +
  scale_fill_manual(values=COL, name=NULL) +
  scale_y_continuous(expand=expansion(mult=c(0,0.15))) +
  labs(title="Predictive skill: random forest vs XGBoost vs LightGBM",
       subtitle="Mean LOSO R2 by model group. Same data, same variables, same folds - only the learner differs.\nBoth boosters beat RF on raw-memory models; both lose slightly to RF where no dominant predictor exists.",
       x=NULL, y="mean LOSO R2") + thm
ggsave(file.path(OUT,"skill_3way.png"), p1, width=11, height=5, dpi=200, bg=DARK)
ggsave(file.path(OUT,"skill_3way.pdf"), p1, width=11, height=5, bg=DARK)

# ---------------------------------------------------------- 2) attribution --
shp <- rbindlist(lapply(DS, function(d) rbindlist(lapply(LR, function(l) {
  f <- sprintf("%s/%s/%s_site_shap_M04_M08.csv", base, if (d$all) l$d_all else l$d_flt, l$p)
  if (!file.exists(f)) return(NULL)
  s <- fread(f)[, .(v=sum(mean_abs_shap)), by=.(model,group)]
  s[, pct := 100*v/sum(v), by=model]
  s[, `:=`(learner=l$n, dataset=d$lab)][]
}), fill=TRUE)), fill=TRUE)

sub <- shp[group %in% c("Disturbance","Memory")]
sub[, learner := factor(learner, levels=LEV)]
sub[, model := factor(model, levels=sort(unique(model)))]

p2 <- ggplot(sub, aes(model, pct, fill=learner)) +
  geom_col(position=position_dodge(0.8), width=0.72) +
  facet_grid(group ~ dataset, scales="free_y") +
  scale_fill_manual(values=COL, name=NULL) +
  labs(title="Driver attribution: the shift is a property of BOOSTING, not of one library",
       subtitle="Share of total |SHAP| per driver group. XGBoost and LightGBM move Disturbance -> Memory by almost the same amount\nin the raw-memory models, while anomaly / no-memory models stay close to RF.",
       x=NULL, y="% of total |SHAP|") +
  thm + theme(axis.text.x=element_text(angle=45, hjust=1, size=6.5))
ggsave(file.path(OUT,"attribution_3way.png"), p2, width=12, height=6, dpi=200, bg=DARK)
ggsave(file.path(OUT,"attribution_3way.pdf"), p2, width=12, height=6, bg=DARK)

cat("saved skill_3way.png and attribution_3way.png\n")
print(dcast(agg, grp ~ dataset + learner, value.var="R2")[, lapply(.SD, function(z) if (is.numeric(z)) round(z,3) else z)])

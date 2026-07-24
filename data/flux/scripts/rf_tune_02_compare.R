#!/usr/bin/env Rscript
# exp02: 3-way comparison — baseline vs exp01 (high mtry) vs exp02 (always.split raw memory)
# Focus on raw-memory models (where the action is). Table + plot, both datasets.
library(data.table); library(ggplot2)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
OUT <- "plots/V10/RF_tuning/exp02_always_split"

DS <- list(
  list(key="all_sites", label="All sites (112)",
       base="RF_v10_all_sites", e1="RF_v10_all_sites_tuned", e2="RF_v10_all_sites_exp02"),
  list(key="filtered", label="High tree cover (93)",
       base="RF_v10", e1="RF_v10_tuned", e2="RF_v10_exp02")
)
rd <- function(d) fread(sprintf("derived_tables/outputs_afterEGU_results/%s/RF_metrics_LOSO.csv", d))[, .(model, response, R2, RMSE)]

allc <- list()
for (d in DS) {
  b <- rd(d$base); e1 <- rd(d$e1); e2 <- rd(d$e2)
  setnames(b,c("R2","RMSE"),c("R2_base","RMSE_base"))
  setnames(e1,c("R2","RMSE"),c("R2_e1","RMSE_e1"))
  setnames(e2,c("R2","RMSE"),c("R2_e2","RMSE_e2"))
  m <- Reduce(function(x,y) merge(x,y,by=c("model","response")), list(b,e1,e2))
  m[, dataset := d$label]
  m[, mem := fifelse(grepl("_raw",model),"raw", fifelse(grepl("_anom",model),"anom","none"))]
  allc[[d$key]] <- m
  cat(sprintf("\n=== %s : mean R2 by memory group ===\n", d$label))
  print(m[, .(base=round(mean(R2_base),3), exp01_highmtry=round(mean(R2_e1),3),
              exp02_alwayssplit=round(mean(R2_e2),3)), by=mem][order(mem)])
}
cmp <- rbindlist(allc)
fwrite(cmp, file.path(OUT,"three_way_metrics.csv"))

# plot: raw-memory models only — R2 baseline vs exp01 vs exp02
raw <- cmp[mem=="raw"]
long <- melt(raw[, .(model,response,dataset,base=R2_base,`exp01 high-mtry`=R2_e1,`exp02 always-split`=R2_e2)],
             id.vars=c("model","response","dataset"), variable.name="config", value.name="R2")
long[, response := factor(response, levels=c("GPPsat","NEPmax","ETmax","uWUE","WUE"))]
DARK<-"#0D0D0D"; PANEL<-"#111111"; GRID<-"#333333"; TXT<-"#FFFFFF"; AXIS<-"#CCCCCC"
p <- ggplot(long, aes(x=response, y=R2, fill=config)) +
  geom_boxplot(outlier.size=0.5, linewidth=0.3, colour="#888888") +
  facet_wrap(~dataset, ncol=1) +
  scale_fill_manual(values=c("base"="#6BA3C4","exp01 high-mtry"="#F0A500","exp02 always-split"="#2ECC71"), name=NULL) +
  labs(title="exp02: raw-memory models (M5-M8 raw) — LOSO R² by config",
       subtitle="base (default) vs exp01 (high mtry) vs exp02 (force {resp}_lag1 every split, default mtry) | higher = better",
       x=NULL, y="LOSO R²") +
  theme_bw(base_size=10) +
  theme(plot.background=element_rect(fill=DARK,colour=NA), panel.background=element_rect(fill=PANEL,colour=NA),
        panel.border=element_rect(colour=GRID,fill=NA), panel.grid.major=element_line(colour=GRID,linewidth=0.2),
        panel.grid.minor=element_blank(), strip.background=element_rect(fill="#1A1A1A",colour=GRID),
        strip.text=element_text(colour=TXT,face="bold"), axis.text=element_text(colour=AXIS),
        axis.title=element_text(colour=AXIS), plot.title=element_text(colour=TXT,face="bold"),
        plot.subtitle=element_text(colour=AXIS,size=8.5), legend.text=element_text(colour=TXT),
        legend.background=element_rect(fill=NA), legend.position="bottom")
ggsave(file.path(OUT,"three_way_raw_memory_R2.png"), p, width=12, height=8, dpi=200, bg=DARK)
ggsave(file.path(OUT,"three_way_raw_memory_R2.pdf"), p, width=12, height=8, bg=DARK)
cat("\n✅ 3-way comparison saved to", OUT, "\n")

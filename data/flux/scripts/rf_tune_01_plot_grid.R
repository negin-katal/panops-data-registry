#!/usr/bin/env Rscript
# exp01: tuning-curve plot — grouped-CV RMSE vs mtry_frac (shows why high mtry wins)
library(data.table); library(ggplot2)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
OUT <- "plots/V10/RF_tuning/exp01_hyperparams"
DARK<-"#0D0D0D"; PANEL<-"#111111"; GRID<-"#333333"; TXT<-"#FFFFFF"; AXIS<-"#CCCCCC"
EFP <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")

g <- rbindlist(list(
  cbind(fread(file.path(OUT,"tuning_grid_all_sites.csv")), dataset="All sites (112)"),
  cbind(fread(file.path(OUT,"tuning_grid_filtered.csv")),  dataset="High tree cover (93)")
))
g[, response := factor(response, levels=EFP)]
g[, cfg := paste0("node ", min_node, ", ", ntrees, " trees")]
# express each combo's CV RMSE relative to the default (mtry≈0.33, node 5, 500 trees) per response×dataset
g[, def_rmse := cv_rmse[abs(mtry_frac-0.33)<1e-9 & min_node==5 & ntrees==500][1], by=.(response,dataset)]
g[, rel := (cv_rmse/def_rmse - 1) * 100]
def <- g[abs(mtry_frac-0.33)<1e-9 & min_node==5 & ntrees==500]

p <- ggplot(g, aes(x=mtry_frac, y=rel, colour=factor(min_node), linetype=factor(ntrees))) +
  geom_hline(yintercept=0, colour="#666666", linewidth=0.4) +
  geom_line(aes(group=cfg), linewidth=0.5, alpha=0.9) +
  geom_point(size=0.8) +
  geom_point(data=def, aes(x=mtry_frac,y=rel), colour="white", size=2.4, shape=1, inherit.aes=FALSE) +
  facet_grid(dataset ~ response) +
  scale_colour_manual(values=c("3"="#4DAECC","5"="#F0A500","10"="#E8257A"), name="min.node.size") +
  scale_linetype_manual(values=c("500"="solid","1000"="dashed"), name="num.trees") +
  scale_x_continuous(breaks=c(0.2,0.33,0.5,0.7,1.0)) +
  labs(title="exp01: hyperparameter tuning curves — grouped-CV RMSE vs mtry (relative to default)",
       subtitle="y = CV RMSE change vs ranger default (white ring, mtry=floor(sqrt(p)) ~5% of p, node 5, 500 trees). Below 0 = better. All 5 EFPs fall as mtry rises -> default far too low.",
       x="mtry (fraction of predictors)", y="CV RMSE vs default (%)") +
  theme_bw(base_size=9) +
  theme(plot.background=element_rect(fill=DARK,colour=NA), panel.background=element_rect(fill=PANEL,colour=NA),
        panel.border=element_rect(colour=GRID,fill=NA), panel.grid.major=element_line(colour=GRID,linewidth=0.2),
        panel.grid.minor=element_blank(), strip.background=element_rect(fill="#1A1A1A",colour=GRID),
        strip.text=element_text(colour=TXT,size=8,face="bold"), axis.text=element_text(colour=AXIS,size=7),
        axis.title=element_text(colour=AXIS,size=9), plot.title=element_text(colour=TXT,face="bold"),
        plot.subtitle=element_text(colour=AXIS,size=8.5), legend.position="bottom",
        legend.background=element_rect(fill=NA), legend.text=element_text(colour=TXT),
        legend.title=element_text(colour=AXIS))
ggsave(file.path(OUT,"tuning_curves_mtry.png"), p, width=16, height=7, dpi=200, bg=DARK)
ggsave(file.path(OUT,"tuning_curves_mtry.pdf"), p, width=16, height=7, bg=DARK)
cat("✅ saved tuning_curves_mtry.png\n")

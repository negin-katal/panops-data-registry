#!/usr/bin/env Rscript
# exp01: baseline vs tuned LOSO comparison — table + plot (both datasets)
library(data.table); library(ggplot2)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

OUT <- "plots/V10/RF_tuning/exp01_hyperparams"
DS <- list(
  list(key="all_sites", label="All sites (112)",
       base="derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_metrics_LOSO.csv",
       tuned="derived_tables/outputs_afterEGU_results/RF_v10_all_sites_tuned/RF_metrics_LOSO.csv"),
  list(key="filtered", label="High tree cover (93)",
       base="derived_tables/outputs_afterEGU_results/RF_v10/RF_metrics_LOSO.csv",
       tuned="derived_tables/outputs_afterEGU_results/RF_v10_tuned/RF_metrics_LOSO.csv")
)
EFP <- c("GPPsat","NEPmax","ETmax","uWUE","WUE")
DARK<-"#0D0D0D"; PANEL<-"#111111"; GRID<-"#333333"; TXT<-"#FFFFFF"; AXIS<-"#CCCCCC"

allcmp <- list()
for (d in DS) {
  b <- fread(d$base)[, .(model, response, R2_base=R2, RMSE_base=RMSE)]
  t <- fread(d$tuned)[, .(model, response, R2_tuned=R2, RMSE_tuned=RMSE)]
  m <- merge(b, t, by=c("model","response"))
  m[, `:=`(dR2=R2_tuned-R2_base, dRMSE_pct=(RMSE_tuned-RMSE_base)/RMSE_base*100, dataset=d$key)]
  allcmp[[d$key]] <- m
  cat(sprintf("\n=== %s ===\n", d$label))
  cat(sprintf("  median ΔR2 = %+.3f | median ΔRMSE = %+.1f%% | improved (RMSE down): %d/%d models\n",
              median(m$dR2), median(m$dRMSE_pct), sum(m$dRMSE_pct<0), nrow(m)))
  print(m[, .(meanΔR2=round(mean(dR2),3), medΔRMSE_pct=round(median(dRMSE_pct),1)), by=response])
}
cmp <- rbindlist(allcmp)
fwrite(cmp, file.path(OUT, "baseline_vs_tuned_metrics.csv"))

# plot: ΔRMSE% per model, facet response × dataset
cmp[, response := factor(response, levels=EFP)]
cmp[, dataset := factor(dataset, levels=c("all_sites","filtered"),
                        labels=c("All sites (112)","High tree cover (93)"))]
cmp[, improved := dRMSE_pct < 0]
p <- ggplot(cmp, aes(x=model, y=dRMSE_pct, fill=improved)) +
  geom_hline(yintercept=0, colour="#888888", linewidth=0.4) +
  geom_col(width=0.8) +
  scale_fill_manual(values=c(`TRUE`="#2ECC71",`FALSE`="#E74C3C"),
                    labels=c(`TRUE`="tuned better",`FALSE`="tuned worse"), name=NULL) +
  facet_grid(dataset ~ response, scales="free_x") +
  labs(title="exp01: tuned vs baseline LOSO — per-site RMSE change",
       subtitle="Negative = tuned model has lower RMSE (better). ΔRMSE % = (tuned − baseline) / baseline × 100",
       x=NULL, y="ΔRMSE (%)") +
  theme_bw(base_size=9) +
  theme(plot.background=element_rect(fill=DARK,colour=NA),
        panel.background=element_rect(fill=PANEL,colour=NA),
        panel.border=element_rect(colour=GRID,fill=NA),
        panel.grid.major=element_line(colour=GRID,linewidth=0.2), panel.grid.minor=element_blank(),
        strip.background=element_rect(fill="#1A1A1A",colour=GRID),
        strip.text=element_text(colour=TXT,size=7.5,face="bold"),
        axis.text.x=element_text(colour=AXIS,size=4.5,angle=90,hjust=1,vjust=0.5),
        axis.text.y=element_text(colour=AXIS,size=8), axis.title=element_text(colour=AXIS,size=9),
        plot.title=element_text(colour=TXT,size=13,face="bold"),
        plot.subtitle=element_text(colour=AXIS,size=8.5),
        legend.background=element_rect(fill=NA), legend.text=element_text(colour=TXT),
        legend.position="bottom")
ggsave(file.path(OUT,"baseline_vs_tuned_dRMSE.png"), p, width=16, height=7, dpi=200, bg=DARK)
ggsave(file.path(OUT,"baseline_vs_tuned_dRMSE.pdf"), p, width=16, height=7, bg=DARK)
cat("\n✅ comparison saved to", OUT, "\n")

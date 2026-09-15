suppressMessages(library(data.table))
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B <- "derived_tables/outputs_afterEGU_results"

# site-level MEAN across years, for both covariates - matches how dist_signed
# itself is already aggregated (mean SHAP across that site's held-out years)
moran <- fread(sprintf("%s/morans_i_mortality_tc30.csv", B))
moran_site <- moran[, .(morans_i = mean(morans_i_500m, na.rm = TRUE)), by = SITE_ID]

harm <- fread(sprintf("%s/v10/v10_B1_GPPsat_harmonized.csv", B), select = c("SITE_ID","YEAR","absolute_mortality_500m"))
intensity_site <- harm[, .(intensity = mean(absolute_mortality_500m, na.rm = TRUE)), by = SITE_ID]

cov <- merge(moran_site, intensity_site, by = "SITE_ID")
ct0 <- cor.test(cov$intensity, cov$morans_i, method = "spearman", exact = FALSE)
cat(sprintf("Collinearity check: Spearman(intensity, morans_i) = %.3f (p=%.4f, n=%d)\n\n",
            ct0$estimate, ct0$p.value, nrow(cov)))

sh <- fread(sprintf("%s/XGB_v10_true24m_optuna/XGB_site_signed_shap_M4.csv", B))
sh <- sh[group == "Disturbance" & response %in% c("GPPsat","NEPmax","ETmax","WUE")]
setnames(sh, "mean_signed_shap", "dist_signed")
sh <- merge(sh, cov, by.x = "test_site", by.y = "SITE_ID")

res <- list()
for (w in c("M4_12m","M4_24m")) for (r in c("GPPsat","NEPmax","ETmax","WUE")) {
  d <- sh[model == w & response == r]
  m_simple <- lm(dist_signed ~ intensity, data = d)
  m_full   <- lm(dist_signed ~ intensity + morans_i, data = d)
  av <- anova(m_simple, m_full)
  f_p <- av$`Pr(>F)`[2]
  sm <- summary(m_full)$coefficients
  res[[length(res)+1]] <- data.table(
    window = sub("M4_","",w), response = r, n = nrow(d),
    r2_intensity_only = summary(m_simple)$r.squared,
    r2_full = summary(m_full)$r.squared,
    morans_partial_coef = sm["morans_i","Estimate"],
    morans_partial_p = sm["morans_i","Pr(>|t|)"],
    nested_F_p = f_p)
}
res <- rbindlist(res)
res[, morans_partial_q := p.adjust(morans_partial_p, method="BH")]
res[, nested_F_q := p.adjust(nested_F_p, method="BH")]
stars <- function(q) fifelse(is.na(q),"",fifelse(q<0.001,"***",fifelse(q<0.01,"**",fifelse(q<0.05,"*","ns"))))
res[, sig := stars(nested_F_q)]
print(res[order(window,response), .(window,response,n,
    r2_intensity=round(r2_intensity_only,3), r2_full=round(r2_full,3),
    dR2=round(r2_full-r2_intensity_only,3),
    morans_p=signif(morans_partial_p,3), morans_q=signif(morans_partial_q,3),
    F_p=signif(nested_F_p,3), F_q=signif(nested_F_q,3), sig)])
fwrite(res, "plots/V10/disturbance_split/morans_i_beyond_intensity.csv")

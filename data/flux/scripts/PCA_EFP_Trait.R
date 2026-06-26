getwd()
rm(list = ls())
# Core
library(dplyr); library(tidyr); library(stringr); library(purrr); library(readr)
install.packages("janitor")
library(janitor)
# PCA + viz
library(factoextra)   # scree, biplot helpers (optional)
library(ggplot2)

# Modeling (tidymodels = CV, tuning, clean pipelines)
library(tidymodels)   # recipes, rsample, parsnip, workflows, tune
tidymodels::tidymodels_prefer()

# Fast random forest
library(ranger)

# Attribution
library(iml)          # ALE
library(fastshap)     # fast SHAP for ranger/xgboost/etc.
library(shapviz)      # pretty SHAP plots
library(vip)          # variable importance plots

set.seed(1234)



##### read the data
trait_df <- fread("clean_data/traitmean_flux_efpsites.csv")
trait_df <- fread("clean_data/traitmean_efp_Mirco.csv")
efp_df <- fread("clean_data/EFP_per_sitesV01.csv")
efp_df[, IGBP := sub("^PFT_", "", IGBP)]
efp_df <- efp_df[IGBP %in% c("CSH", "DBF", "DNF", "EBF", "ENF", "MF", "OSH", "SAV", "WET", "WSA","GRA")]
### Keep only the sites that are in Mirco's study
#### Continue from here
efp_df_Mirco_New <- semi_join(efp_df, subEFPN, by = "SITE_ID")
####
str(efp_df)
str(EFPN)
str(trait_df)
efp_df <- trait_df
# efp_df: columns like SITE_ID, YEAR, uWUE, ETmax, GPPsat, NEPmax, GSmax, ...
# traits_df: columns like SITE_ID[, YEAR], trait_1 ... trait_17 (all numeric)

EFPs_codes_4_PCA <- c("uWUE","ETmax",
                      "GSmax","G1","EF","EFampl",
                      "GPPsat","NEPmax", "Rb","Rbmax","aCUE")

# Select only those columns (use .. to evaluate the character vector)
efp_df <- dat_merged
efp_mat <- efp_df[, ..EFPs_codes_4_PCA]

## -- Run PCA withouth multiple imputation

EFP.pca <- PCA(scale(efp_mat), graph = FALSE)
ind <- get_pca_ind(EFP.pca)
efp_df$PC1 <- ind$coord[,1]
efp_df$PC2 <- ind$coord[,2]
efp_df$PC3 <- ind$coord[,3]


picBiplot<-fviz_pca_biplot(EFP.pca, fill.ind = efp_df$PFT, col.ind = "white", geom.ind = "point", palette = 'igv',
                           label ="var", col.var = "black", labelsize = 2, repel=TRUE,
                           pointshape = 21, pointsize = 1, alpha.ci = 0.5) + 
  labs(title = "", x = "Principal Component 1 (PC1)", 
       y = "Principal Component 2 (PC2)",
       fill = "PFT") + 
  theme(#legend.position = "top", 
    legend.key.size = unit(0.1, "cm"),
    legend.key.width = unit(0.05,"cm"),
    legend.text=element_text(size=3),
    legend.title=element_text(size=3),
    title = element_text(size = 6, face = "bold"),
    text = element_text(size = 6),
    axis.title = element_text(size = 6),
    axis.text = element_text(size = 6)) + xlim(-7.5,7.5) + ylim(-7.5,7.5)

ggsave(filename = "PCA_EFP_228site.jpg", plot = grid.arrange(picBiplot), 
       device = 'png', width = 180, height = 85, units = "mm", dpi = 600)

var <- get_pca_var(EFP.pca)

###uncentainty testing Dray et al 2006, Diaz et al. 2015
library(ade4)

tab <- na.omit(efp_mat)
pca1 <- dudi.pca(tab, center = TRUE, scale = TRUE, scannf = FALSE, nf = 3)
test1 <- testdim(pca1, nrepet = 999)
print(paste("Number of significant PCs:", test1$nb.cor))

# Bootstrap significance of loadings
boot6 <- netoboot(tab, scannf = FALSE, nf = 3)
pvalmatrix <- computePval_peres(pca1$c1, boot6)
####apply threshholds
coordPCthr_val <- rbind(abs(var$coord[,1]),
                        abs(var$coord[,2]),
                        abs(var$coord[,3]))

coordPCthr <- rbind(ifelse(abs(var$coord[,1])>0.3, TRUE, FALSE),
                    ifelse(abs(var$coord[,2])>0.3, TRUE, FALSE),
                    ifelse(abs(var$coord[,3])>0.3, TRUE, FALSE))

contrPCthr <- rbind(ifelse(var$contrib[,1]>(100/nrow(var$coord)), TRUE, FALSE),
                    ifelse(var$contrib[,2]>(100/nrow(var$coord)), TRUE, FALSE),
                    ifelse(var$contrib[,3]>(100/nrow(var$coord)), TRUE, FALSE))

# Combine with significance test
pvalmatrix_TF <- ifelse(pvalmatrix < 0.05, TRUE, FALSE)

pc1Relevance <- coordPCthr[1,] * pvalmatrix_TF[1,] * contrPCthr[1,]
pc2Relevance <- coordPCthr[2,] * pvalmatrix_TF[2,] * contrPCthr[2,]
pc3Relevance <- coordPCthr[3,] * pvalmatrix_TF[3,] * contrPCthr[3,]

####prep data for plot:
df.loadings <- data.frame(
  EFP = rep(rownames(var$coord), 3),
  val = c(var$coord[,1], var$coord[,2], var$coord[,3]),
  contr = c(ifelse(pc1Relevance == 1, 'High', 'Low'),
            ifelse(pc2Relevance == 1, 'High', 'Low'),
            ifelse(pc3Relevance == 1, 'High', 'Low')),
  PC = rep(c("PC1","PC2","PC3"), each = nrow(var$coord))
)

df.contrib <- data.frame(
  EFP = rep(rownames(var$contrib), 3),
  val = c(var$contrib[,1], var$contrib[,2], var$contrib[,3]),
  contr = c(ifelse(pc1Relevance == 1, 'High', 'Low'),
            ifelse(pc2Relevance == 1, 'High', 'Low'),
            ifelse(pc3Relevance == 1, 'High', 'Low')),
  PC = rep(c("PC1","PC2","PC3"), each = nrow(var$contrib))
)


### Plot
# c) Contributions
p2contribs <- ggplot(df.contrib, aes(x=EFP, y=val, fill=contr)) +
  facet_grid(. ~ PC, scales = "free_y") +
  geom_bar(stat="identity") + coord_flip() +
  scale_fill_manual(values=c("High"="#E69F00","Low"="#999999")) +
  theme_classic() + labs(y="Contribution [%]", x="EFP")

# d) Loadings
p1loadings <- ggplot(df.loadings, aes(x=EFP, y=val, fill=contr)) +
  facet_grid(. ~ PC, scales = "free_y") +
  geom_bar(stat="identity") + coord_flip() +
  scale_fill_manual(values=c("High"="#E69F00","Low"="#999999")) +
  theme_classic() + labs(y="Loadings", x="EFP")

# b) Scree
p3 <- fviz_eig(EFP.pca, addlabels=FALSE,
               barfill="white", barcolor="darkblue",
               ncp=8, labelsize=2, linecolor="red") +
  ylim(0,45) +
  theme_classic() + labs(x="Principal Components (PC)", y="Explained variance [%]")

# a) Biplot (already done as picBiplot)
figure1 <- ggarrange(picBiplot, p3, p2contribs, p1loadings,
                     labels=c("a","b","c","d"),
                     nrow=2, ncol=2)

ggsave("plots/fig1_Mirco.jpg", plot=figure1, width=120, height=95, units="mm", dpi=600)
##################
##step 2
# efp_df already has PC1, PC2, PC3 added
# trait_df has traits per SITE_ID

dat_merged <- merge(
  efp_df[, .(SITE_ID, PC1, PC2, PC3)],   # keep only needed columns
  trait_df,
  by = "SITE_ID",
  all.x = TRUE
)

##### Test
dat_merged <- merge(
  EFPN[, .(SITE_ID, PC1, PC2, PC3)],   # keep only needed columns
  trait_df,
  by = "SITE_ID",
  all.x = TRUE
)

dat_merged <- trait_df

str(dat_merged)
### ALl PCs 
# -------------------------------
# Packages
# -------------------------------
library(data.table)
library(dplyr)
library(janitor)
library(randomForest)
library(ggpubr)

# -------------------------------
# 1. Merge EFP PCs with traits
# -------------------------------
dat_merged <- merge(
  efp_df[, .(SITE_ID, PC1, PC2, PC3)],   # PCA scores already in efp_df
  trait_df,
  by = "SITE_ID",
  all.x = TRUE
)

# Clean names for modeling (no spaces/special chars)
dat_merged_clean <- janitor::clean_names(dat_merged)

# Identify trait variables = all numeric columns except metadata + PCs
exclude_vars <- c("site_id","pft","latitude","longitude","location_elev",
                  "pc1","pc2","pc3")

trait_vars <- setdiff(names(dat_merged_clean), exclude_vars)

###Mirco's data
# Keep only plant traits = columns from 34 onwards
trait_vars <- names(dat_merged_clean)[35:ncol(dat_merged_clean)]
# -------------------------------
# 2. Helper: fit RF and extract importance
# -------------------------------
fit_rf_importance <- function(df, target, predictors) {
  subdf <- df %>%
    dplyr::select(all_of(c(target, predictors))) %>%
    na.omit()
  
  set.seed(123)
  rf <- randomForest(
    formula = as.formula(paste(target, "~ .")),
    data = subdf,
    importance = TRUE
  )
  
  imp <- as.data.frame(randomForest::importance(rf))
  imp$varnames <- rownames(imp)
  rownames(imp) <- NULL
  imp$PC <- target
  names(imp)[1] <- "IncMSE"
  
  list(rf = rf, imp = imp)
}

# -------------------------------
# 3. Run for PC1, PC2, PC3
# -------------------------------
resPC1 <- fit_rf_importance(dat_merged_clean, "pc1", trait_vars)
resPC2 <- fit_rf_importance(dat_merged_clean, "pc2", trait_vars)
resPC3 <- fit_rf_importance(dat_merged_clean, "pc3", trait_vars)

impPC1 <- resPC1$imp
impPC2 <- resPC2$imp
impPC3 <- resPC3$imp

# -------------------------------
# 4. Plot importance for each PC
# -------------------------------
dotsize <- 4
fontsize <- 5

pPC1 <- ggdotchart(impPC1, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC1$IncMSE,1.5),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC1 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC2 <- ggdotchart(impPC2, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC2$IncMSE,1.5),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC2 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC3 <- ggdotchart(impPC3, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC3$IncMSE,1.5),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC3 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

# -------------------------------
# 5. Combine into one figure
# -------------------------------
myfinalplot <- ggarrange(pPC1, pPC2, pPC3,
                         labels = c("a","b","c"),
                         font.label = list(face = "bold", size = 8),
                         nrow = 1, ncol = 3)

print(myfinalplot)

# Optionally save
ggsave("plots/RF_importance_traits_PCs.png", myfinalplot,
       width = 180, height = 80, units = "mm", dpi = 600)


##### with trait colored:
# ---- classify traits into groups ----
# Example grouping into 3 categories
# Classify variables by plant organ
impPC1$variableClass <- dplyr::case_when(
  grepl("leaf|sla|ldmc", impPC1$varnames) ~ "Leaf",
  grepl("ssd|stem|wood|conduit", impPC1$varnames) ~ "Stem",
  grepl("root|srl", impPC1$varnames) ~ "Root",
  TRUE ~ "Other"
)

impPC2$variableClass <- dplyr::case_when(
  grepl("leaf|sla|ldmc", impPC2$varnames) ~ "Leaf",
  grepl("ssd|stem|wood|conduit", impPC2$varnames) ~ "Stem",
  grepl("root|srl", impPC2$varnames) ~ "Root",
  TRUE ~ "Other"
)

impPC3$variableClass <- dplyr::case_when(
  grepl("leaf|sla|ldmc", impPC3$varnames) ~ "Leaf",
  grepl("ssd|stem|wood|conduit", impPC3$varnames) ~ "Stem",
  grepl("root|srl", impPC3$varnames) ~ "Root",
  TRUE ~ "Other"
)

# Verify classification
unique(impPC1$variableClass)


palette = c("Leaf" = "#00AFBB", "Stem" = "#E7B800", 
            "Root" = "#FC4E07", "Other" = "gray50")
# ---- plot as in the paper ----
dotsize <- 4
fontsize <- 5

pPC1_Fig3 <- ggdotchart(impPC1, x = "varnames", y = "IncMSE",
                        color = "variableClass",
                        palette = palette,
                        sorting = "descending",
                        add = "segments",
                        add.params = list(color = "lightgray", size = 2),
                        dot.size = dotsize,
                        label = round(impPC1$IncMSE,1),
                        font.label = list(color = "white", size = fontsize, vjust = 0.5),
                        legend.title = "",
                        rotate = TRUE,
                        xlab = "",
                        ylab = "PC1 % Increase MSE",
                        ggtheme = theme_pubclean()) +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC2_Fig3 <- ggdotchart(impPC2, x = "varnames", y = "IncMSE",
                        color = "variableClass",
                        palette = palette,
                        sorting = "descending",
                        add = "segments",
                        add.params = list(color = "lightgray", size = 2),
                        dot.size = dotsize,
                        label = round(impPC2$IncMSE,1),
                        font.label = list(color = "white", size = fontsize, vjust = 0.5),
                        rotate = TRUE,
                        xlab = "",
                        ylab = "PC2 % Increase MSE",
                        ggtheme = theme_pubclean()) +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC3_Fig3 <- ggdotchart(impPC3, x = "varnames", y = "IncMSE",
                        color = "variableClass",
                        palette = palette,
                        sorting = "descending",
                        add = "segments",
                        add.params = list(color = "lightgray", size = 2),
                        dot.size = dotsize,
                        label = round(impPC3$IncMSE,1),
                        font.label = list(color = "white", size = fontsize, vjust = 0.5),
                        rotate = TRUE,
                        xlab = "",
                        ylab = "PC3 % Increase MSE",
                        ggtheme = theme_pubclean()) +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

# ---- formatting same as paper ----
pPC1_Fig3 <- ggpar(pPC1_Fig3, legend = "") + theme(title = element_text(size = 8, face = "bold"),
                                                   text = element_text(size = 6),
                                                   axis.title = element_text(size = 6),
                                                   axis.text = element_text(size = 6))
pPC2_Fig3 <- ggpar(pPC2_Fig3, legend = "") + theme(title = element_text(size = 8, face = "bold"),
                                                   text = element_text(size = 6),
                                                   axis.title = element_text(size = 6),
                                                   axis.text = element_text(size = 6))
pPC3_Fig3 <- ggpar(pPC3_Fig3, legend = "") + theme(title = element_text(size = 8, face = "bold"),
                                                   text = element_text(size = 6),
                                                   axis.title = element_text(size = 6),
                                                   axis.text = element_text(size = 6))

myfinalplot <- ggarrange(pPC1_Fig3, pPC2_Fig3, pPC3_Fig3,
                         labels = c("a","b","c"),
                         font.label = list(face = "bold", color = "black", size = 8),
                         common.legend = FALSE,
                         nrow = 1, ncol = 3)

print(myfinalplot)


ggsave(myfinalplot, width =  18, height = 5, units = "cm", dpi = 600,
       filename = 'plots/RF_var_Import_Mirco_analysis-ready.jpg')

##################################################################################################

# --------------------
# Ulisse's data
# --------------------
# Input data
trait_df <- fread("clean_data/traitmean_efp_Ulisse.csv")
trait_df <- trait_df %>%
  mutate(
    wlma_g_m2 = 1000 / SLA   # SLA in m²/kg → convert to g/m²
  )

trait_df <- trait_df %>%
  mutate(
    # --- recompute Narea if needed
    wNarea_calc = `Leaf N (mass)` * wlma_g_m2,   # g N per m2 leaf
    
    # --- PNUE using N per area
    PNUEarea_calc = GPPsat / wNarea_calc,  
    
    # --- PNUE using N per mass
    PNUEmass_calc = GPPsat / `Leaf N (mass)`,
    
    # --- PNUE using canopy N (Narea × LAImax)
    PNUE_calc = GPPsat / (wNarea_calc * `Leaf area`)
  )


inputdata <- fread("uligom/Input data.csv")
#inputdata_na <-na.omit(inputdata) 
  
efp_df_01 <- inputdata
efp_df_02 <- inputdata
efp_df_03 <- inputdata
###Ulisse
EFPs_codes_4_PCA <- c("wLL","RECOmax","wNmass", "wLMA","GPPsat")
EFPs_codes_4_PCA <- c("wNmass","wLMA","GPPsat", "wSSD", "Hc", "LAImax")
EFPs_codes_4_PCA <- c("Ta","WUEt","PNUE_calc", "Gsmax","EF", "Plant height")
### Daniel trait's
EFPs_codes_4_PCA <- c("Leaf thickness","RECOmax","Leaf N (mass)", "wlma_g_m2","GPPsat")
EFPs_codes_4_PCA <- c("Gsmax","EF", "PNUE_calc", "Ta", "WUEt")
EFPs_codes_4_PCA <- c("SSD","Leaf N (mass)","GPPsat", "wlma_g_m2", "Leaf area")
# Select only those columns (use .. to evaluate the character vector)

efp_mat <- trait_df[, ..EFPs_codes_4_PCA]

## -- Run PCA withouth multiple imputation

EFP.pca <- PCA(scale(efp_mat), graph = FALSE)
ind <- get_pca_ind(EFP.pca)
trait_df$PC1 <- ind$coord[,1]
trait_df$PC2 <- ind$coord[,2]
trait_df$PC3 <- ind$coord[,3]


picBiplot<-fviz_pca_biplot(EFP.pca, fill.ind = trait_df$IGBP, col.ind = "white", geom.ind = "point", palette = 'igv',
                           label ="var", col.var = "black", labelsize = 2, repel=TRUE,
                           pointshape = 21, pointsize = 1, alpha.ci = 0.5) + 
  labs(title = "", x = "Principal Component 1 (PC1)", 
       y = "Principal Component 2 (PC2)",
       fill = "PFT") + 
  theme(#legend.position = "top", 
    legend.key.size = unit(0.1, "cm"),
    legend.key.width = unit(0.05,"cm"),
    legend.text=element_text(size=3),
    legend.title=element_text(size=3),
    title = element_text(size = 6, face = "bold"),
    text = element_text(size = 6),
    axis.title = element_text(size = 6),
    axis.text = element_text(size = 6)) + xlim(-7.5,7.5) + ylim(-7.5,7.5)

ggsave(filename = "plots/PCA_EFP_230site_danieltrait03_02.jpg", plot = grid.arrange(picBiplot), 
       device = 'png', width = 180, height = 85, units = "mm", dpi = 600)


str(trait_df)
# -------------------------------
# Packages
# -------------------------------
library(data.table)
library(dplyr)
library(janitor)
library(randomForest)
library(ggpubr)

# -------------------------------
# 1. Merge EFP PCs with traits
# -------------------------------
dat_merged <- merge(
  efp_df_01[, .(SITE_ID, PC1, PC2, PC3)],   # PCA scores already in efp_df
  trait_df,
  by = "SITE_ID",
  all.x = TRUE
)

# Clean names for modeling (no spaces/special chars)
dat_merged_clean <- janitor::clean_names(dat_merged)

# Identify trait variables = all numeric columns except metadata + PCs
exclude_vars <- c("site_id","igbp","location_lat","location_long","location_elev",
                  "pc1","pc2","pc3")

trait_vars <- setdiff(names(dat_merged_clean), exclude_vars)

### Ulisse's data
# Keep only plant traits = columns from 34 onwards
trait_vars <- names(dat_merged_clean)[55:ncol(dat_merged_clean)]
# -------------------------------
# 2. Helper: fit RF and extract importance
# -------------------------------
fit_rf_importance <- function(df, target, predictors) {
  subdf <- df %>%
    dplyr::select(all_of(c(target, predictors))) %>%
    na.omit()
  
  set.seed(123)
  rf <- randomForest(
    formula = as.formula(paste(target, "~ .")),
    data = subdf,
    importance = TRUE
  )
  
  imp <- as.data.frame(importance(rf))
  imp$varnames <- rownames(imp)
  rownames(imp) <- NULL
  imp$PC <- target
  names(imp)[1] <- "IncMSE"
  
  list(rf = rf, imp = imp)
}

# -------------------------------
# 3. Run for PC1, PC2, PC3
# -------------------------------
resPC1 <- fit_rf_importance(dat_merged_clean, "pc1", trait_vars)
resPC2 <- fit_rf_importance(dat_merged_clean, "pc2", trait_vars)
resPC3 <- fit_rf_importance(dat_merged_clean, "pc3", trait_vars)

impPC1 <- resPC1$imp
impPC2 <- resPC2$imp
impPC3 <- resPC3$imp

# -------------------------------
# 4. Plot importance for each PC
# -------------------------------
dotsize <- 4
fontsize <- 5

pPC1 <- ggdotchart(impPC1, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC1$IncMSE,1.5),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC1 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC2 <- ggdotchart(impPC2, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC2$IncMSE,1.5),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC2 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC3 <- ggdotchart(impPC3, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC3$IncMSE,1.5),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC3 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

# -------------------------------
# 5. Combine into one figure
# -------------------------------
myfinalplot <- ggarrange(pPC1, pPC2, pPC3,
                         labels = c("a","b","c"),
                         font.label = list(face = "bold", size = 8),
                         nrow = 1, ncol = 3)

print(myfinalplot)

# Optionally save
ggsave("plots/RF_importance_traits_PCs.png", myfinalplot,
       width = 180, height = 80, units = "mm", dpi = 600)


##### with trait colored:
# ---- classify traits into groups ----
# Example grouping into 3 categories
impPC1$variableClass <- dplyr::case_when(
  grepl("^leaf", impPC1$varnames) ~ "Leaf",
  grepl("^sla|^ssd|^stem", impPC1$varnames) ~ "Stem",
  grepl("^root", impPC1$varnames) ~ "Root",
  TRUE ~ "Other"
)

impPC2$variableClass <- dplyr::case_when(
  grepl("^leaf", impPC2$varnames) ~ "Leaf",
  grepl("^sla|^ssd|^stem", impPC2$varnames) ~ "Stem",
  grepl("^root", impPC2$varnames) ~ "Root",
  TRUE ~ "Other"
)

impPC3$variableClass <- dplyr::case_when(
  grepl("^leaf", impPC3$varnames) ~ "Leaf",
  grepl("^sla|^ssd|^stem", impPC3$varnames) ~ "Stem",
  grepl("^root", impPC3$varnames) ~ "Root",
  TRUE ~ "Other"
)

# Check unique groups
unique(impPC1$variableClass)

palette = c("Leaf" = "#00AFBB", "Stem" = "#E7B800", 
            "Root" = "#FC4E07", "Other" = "gray50")
# ---- plot as in the paper ----
dotsize <- 4
fontsize <- 5

pPC1_Fig3 <- ggdotchart(impPC1, x = "varnames", y = "IncMSE",
                        color = "variableClass",
                        palette = palette,
                        sorting = "descending",
                        add = "segments",
                        add.params = list(color = "lightgray", size = 2),
                        dot.size = dotsize,
                        label = round(impPC1$IncMSE,1),
                        font.label = list(color = "white", size = fontsize, vjust = 0.5),
                        legend.title = "",
                        rotate = TRUE,
                        xlab = "",
                        ylab = "PC1 % Increase MSE",
                        ggtheme = theme_pubclean()) +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC2_Fig3 <- ggdotchart(impPC2, x = "varnames", y = "IncMSE",
                        color = "variableClass",
                        palette = palette,
                        sorting = "descending",
                        add = "segments",
                        add.params = list(color = "lightgray", size = 2),
                        dot.size = dotsize,
                        label = round(impPC2$IncMSE,1),
                        font.label = list(color = "white", size = fontsize, vjust = 0.5),
                        rotate = TRUE,
                        xlab = "",
                        ylab = "PC2 % Increase MSE",
                        ggtheme = theme_pubclean()) +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC3_Fig3 <- ggdotchart(impPC3, x = "varnames", y = "IncMSE",
                        color = "variableClass",
                        palette = palette,
                        sorting = "descending",
                        add = "segments",
                        add.params = list(color = "lightgray", size = 2),
                        dot.size = dotsize,
                        label = round(impPC3$IncMSE,1),
                        font.label = list(color = "white", size = fontsize, vjust = 0.5),
                        rotate = TRUE,
                        xlab = "",
                        ylab = "PC3 % Increase MSE",
                        ggtheme = theme_pubclean()) +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

# ---- formatting same as paper ----
pPC1_Fig3 <- ggpar(pPC1_Fig3, legend = "") + theme(title = element_text(size = 8, face = "bold"),
                                                   text = element_text(size = 6),
                                                   axis.title = element_text(size = 6),
                                                   axis.text = element_text(size = 6))
pPC2_Fig3 <- ggpar(pPC2_Fig3, legend = "") + theme(title = element_text(size = 8, face = "bold"),
                                                   text = element_text(size = 6),
                                                   axis.title = element_text(size = 6),
                                                   axis.text = element_text(size = 6))
pPC3_Fig3 <- ggpar(pPC3_Fig3, legend = "") + theme(title = element_text(size = 8, face = "bold"),
                                                   text = element_text(size = 6),
                                                   axis.title = element_text(size = 6),
                                                   axis.text = element_text(size = 6))

myfinalplot <- ggarrange(pPC1_Fig3, pPC2_Fig3, pPC3_Fig3,
                         labels = c("a","b","c"),
                         font.label = list(face = "bold", color = "black", size = 8),
                         common.legend = FALSE,
                         nrow = 1, ncol = 3)

print(myfinalplot)


ggsave(myfinalplot, width =  18, height = 5, units = "cm", dpi = 600,
       filename = 'plots/RF_var_Import_Ulisse01.jpg')

###### RF performance 
library(ggplot2)
library(dplyr)
library(Metrics)
library(ggplot2)
library(ggpmisc)    # for regression equation
library(Metrics)    # for RMSE
library(dplyr)

# Prep prediction data for PC1
subdf <- dat_merged_clean %>%
  dplyr::select(all_of(c("pc3", trait_vars))) %>%
  na.omit()

observed <- subdf$pc3
predicted <- predict(resPC3$rf, newdata = subdf)

# Make a data frame
pred_df <- data.frame(observed = observed, predicted = predicted)

# R²
rsq <- cor(observed, predicted)^2

# RMSE
rmse_val <- rmse(observed, predicted)

# Bias (mean error)
bias <- mean(predicted - observed)

# Slope (from linear regression)
slope <- coef(lm(observed ~ predicted))[2]

# Sample size
n <- nrow(pred_df)

ggplot(pred_df, aes(x = predicted, y = observed)) +
  # Density shading (discrete filled contours)
  stat_density_2d_filled(
    geom = "polygon",
    contour_var = "ndensity",
    alpha = 0.8,
    show.legend = FALSE
  ) +
  # Scatter points
  geom_point(alpha = 0.2, size = 0.4, color = "black") +
  # 1:1 dashed line
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "black", linewidth = 0.4) +
  # Regression line
  geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 0.5) +
  # Text annotation
  annotate("text", x = min(pred_df$predicted), y = max(pred_df$observed), hjust = 0, vjust = 1,
           label = paste0(
             "R² = ", round(rsq, 2), "\n",
             "RMSE = ", round(rmse_val, 5), "\n",
             "Bias = ", round(bias, 5), "\n",
             "n = ", n, "\n",
             "Slope = ", round(slope, 2)
           ),
           size = 4, color = "black") +
  # Labels and theme
  labs(x = expression("Predicted PC3"),
       y = expression("Observed PC3"),
       title = "All factors") +
  scale_fill_brewer(palette = "Greens") +  # use green color palette for filled contours
  coord_fixed() +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    plot.title = element_text(hjust = 0.5),
    axis.text = element_text(color = "black"),
    axis.title = element_text(color = "black")
  )


plot_rf_performance <- function(rf_model, target, df, predictors, title = "") {
  subdf <- df %>% select(all_of(c(target, predictors))) %>% na.omit()
  observed <- subdf[[target]]
  predicted <- predict(rf_model, newdata = subdf)
  
  # Metrics
  rsq <- cor(observed, predicted)^2
  rmse_val <- rmse(observed, predicted)
  bias <- mean(predicted - observed)
  slope <- coef(lm(observed ~ predicted))[2]
  n <- length(observed)
  
  plot_df <- data.frame(observed, predicted)
  
  ggplot(plot_df, aes(x = predicted, y = observed)) +
    geom_point(alpha = 0.3, size = 0.7) +
    geom_density_2d_filled(alpha = 0.6, contour_var = "density") +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "black") +
    geom_smooth(method = "lm", se = FALSE, color = "black") +
    theme_minimal() +
    labs(x = paste("Predicted", toupper(target)), y = paste("Observed", toupper(target)),
         title = title) +
    annotate("text", x = min(predicted), y = max(observed), hjust = 0, vjust = 1,
             label = paste0(
               "R² = ", round(rsq, 2), "\n",
               "RMSE = ", round(rmse_val, 4), "\n",
               "Bias = ", round(bias, 5), "\n",
               "n = ", n, "\n",
               "Slope = ", round(slope, 2)
             ), size = 4)
}


###SHAP value:
install.packages("iml")
library(iml)
# Prepare data
subdf <- dat_merged_clean %>% select(all_of(c("pc1", trait_vars))) %>% na.omit()
X <- subdf[, ..trait_vars]
y <- subdf$pc1

# Wrap RF model in iml Predictor
predictor <- Predictor$new(resPC1$rf, data = X, y = y)

# SHAP values
shap <- Shapley$new(predictor, x.interest = X[1:100, ])  # compute for first 100 instances (for speed)
shap_values <- shap$results

# SHAP summary
library(ggplot2)
shap$plot()
# With fastshap or iml, get SHAP matrix:
shap_matrix <- sapply(1:nrow(X), function(i) {
  shap <- Shapley$new(predictor, x.interest = X[i, , drop = FALSE])
  shap$results$phi
})
rownames(shap_matrix) <- colnames(X)

# Plot heatmap (ggplot2 + reshape2)
library(reshape2)
library(ggplot2)

shap_df <- melt(shap_matrix)
colnames(shap_df) <- c("Feature", "Instance", "SHAP")

ggplot(shap_df, aes(x = Instance, y = Feature, fill = SHAP)) +
  geom_tile() +
  scale_fill_gradient2(low = "purple", mid = "white", high = "green", midpoint = 0) +
  theme_minimal() +
  labs(title = "SHAP value heatmap", x = "Instances", y = "Traits")
################################################################## Mirco's paper:
# Load required packages
library(data.table)
library(dplyr)
library(janitor)
library(randomForest)
library(ggpubr)

# -------------------------------
# 1. Load and prepare EFPN data
# -------------------------------
EFPN <- read.table("MigliavaccaEcosystemfunctionsReprWorkflow/data/InputData_withPCs_Migliavacca2021.csv", 
                   header = TRUE, sep = ";")

# Convert P from mm/month to mm/year
EFPN$P <- EFPN$P * 12

# Clean column names
EFPN <- janitor::clean_names(EFPN)

# -------------------------------
# 2. Define target PCs and predictor traits
# -------------------------------
trait_vars <- c('nmass', 'la_imax', 's_win', 'tair', 'vpd', 'p', 'cswi', 'hc', 'abg')
target_pcs <- c("pc1", "pc2", "pc3")

# -------------------------------
# 3. Helper function: Fit RF and extract importance
# -------------------------------
fit_rf_importance <- function(df, target, predictors) {
  subdf <- df %>%
    dplyr::select(all_of(c(target, predictors))) %>%
    na.omit()
  
  set.seed(123)
  rf <- randomForest(
    formula = as.formula(paste(target, "~ .")),
    data = subdf,
    importance = TRUE
  )
  
  imp <- as.data.frame(importance(rf))
  imp$varnames <- rownames(imp)
  rownames(imp) <- NULL
  imp$PC <- target
  names(imp)[1] <- "IncMSE"
  
  list(rf = rf, imp = imp)
}

# -------------------------------
# 4. Run RF models for PC1–PC3
# -------------------------------
resPC1 <- fit_rf_importance(EFPN, "pc1", trait_vars)
resPC2 <- fit_rf_importance(EFPN, "pc2", trait_vars)
resPC3 <- fit_rf_importance(EFPN, "pc3", trait_vars)

impPC1 <- resPC1$imp
impPC2 <- resPC2$imp
impPC3 <- resPC3$imp

# -------------------------------
# 5. Plot variable importance for each PC
# -------------------------------
dotsize <- 4
fontsize <- 5

pPC1 <- ggdotchart(impPC1, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC1$IncMSE, 2),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC1 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC2 <- ggdotchart(impPC2, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC2$IncMSE, 2),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC2 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

pPC3 <- ggdotchart(impPC3, x = "varnames", y = "IncMSE",
                   sorting = "descending", add = "segments",
                   add.params = list(color = "lightgray", size = 1.5),
                   dot.size = dotsize, label = round(impPC3$IncMSE, 2),
                   font.label = list(color = "white", size = fontsize),
                   rotate = TRUE, ylab = "PC3 % Increase MSE") +
  geom_hline(yintercept = 0, linetype = 2, color = "lightgray")

# -------------------------------
# 6. Combine plots into one panel
# -------------------------------
myfinalplot <- ggarrange(pPC1, pPC2, pPC3,
                         labels = c("a", "b", "c"),
                         font.label = list(face = "bold", size = 8),
                         nrow = 1, ncol = 3)

print(myfinalplot)
#### Random Forest performance:
###### RF performance 
library(ggplot2)
library(dplyr)
library(Metrics)
library(ggplot2)
library(ggpmisc)    # for regression equation
library(Metrics)    # for RMSE
library(dplyr)

# Prep prediction data for PC1
subdf <- EFPN %>%
  dplyr::select(all_of(c("PC3", trait_vars))) %>%
  na.omit()

observed <- subdf$PC3
predicted <- predict(resPC3$rf, newdata = subdf)

# Make a data frame
pred_df <- data.frame(observed = observed, predicted = predicted)

# R²
rsq <- cor(observed, predicted)^2

# RMSE
rmse_val <- rmse(observed, predicted)

# Bias (mean error)
bias <- mean(predicted - observed)

# Slope (from linear regression)
slope <- coef(lm(observed ~ predicted))[2]

# Sample size
n <- nrow(pred_df)

ggplot(pred_df, aes(x = predicted, y = observed)) +
  # Density shading (discrete filled contours)
  stat_density_2d_filled(
    geom = "polygon",
    contour_var = "ndensity",
    alpha = 0.8,
    show.legend = FALSE
  ) +
  # Scatter points
  geom_point(alpha = 0.2, size = 0.4, color = "black") +
  # 1:1 dashed line
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "black", linewidth = 0.4) +
  # Regression line
  geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 0.5) +
  # Text annotation
  annotate("text", x = min(pred_df$predicted), y = max(pred_df$observed), hjust = 0, vjust = 1,
           label = paste0(
             "R² = ", round(rsq, 2), "\n",
             "RMSE = ", round(rmse_val, 5), "\n",
             "Bias = ", round(bias, 5), "\n",
             "n = ", n, "\n",
             "Slope = ", round(slope, 2)
           ),
           size = 4, color = "black") +
  # Labels and theme
  labs(x = expression("Predicted PC3"),
       y = expression("Observed PC3"),
       title = "All factors") +
  scale_fill_brewer(palette = "Greens") +  # use green color palette for filled contours
  coord_fixed() +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    plot.title = element_text(hjust = 0.5),
    axis.text = element_text(color = "black"),
    axis.title = element_text(color = "black")
  )

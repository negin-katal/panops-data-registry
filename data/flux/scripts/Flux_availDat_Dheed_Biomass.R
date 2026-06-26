rm(list = ls())
getwd()

library(dplyr)
library(ggplot2)
library(readr)
library(data.table)
library(lubridate)


efp_all <- fread("clean_data/efp_by_site_year_V2.csv")
dheed <- fread("clean_data/flux_dheed_events.csv")
biomass <- fread("/mnt/gsdata/projects/other/ESA_CCi_Biomass/output/AGB_all_sites_1km_all_years_withIGBP.csv")
climate <- fread("clean_data/climate_yearly_allsite.csv")
str(efp_all)
str(dheed)
str(biomass)
unique(biomass$SITE_ID)




# Make sure dheed is a data.table
setDT(dheed)

# Sort and keep the first row per SITE_ID and end_time
dheed_first <- dheed[order(SITE_ID, end_time, date), .SD[1], by = .(SITE_ID, end_time)]

dheed_clean <- dheed_first[complete.cases(dheed_first)]

# Add year column
dheed_clean[, year := year(date)]

dheed_clean[, IGBP := sub("^PFT_", "", IGBP)]
## take only years after 2010
dheed_2010 <- dheed_clean %>% 
  filter(year>=2010)
## remove the days
dheed_2010[, duration := as.numeric(gsub(" days", "", duration))]

## plot
library(ggplot2)

ggplot(dheed_2010, aes(x = as.character(year), y = duration, color = IGBP)) +
  geom_point(alpha = 0.7) +
  labs(
    x = "Year",
    y = "Duration (days)",
    color = "IGBP",
    title = "Duration of Events by Year and IGBP"
  ) +
  theme_minimal(base_size = 14)

###filter the IGBP
dheed_2010_IGBP_fil <- dheed_2010[IGBP %in% c("CSH", "DBF", "DNF", "EBF", "ENF", "MF", "OSH", "SAV", "WET", "WSA")]

ggplot(dheed_2010_IGBP_fil, aes(x = as.character(year), y = duration, color = IGBP)) +
  geom_point(alpha = 0.7) +
  labs(
    x = "Year",
    y = "Duration (days)",
    color = "IGBP",
    title = "Duration of Events by Year and IGBP"
  ) +
  theme_minimal(base_size = 14)

### filter the EU countries
# Define the European country codes
europe_country_codes <- c(
  "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE",
  "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT",
  "RO", "SK", "SI", "ES", "SE", "CH", "GB", "NO", "IS"
)

# Extract the country code from SITE_ID (before the dash)
dheed_2010_IGBP_fil[, site_country := tstrsplit(SITE_ID, "-", keep = 1)]

# Filter rows where the site country is in Europe
dheed_eu <- dheed_2010_IGBP_fil[site_country %in% europe_country_codes]

# Make sure both are data.tables


ggplot(dheed_eu, aes(x = as.character(year), y = SITE_ID, fill = duration)) +
  geom_tile() +
  scale_fill_viridis_c(name = "Duration (days)", na.value = "grey90") +
  facet_wrap(~ IGBP, scales = "free_y", nrow = 2, ncol = 4) +
  labs(
    x = "Year",
    y = "Site",
    title = "Duration of Events EU Sites"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.text.y = element_text(size = 6, angle = 15, hjust = 1)  # optional: reduce font size if crowded
  )
# Summarize duration per year and IGBP
dheed_summary <- dheed_2010_IGBP_fil %>%
  group_by(year, IGBP) %>%
  summarise(
    mean_duration = mean(duration, na.rm = TRUE),
    sd_duration = sd(duration, na.rm = TRUE),
    n = n()
  ) %>%
  ungroup()

# Plot with ribbons showing variability
ggplot(dheed_2010_IGBP_fil, aes(x = as.character(year), y = SITE_ID, fill = duration)) +
  geom_tile() +
  scale_fill_viridis_c(name = "Duration (days)", na.value = "grey90") +
  facet_wrap(~ IGBP, scales = "free_y", nrow = 2, ncol = 5) +
  labs(
    x = "Year",
    y = "Site",
    title = "Duration of Events"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.text.y = element_text(size = 4, angle = 15, hjust = 1)  # optional: reduce font size if crowded
  )

#take the sites which are in dheed EU
# Get unique site IDs from dheed_eu
eu_sites <- unique(dheed_eu$SITE_ID)

# Filter EFP data to those sites
efp_eu <- efp_all[SITE_ID %in% eu_sites]

unique(efp_eu$SITE_ID)

# Number of sites before and after filtering
length(unique(efp_all$SITE_ID))
length(unique(efp_eu$SITE_ID))
####
# Get the 34 unique site IDs from efp_eu
efp_sites <- unique(efp_eu$SITE_ID)

# Filter dheed_eu to include only those 34 sites
dheed_efp_sites <- dheed_eu[SITE_ID %in% efp_sites]

ggplot(dheed_efp_sites, aes(x = as.character(year), y = SITE_ID, fill = duration)) +
  geom_tile() +
  scale_fill_viridis_c(name = "Duration (days)", na.value = "grey90") +
  facet_wrap(~ IGBP, scales = "free_y", nrow = 2, ncol = 4) +
  labs(
    x = "Year",
    y = "Site",
    title = "EU site with EFP available data"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.text.y = element_text(size = 6, angle = 15, hjust = 1)  # optional: reduce font size if crowded
  )

## calculate the anomalies of EFP for EU sites
# Calculate anomalies: value - site mean
efp_anomalies <- efp_eu[, lapply(.SD, function(x) x - mean(x, na.rm = TRUE)),
                        by = .(SITE_ID),
                        .SDcols = c("GPPsat", "NEPmax", "uWUE", "ETmax", "GSmax")]

# Copy the data first
efp_anomalies <- copy(efp_eu)

# Calculate and add anomaly columns
efp_anomalies[, GPPsat_anom := GPPsat - mean(GPPsat, na.rm = TRUE), by = SITE_ID]
efp_anomalies[, NEPmax_anom := NEPmax - mean(NEPmax, na.rm = TRUE), by = SITE_ID]
efp_anomalies[, uWUE_anom   := uWUE   - mean(uWUE,   na.rm = TRUE), by = SITE_ID]
efp_anomalies[, ETmax_anom  := ETmax  - mean(ETmax,  na.rm = TRUE), by = SITE_ID]
efp_anomalies[, GSmax_anom  := GSmax  - mean(GSmax,  na.rm = TRUE), by = SITE_ID]


efp_anomalies[, GPPsat_z := (GPPsat - mean(GPPsat, na.rm = TRUE)) / sd(GPPsat, na.rm = TRUE), by = SITE_ID]


library(data.table)

# Melt into long format
efp_long <- melt(
  efp_anomalies,
  id.vars = c("SITE_ID", "IGBP", "year"),
  measure.vars = patterns("_anom$"),
  variable.name = "EFP_variable",
  value.name = "anomaly"
)

efp_long_2010 <- efp_long %>% 
  filter(year>=2010)
# Clean variable names if needed
efp_long[, EFP_variable := gsub("_anom", "", EFP_variable)]

# Get unique IGBPs
igbps <- unique(efp_long_2010$IGBP)

# Create a list of ggplot objects, one for each IGBP
plots_by_igbp <- lapply(igbps, function(igbp_name) {
  ggplot(efp_long_2010[IGBP == igbp_name], aes(x = as.character(year), y = anomaly, color = EFP_variable, group = SITE_ID)) +
    geom_line(alpha = 0.7) +
    geom_point(size = 2) +
    facet_wrap(~ SITE_ID, scales = "free_y", ncol=1) +
    labs(
      title = paste("EFP Anomalies for IGBP:", igbp_name),
      x = "Year",
      y = "Anomaly",
      color = "EFP Variable"
    ) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      strip.text = element_text(size = 10)
    )
})

# View one
print(plots_by_igbp[[7]])  # or use View(plots_by_igbp)

###only GPPsat
library(ggplot2)
library(data.table)
efp_anomalies_2010 <- efp_anomalies %>% 
  filter(year>= 2010)

ggplot(efp_anomalies_2010, aes(x = as.factor(year), y = GPPsat_anom, fill= IGBP#, group = SITE_ID
                          )) +
  #geom_line(color = "steelblue", alpha = 0.6) +
  #geom_point(color = "steelblue", size = 1.5) +
  geom_boxplot()+
  #facet_wrap(~ IGBP, scales = "free_y", ncol = 3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40")+
  labs(
    title = "GPPsat Anomalies per Site, Faceted by IGBP",
    x = "Year",
    y = "GPPsat Anomaly"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(size = 10)
  )
#############################
# Filter to GPPsat only
efp_gppsat <- efp_long_2010[EFP_variable == "GPPsat"]
efp_nepmax <- efp_long_2010[EFP_variable == "NEPmax"]
efp_etmax <- efp_long_2010[EFP_variable == "ETmax"]
efp_gsmax <- efp_long_2010[EFP_variable == "GSmax"]
efp_uwue <- efp_long_2010[EFP_variable == "uWUE"]
# Get IGBP list
igbps <- unique(efp_gppsat$IGBP)

# Generate plots per IGBP
plots_by_igbp <- lapply(igbps, function(igbp_name) {
  ggplot(efp_gppsat[IGBP == igbp_name], aes(x = as.character(year), y = anomaly, group = SITE_ID)) +
    geom_line(alpha = 0.7, color = "forestgreen") +
    geom_point(size = 2, color = "forestgreen") +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    facet_wrap(~ SITE_ID, ncol = 1, scales = "free_y") +
    labs(
      title = paste("GPPsat Anomalies for IGBP:", igbp_name),
      x = "Year",
      y = "GPPsat Anomaly"
    ) +
    theme_minimal(base_size = 13) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      strip.text = element_text(size = 10)
    )
})

# View one
print(plots_by_igbp[[7]])
###heatplot
ggplot(efp_uwue, aes(x = as.factor(year), y = SITE_ID, fill = anomaly)) +
  geom_tile() +
  scale_fill_gradient2(
    name = "uWUE Anomaly",
    low = "brown", mid = "white", high = "darkgreen", midpoint = 0,
    na.value = "grey90"
  ) +
  facet_wrap(~ IGBP, scales = "free_y", ncol = 4) +
  labs(
    x = "Year",
    y = "Site",
    title = "uWUE Anomalies per Site"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1, size = 5),
    axis.text.y = element_text(size = 6, angle = 15, hjust = 1),
    strip.text = element_text(size = 10)
  )
############################
AGB_efp_EUsites <- biomass[SITE_ID %in% efp_sites]
# Calculate anomaly per site
AGB_efp_EUsites[, agb_anom := agb_median - mean(agb_median, na.rm = TRUE), by = SITE_ID]

ggplot(AGB_efp_EUsites, aes(x = as.factor(year), y = SITE_ID, fill = agb_anom)) +
  geom_tile() +
  scale_fill_gradient2(
    name = "AGB Anomaly",
    low = "brown", mid = "white", high = "darkgreen", midpoint = 0,
    na.value = "grey90"
  ) +
  facet_wrap(~ IGBP, scales = "free_y", ncol = 4) +
  labs(
    x = "Year",
    y = "Site",
    title = "AGB Anomalies per Site"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.text.y = element_text(size = 6, angle = 15, hjust = 1),
    strip.text = element_text(size = 10)
  )

ggplot(AGB_efp_EUsites, aes(x = as.character(year), y = SITE_ID, fill = agb_median)) +
  geom_tile() +
  #geom_bar()+
  scale_fill_viridis_c(name = "AGB", na.value = "grey90") +
  facet_wrap(~ IGBP, scales = "free_y", nrow = 2, ncol = 4) +
  labs(
    x = "Year",
    y = "Site",
    title = "ABG EU site "
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.text.y = element_text(size = 6, angle = 15, hjust = 1)  # optional: reduce font size if crowded
  )

ggplot(AGB_efp_EUsites, aes(x = as.factor(year), y = agb_median, group = SITE_ID, color= SITE_ID)) +
  geom_line( alpha = 0.7) +
  geom_point( size = 2) +
  facet_wrap(~ IGBP, scales = "free_y", ncol = 2) +
  labs(
    x = "Year",
    y = "AGB",
    title = "AGB Trends Over Time for EU Flux Sites"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.text.y = element_text(size = 10)
  )




####combine all three datasets:
climate_eu <- climate[SITE_ID %in% efp_sites]


# Step 1: Merge AGB and EFP data
df1 <- merge(AGB_efp_EUsites, efp_anomalies, by = c("SITE_ID", "year"))
df2 <- merge(df1, climate_eu, by = c("SITE_ID", "year"))
# Step 2: Merge in the DHEED extreme event data
combined_df <- merge(df2, dheed_2010_IGBP_fil, by = c("SITE_ID", "year"))

fwrite(combined_df, "clean_data/biomass_dheed_efp.csv")
###
combined_df <- fread("clean_data/biomass_dheed_efp.csv")
###statistical model
library(lme4)

# Predicting GPPsat anomaly
model_gpp_fix <- lm(GPPsat ~ duration + IGBP.y, data = combined_df)
summary(model_gpp_fix)
# Predicting AGB anomaly
model_agb <- lmer(agb_anom ~ duration + (1|SITE_ID), data = combined_df)
##################################################################

str(combined_df)
###Coefficient plot
lm(GPPsat ~ drought90 + P_mean + VPD_mean + Tair_mean + agb_mean+ IGBP.x , data = combined_df)

library(broom)
fit <- lm(GPPsat ~ drought90 + P_mean + VPD_mean + Tair_mean + agb_mean+ IGBP.x , data = combined_df)
results <- tidy(fit, conf.int = TRUE)


# Add predictor type manually
results$predictor_type <- dplyr::case_when(
  results$term == "drought90" ~ "Extreme event",
  results$term %in% c("P_mean", "VPD_mean", "Tair_mean") ~ "Climate",
  results$term == "agb_mean" ~ "Biomass",
  grepl("IGBP", results$term) ~ "Vegetation type",
  TRUE ~ "Other"
)

# Dummy importance (absolute standardized coefficient)
results$importance <- abs(results$estimate) / max(abs(results$estimate), na.rm = TRUE)


ggplot(results, aes(x = estimate, y = term)) +
  geom_point(aes(size = importance, color = predictor_type)) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high, color = predictor_type), height = 0.2) +
  scale_color_manual(values = c("red", "blue", "green", "purple", "orange")) +
  theme_minimal() +
  labs(x = "Effect coefficient", y = "", size = "Relative importance", color = "Predictor type")

library(Metrics)
install.packages("Metrics")
# R²
r2_val <- summary(fit)$r.squared

# RMSE
rmse_val <- rmse(fit$model$GPPsat, fitted(fit))


ggplot(results, aes(x = estimate, y = term)) +
  geom_point(aes(size = importance, color = predictor_type)) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high, color = predictor_type), height = 0.2) +
  scale_color_manual(values = c("red", "blue", "green", "purple", "orange")) +
  theme_minimal() +
  labs(
    x = "Effect coefficient", 
    y = "", 
    size = "Relative importance", 
    color = "Predictor type",
    title = "GPPsat",
    subtitle = paste0("R² = ", round(r2_val, 2), 
                      " | RMSE = ", round(rmse_val, 2))
  )

###### scale the variables
combined_df_scaled <- combined_df %>%
  mutate(across(c(P_mean, VPD_mean, Tair_mean, agb_mean, drought90, drought30, drought180, SWin_mean), scale))

fit <- lm(GPPsat ~ drought90+ drought30 + drought180+ SWin_mean + P_mean + VPD_mean + Tair_mean + agb_mean + IGBP.x, 
          data = combined_df_scaled)

results <- tidy(fit, conf.int = TRUE)


# Add predictor type manually
results$predictor_type <- dplyr::case_when(
  results$term %in% c("drought30", "drought90", "drought180") ~ "Extreme event",
  results$term %in% c("P_mean", "VPD_mean", "Tair_mean", "SWin_mean") ~ "Climate",
  results$term == "agb_mean" ~ "Biomass",
  grepl("IGBP.x", results$term) ~ "Vegetation type",
  TRUE ~ "Other"
)

# Dummy importance (absolute standardized coefficient)
results$importance <- abs(results$estimate) / max(abs(results$estimate), na.rm = TRUE)


ggplot(results, aes(x = estimate, y = term)) +
  geom_point(aes(size = importance, color = predictor_type)) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high, color = predictor_type), height = 0.2) +
  scale_color_manual(values = c("red", "blue", "green", "purple", "orange")) +
  theme_minimal() +
  labs(x = "Effect coefficient", y = "", size = "Relative importance", color = "Predictor type")

library(Metrics)
install.packages("Metrics")
# R²
r2_val <- summary(fit)$r.squared

# RMSE
rmse_val <- rmse(fit$model$GPPsat, fitted(fit))

ggplot(results, aes(x = estimate, y = term)) +
  geom_point(aes(size = importance, color = predictor_type)) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high, color = predictor_type), height = 0.2) +
  scale_color_manual(values = c("red", "blue", "green", "purple", "orange")) +
  theme_minimal() +
  labs(
    x = "Effect coefficient", 
    y = "", 
    size = "Relative importance", 
    color = "Predictor type",
    title = "GPPsat",
    subtitle = paste0("R² = ", round(r2_val, 2), 
                      " | RMSE = ", round(rmse_val, 2))
  )
##################
library(broom)
library(dplyr)
library(ggplot2)
library(purrr)

efps <- c("uWUE", "ETmax", "GPPsat", "NEPmax")

# fit model for each EFP
fit_list <- map(efps, ~ lm(GPPsat ~ drought90+ drought30 + drought180+ SWin_mean + P_mean + VPD_mean + Tair_mean + agb_mean + IGBP.x, 
                           data = combined_df_scaled))

# tidy results
results <- map2_dfr(fit_list, efps, ~ tidy(.x, conf.int = TRUE) %>% mutate(response = .y))

results <- results %>%
  mutate(
    predictor_type = case_when(
      term %in% c("drought30", "drought90", "drought180") ~ "Extreme event",
      term %in% c("P_mean", "VPD_mean", "Tair_mean", "SWin_mean") ~ "Climate",
      term == "agb_mean" ~ "Biomass",
      grepl("IGBP", term) ~ "Vegetation type",
      TRUE ~ "Other"
    ),
    importance = abs(estimate) / max(abs(estimate), na.rm = TRUE)
  )


### plot
results_no_intercept <- results %>% filter(term != "(Intercept)")

ggplot(results_no_intercept, aes(x = estimate, y = term)) +
  geom_vline(xintercept = 0, color = "grey50", linetype = "dashed") +
  geom_point(aes(size = importance, color = predictor_type)) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high, color = predictor_type), height = 0.2) +
  scale_color_manual(values = c("red", "blue", "green", "purple", "orange")) +
  theme_minimal(base_size = 13) +
  facet_wrap(~ response, ncol = 2) +
  labs(x = "Effect coefficient", y = "", size = "Relative importance", color = "Predictor type")
#####
######## Multimodel inference (MMI)
install.packages("MuMIn")
library(MuMIn)
library(car)     # for VIF
library(relaimpo) # for relative importance

options(na.action = "na.omit")

# Select predictors similar to paper
predictors <- c("P_mean", "VPD_mean", "Tair_mean", "SWin_mean", "agb_mean", 
                "drought90", "drought30", "drought180", "IGBP.x")

formula_full <- as.formula(
  paste("GPPsat ~", paste(predictors, collapse = " + "))
)

# Full model
fit_full <- lm(formula_full, data = combined_df_scaled)

##
get_vif_adj <- function(model) {
  vif_out <- car::vif(model)
  if (is.matrix(vif_out)) {
    # return adjusted GVIF
    return(vif_out[, "GVIF^(1/(2*Df))"])
  } else {
    return(vif_out)
  }
}

vif_vals <- get_vif_adj(fit_full)

for (i in 1:length(predictors)) {
  if (max(vif_vals) <= 5) break  # stop when all adjusted VIFs are acceptable
  
  drop_var <- names(which.max(vif_vals))
  message("Dropping predictor: ", drop_var, " (VIF = ", round(max(vif_vals), 2), ")")
  
  predictors <- setdiff(predictors, drop_var)
  formula_full <- as.formula(paste("GPPsat ~", paste(predictors, collapse = " + ")))
  fit_full <- lm(formula_full, data = combined_df)
  vif_vals <- get_vif_adj(fit_full)
}

print(vif_vals)
# Run dredge
options(na.action = "na.fail")  # required for dredge
dredge_out <- dredge(fit_full, trace = TRUE, rank = "AICc")

# Best models = delta AICc < 4
best_models <- subset(dredge_out, delta < 4)

# Model averaging (weighted coefficients)
avg_mod <- model.avg(best_models)
summary(avg_mod)

# Calculate relative importance on full model
relimp_res <- calc.relimp(fit_full, type = "lmg", rela = TRUE)

# Extract variable importance
importance_df <- data.frame(
  term = names(relimp_res$lmg),
  importance = relimp_res$lmg
)

library(broom)

coef_df <- tidy(avg_mod, conf.int = TRUE) %>%
  dplyr::filter(term != "(Intercept)") %>%
  left_join(importance_df, by = c("term" = "term")) %>%
  mutate(predictor_type = case_when(
    term %in% c("P_mean", "VPD_mean", "Tair_mean", "SWin_mean") ~ "Climate",
    term %in% c("drought30", "drought90", "drought180") ~ "Extreme event",
    term == "agb_mean" ~ "Biomass",
    grepl("IGBP", term) ~ "Vegetation type",
    TRUE ~ "Other"
  ))

ggplot(coef_df, aes(x = estimate, y = term)) +
  geom_vline(xintercept = 0, color = "grey50", linetype = "dashed") +
  geom_point(aes(size = importance, color = predictor_type)) +
  geom_errorbarh(aes(xmin = conf.low, xmax = conf.high, color = predictor_type), height = 0.2) +
  scale_color_manual(values = c("red", "blue", "green", "orange")) +
  theme_minimal(base_size = 13) +
  labs(x = "Weighted effect coefficient", y = "", 
       size = "Relative importance", color = "Predictor type")
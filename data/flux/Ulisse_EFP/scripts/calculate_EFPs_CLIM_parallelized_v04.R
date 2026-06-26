#### IMPORT AND PROCESS FLUXES
# Ecosystem Functional Properties, climate properties...

### Authors: Ulisse Gomarasca (ugomar@bgc-jena.mpg.de)
### Version History ------------------------------------------------------------
# v01, 30.01.2024:  Working parallelized EFP calculation (CUEeco, GPPsat, NEPmax,
#                   Gsmax, WUE) for full sites and by years.
# v02, 31.01.2024:  Moved EC data filtering so that it is not repeated for every
#                   EFP (cuts ~20-25% of processing time). Streamlined SW filtering
#                   thresholds. NB: EFPs "by years" will be slightly different
#                   than in v01, because growing season and precipitation filters
#                   are applied on whole period instead of on single years, and
#                   5-days-moving-window for GPPsat will be interrupted at the
#                   end of year.
# v03, 28.03.2024:  Added climate aggregation. Filtered out IGBP = CVM.
# v04, 23.01.2026:  Added EFPs calculations for Rb, EF, and LUE.



### Script settings ------------------------------------------------------------
# Clear environment
rm(list = ls(all = TRUE))

# Start
library(tictoc)
tic("") # Script run time.

# Computation grouping strategy
group_year <- F #readline(prompt = "Calculate EFPs for site-years (T) or whole sites (F)? T/F:") # ask if sites or site-years
if (group_year %in% c("y", "yes", "Y", "YES", "T", "TRUE")) {
  grouping_var <- rlang::sym("YEAR")
  groupin <- "_ByYears"
} else if (group_year %in% c("n", "no", "N", "NO", "F", "FALSE")) {
  grouping_var <- NULL
  groupin <- ""
}; rm(group_year) # clean environment

# Data settings
savedata <- as.logical(readline(prompt = "Save the output of the script? T/F:")) # ask if output should be saved
vers_out <- "v04" # output version
eval_file <- glue::glue("results/analysis_evaluation/evaluation_calculate_EFPs_CLIM{groupin}_{vers_out}.txt")
if (savedata) {
  cat(paste0(vers_out, "\n"), file = "data/efp_version.txt") # save version number for reference in other scripts ("\n" for new line to avoid warning when reading back into R with read.table())
  cat(paste0("##### IMPORT AND PREPARE DATA FOR ANALYSIS #####", "\n"), file = eval_file, append = F) # initialize evaluation text
}



### Utilities ------------------------------------------------------------------
## Functions
source("scripts/functions/safe_load_packages.R")
source("scripts/functions/import_data_and_calc_CLIM.R")
source("scripts/functions/import_data_and_calc_EFPs.R")
source("scripts/functions/plot_timeseries.R")

## Packages
required_packages <- c(
  "bigleaf",      # eddy covariance processing
  "dplyr",        # tidy data manipulation
  "furrr",        # map in parallel
  "future",       # plan parallelization
  "ggplot2",      # tidy plots
  "glue",         # glue strings
  "janitor",      # clean data
  "lubridate",    # dates manipulation
  "ncdf4",        # netcdf files
  "purrr",        # map functions
  "quantreg",     # quantile regression
  "readr",        # read csv files
  "REddyProc",    # eddy covariance functions
  "rlang",        # quoting inside functions
  "stringr",      # tidy string manipulation
  "tictoc",       # measure time
  "tidyr"         # clean and reshape tidy data
  )
safe_load_packages(required_packages)



### Data files -----------------------------------------------------------------
data_path_fluxes <- "//minerva/BGI/work_4/scratch/jnelson/4Sinikka/data20240123/"
data_path_meteo <- "//minerva/BGI/work_4/scratch/fluxcom/sitecube_proc/model_files_20231129/"

## Sites
sites <- str_extract(list.files(data_path_fluxes), pattern = "[:upper:]{2}-[:alnum:]{3}") %>% unique()
sites2 <- str_extract(list.files(data_path_meteo), pattern = "[:upper:]{2}-[:alnum:]{3}") %>% unique()


## Combine site list
# TO DO: check what is missing, and possibly integrate from other sources
sites <- intersect(sites, sites2); rm(sites2)



### Filtering thresholds -------------------------------------------------------
QCfilt <- c(0, 1) # quality filter
GSfilt <- 0.3     # growing season
Pfilt  <- 0.1     # precipitation filter
Pfilt_time <- 48  # period to exclude after precipitation events (hours)
SWfilt <- 50      # radiation filter (daytime) --> fixed to 100 for every EFP for streamlining (but still conservative)
USfilt <- 0.2     # u* filter
GPPsatfilt <- 60  # filter for GPPsat outliers
Rfilt  <- 30      # filter for RECO_NT outliers

min_years <- 5    # minimum number of years EFP calculations
min_months <- 3   # minimum number of months in a site-year (used to calculated min. half-hourly entries)



### Initialization -------------------------------------------------------------
# Initialize output
efps_out <- tibble()

# Initialize evaluation
n0 <- length(sites) # number of sites BEFORE filter



### Sites of Interest ----------------------------------------------------------
# Sites of interest (mostly for testing without the full site list)
# load(file = glue("data/sites_trend_efp_{vers_out}.RData")) # sites_trend_efp from trend analysis in calculate_eco_stability.R script
rangesites <- 1:length(sites) #which(sites == "BE-Lcr") #
site_list <- split(sites[rangesites], seq(length(sites[rangesites]))); # site_list <- as.list(sites[rangesites]) # simpler, check later if it works
# site_list <- as.list(sites[sites %in% sites_trend_efp])

# Random indexes for plotting
set.seed(34743821)
random_n <- as.integer(runif(10, min = 1, max = n0)) %>% sort()
rand_sites <- sites[random_n] # random sites for time-series plots
# rand_sites <- sites_trend_efp


#### Parallelization -----------------------------------------------------------
# ## Test function ----
# efps_test <- import_data_and_calc_EFPs(site_list = site_list[2], path_fluxes = data_path_fluxes, path_meteo = data_path_meteo, plotting = F)
# # works as of 25.03.2026 for AT-Neu
# clim_test <- import_data_and_calc_CLIM(site_list = site_list[2], path_fluxes = data_path_fluxes, path_meteo = data_path_meteo, plotting = F)
# # works as of 25.03.2026 for AT-Neu
# 
#
# ## Test sequential computation time ----
# efps_out <- tibble()
# tic("Time to import, process data, and calculate EFPs for all sites (sequential)")
# for (ii in 1:length(site_list)) {
#   temp_out <- import_data_and_calc_EFPs(site_list = site_list[ii], path_fluxes = data_path_fluxes, path_meteo = data_path_meteo, plotting = F)
#   efps_out <- bind_rows(efps_out, temp_out)
# }
# toc()
# # With 2 cpus, saved ~ 20-25% of the time for full sites and 35% for site-years;
# 
# 
## Define computing strategy ----
# if (getwd() == "C:/Users/ugomar/Desktop/multifunctionality") {
#   plan(multisession, workers = 2) # works as of 26.01.2024 17:05
# } else if (getwd() == "/Net/Groups/BGI/people/ugomar/codes/multifunctionality") {
ncpus <- as.integer(readline(prompt = "How many CPUs should be used for parallel computing? (Careful, check core availability!):"))
plan(cluster, workers = ncpus)
# }


### Run functions (parallel computing) -----------------------------------------
## Calculate EFPs ----
txt <- glue::glue("### Calculation of EFPs ###")
print(txt); if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}

tic("")
efps_out <- future_map_dfr( # output as row-bound dataframe
  .x = site_list, .f = import_data_and_calc_EFPs, path_fluxes = data_path_fluxes, path_meteo = data_path_meteo, plotting = T,
  .options = furrr_options(
    seed = 1234, scheduling = Inf, chunk_size = NULL), # scheduling set to Inf creates n_x chunks (1 chunk per element of .x).
  .progress = T
)
toc(log = T); log_efps <- tic.log(format = T)[[1]]; tic.clearlog()
# works as of 30.01.2024 17:59 for all EFPs, for full sites and by years


## Aggregate CLIMATE and site characteristics (e.g. soil) ----
txt <- glue::glue("### Aggregation of climatic variables ###")
print(txt); if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}

tic("")
clim_out <- future_map_dfr( # output as row-bound dataframe
  .x = site_list, .f = import_data_and_calc_CLIM, path_fluxes = data_path_fluxes, path_meteo = data_path_meteo, plotting = T,
  .options = furrr_options(
    seed = 1234, scheduling = Inf, chunk_size = NULL), # scheduling set to Inf creates n_x chunks (1 chunk per element of .x).
  .progress = T
)
toc(log = T); log_clim <- tic.log(format = T)[[1]]; tic.clearlog()



## Revert to default computing strategy to avoid issues ----
plan(sequential)



## Evaluation computed sites ----
txt <- "================================================================================"
if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}

n_efps <- efps_out %>% pull(SITE_ID) %>% unique() %>% length() # number of processed sites (incl. failed processing) for EFPs
n_clim <- clim_out %>% pull(SITE_ID) %>% unique() %>% length() # number of processed sites (incl. failed processing) for climate

txt <- glue::glue("Time to import, process data, and calculate EFPs for {n_efps} sites (parallel): {log_efps}.")
if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}
txt <- glue::glue("Time to import, process data, and aggregate climatic variables for {n_clim} sites (parallel): {log_clim}.")
if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}

failed_sites <- efps_out[rowSums(is.na(efps_out[, 0:ncol(efps_out)])) == ncol(efps_out) - 1, ] %>% pull(SITE_ID) # record sites where calculations failed


## Remove empty output ----
efps_out <- efps_out[rowSums(is.na(efps_out[, 0:ncol(efps_out)])) < ncol(efps_out) - 1, ] # remove empty rows
efps_out

clim_out <- clim_out[rowSums(is.na(clim_out[, 0:ncol(clim_out)])) < ncol(clim_out) - 1, ] # remove empty rows
clim_out



### Evaluation -----------------------------------------------------------------
n_efps <- efps_out %>% pull(SITE_ID) %>% unique() %>% length() # number of sites with valid EFP calculation
txt <- glue::glue("====> Calculations of EFPs was performed correctly for {n_efps} site(s). {n0 - n_efps} site(s) unavailable.")
print(txt); if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}
if (length(failed_sites) > 0) {txt <- glue::glue("Calculations failed for site(s): {paste(failed_sites, collapse = ', ')}."); print(txt); if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}}



### Select and rename variables ------------------------------------------------
efps_out <- efps_out %>% 
  dplyr::select(-NEP99) %>% 
  dplyr::rename(
    CUEeco = CUEeco90,
    NEPmax = NEP95
  ) %>% 
  glimpse()



### Vector names of variables --------------------------------------------------
if (savedata) {
  # Vector of names
  efps_names <- names(efps_out %>% dplyr::select(-SITE_ID, -contains("pval"), -contains("YEAR"))) # efps_names <- c("CUEeco", "GPPsat", "Gsmax", "NEPmax", "uWUE", "WUE")
  clim_names <- names(clim_out %>% dplyr::select(-SITE_ID, -contains("YEAR"))) %>% sort()
  # Save
  save(efps_names, file = glue::glue("data/inter/efps_names_{vers_out}.RData"))
  save(clim_names, file = glue::glue("data/inter/clim_names_{vers_out}.RData"))
}



### Combine data ---------------------------------------------------------------
if (rlang::is_empty(as.character(grouping_var))) {
  join_vars <- "SITE_ID"
} else if (!rlang::is_empty(as.character(grouping_var))) {
  join_vars <- c("SITE_ID", "YEAR")
}
dat_all <- efps_out %>% # EFPs
  dplyr::left_join(clim_out, by = join_vars) %>% # climate
  glimpse()
# DROP sites with no valid climate? or check again why calculation failed?



### Plot -----------------------------------------------------------------------
p_efps <- efps_out %>%
  pivot_longer(cols = c(!SITE_ID & !contains("pval")),
               names_to = "VARIABLENAME", values_to = "DATAVALUE") %>%
  ggplot() +
  geom_point(aes(SITE_ID, DATAVALUE), alpha = 0.8, color = "#808080", size = 3) +
  facet_wrap(. ~ VARIABLENAME, scales = "free_y") +
  labs(caption = paste("n =", nrow(efps_out))) +
  theme_classic() +
  theme(axis.title = element_text(size = 24),
        axis.text = element_text(size = 16),
        axis.text.x = element_text(angle = 270), # rotate x axis text
        panel.grid.major = element_line(),
        plot.caption = element_text(size = 24),  # caption text
        plot.margin = margin(10, 10, 10, 10, unit = "mm"), # margins around plot
        strip.text = element_text(size = 20),    # subplots title text
        strip.background = element_blank()       # subplots title with no border
  )
print(p_efps)

p_clim <- clim_out %>%
  pivot_longer(cols = c(!SITE_ID), names_to = "VARIABLENAME", values_to = "DATAVALUE") %>%
  ggplot() +
  geom_point(aes(SITE_ID, DATAVALUE), alpha = 0.8, color = "#808080", size = 3) +
  facet_wrap(. ~ VARIABLENAME, scales = "free_y") +
  labs(caption = paste("n =", nrow(clim_out))) +
  theme_classic() +
  theme(axis.title = element_text(size = 24),
        axis.text = element_text(size = 16),
        axis.text.x = element_text(angle = 270), # rotate x axis text
        panel.grid.major = element_line(),
        plot.caption = element_text(size = 24),  # caption text
        plot.margin = margin(10, 10, 10, 10, unit = "mm"), # margins around plot
        strip.text = element_text(size = 20),    # subplots title text
        strip.background = element_blank()       # subplots title with no border
  )
print(p_clim)

## Save plot
if (savedata) {
  ggsave(filename = glue::glue("EFPs{groupin}.jpg"),
         plot = p_efps, device = "jpeg", path = "results/scatterplots",
         width = 508, height = 285.75, units = "mm", dpi = 300) # 1920 x  1080 px resolution (16:9)
  ggsave(filename = glue::glue("CLIM{groupin}.jpg"),
         plot = p_clim, device = "jpeg", path = "results/scatterplots",
         width = 508, height = 285.75, units = "mm", dpi = 300) # 1920 x  1080 px resolution (16:9)
}



### Save -----------------------------------------------------------------------
if (savedata) {
  write_csv(efps_out, glue::glue("data/inter/efps{groupin}_{vers_out}.csv")) # EFPs
  write_csv(clim_out, glue::glue("data/inter/clim{groupin}_{vers_out}.csv")) # climate
  write_csv(dat_all, glue::glue("data/inter/data_efps_clim{groupin}_{vers_out}.csv")) # all data
}



### End ------------------------------------------------------------------------
toc(log = T)
txt <- glue::glue("Script total run time: {tic.log(format = T)[[1]]}."); tic.clearlog()
if (savedata) {cat(paste0(txt, "\n"), file = eval_file, append = T)}
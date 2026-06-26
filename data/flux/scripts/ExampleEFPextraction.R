## ---------------------------
##
## Script name: ExampleEFPextraction.R 
##
## Purpose of script: This script calculates ecosystem functional properties (EFP) from FLUXNET half-hourly observations
##                    For the detailed description see Methods section of Migliavacca et al., (2021), in review.
##
## Author: Mirco Migliavacca
##
## Date Created: 2021-05-25
## Email: mirco.migliavacca@gmail.com
## modified by Negin Katal 01.04.2025
## 
##
## ---------------------------
##
## Notes:
##   
##
## ---------------------------
###################################################
## -- Loading packages and install the missing ones
getwd() #-- Get the working directory
setwd("/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes") #-- Set the working directory to the folder with the script
rm(list = ls())

## -- Loading packages and install the missing ones
library(bigleaf)
library(purrr)
library(REddyProc)
library(stringr)
library(tidyr)
library(plyr)
library(dplyr)
library(broom)
library(sf)
library(lutz)
packages <- c("bigleaf", "purrr", "REddyProc", "stringr", "tidyr", "dplyr", "plyr", "broom", "lutz", "sf")

# Install packages not yet installed
installed_packages <- packages %in% rownames(installed.packages())
if (any(installed_packages == FALSE)) {
  install.packages(packages[!installed_packages])
}

invisible(lapply(packages, library, character.only = TRUE))

# ++ Function to calculate time zone

TimeZoneCalculatorFLUXNET <- function(lat = lat, long = long) {

  print('Calculation of Time zone')

  aaa <- tz_lookup_coords(lat, lon, method = "accurate", warn = FALSE)
 
  dfout <- tz_offset(as.POSIXct("2018-01-01 12:00:00", tz = tz_lookup_coords(-0.000500, 51.476852)), aaa)
  
  TimeZone_h.n<-dfout$utc_offset_h  
  return(TimeZone_h.n)
  
}

# ++ Function to calculate the functional properties

EFPcalc<-function(dat.all){

  #-- Set the growing season filter as 30% of the seasonal amplitude of daily GPP
  
  GSfilt <- 0.3

  if(is.na(summary(dat.all$P)[4]) | (summary(dat.all$P)[4] == 0)){
    print("##### Warning: no Precipitation data!!! No precipitation Filter")
    dat.filtered <- filter.data(data.frame(dat.all), quality.control = TRUE, filter.growseas=TRUE, filter.precip=FALSE, 
                                GPP="GPP_NT",doy="doy",year="year",tGPP=GSfilt,
                                precip="P", tprecip=0.1,precip.hours=24,records.per.hour=2,
                                vars.qc=c("TA","H","LE", "NEE", "VPD"), quality.ext="_QC",good.quality=1)
    precipAvail <- "no"
  } 
  
  if(!is.na(summary(dat.all$P)[4]) & (summary(dat.all$P)[4] != 0)){
    print("#### Precipitation data available!!! Precipitation Filter Active")
    # -- Indicate if the data are hourly (record.per.hour <- 1) or half-hourly (record.per.hour <- 2)
    record.per.hour <- 2
    
    dat.filtered <- filter.data(data.frame(dat.all), quality.control = TRUE, filter.growseas=TRUE, filter.precip=TRUE, 
                                GPP="GPP_NT",doy="doy",year="year",tGPP=GSfilt,
                                precip="P", tprecip=0.1,precip.hours=24,records.per.hour=record.per.hour,
                                vars.qc=c("TA","H","LE", "NEE", "VPD"), quality.ext="_QC",good.quality=1)
    precipAvail <- "yes"
  }  
  
  # Filtering G1 and WUE, remove also low u* values (u* <= 0.2)
  
  print('....computing WUE Metrics for the site')
  
  # Water-use efficiency (WUE):
  #   WUE = GPP / ET
  # 
  # Water-use efficiency based on NEE (WUE_NEE):
  #   WUE_NEE = NEE / ET
  #
  # Inherent water-use efficiency (IWUE; Beer et al. 2009):
  #   IWUE = (GPP * VPD) / ET
  # 
  # Underlying water-use efficiency (uWUE; Zhou et al. 2014):
  #   uWUE= (GPP * sqrt(VPD)) / ET
  # 
  # All metrics are calculated based on the median of all values. E.g. WUE = median(GPP/ET,na.rm=TRUE)
  # 
  aaa<-subset(dat.filtered, SW_IN > 200 & USTAR > 0.2)
  
  EFPsOut<-WUE.metrics(aaa, GPP = "GPP_NT", NEE = "NEE", LE = "LE", VPD = "VPD_kPa",
                       Tair = "TA", constants = bigleaf.constants())
  
  # Calculate maximum Evapotranspiration (95th percetile of half hourly values)
  
  print('....computing maximum Evapotranspiration')
  
  EFPsOut$ETmax<-quantile(aaa$ET, 0.95, na.rm=T)

  # Availability of precipitation
  EFPsOut$precipAvail <- precipAvail
  
  # Calculation of surface conductance and stomatal slope, G1
  print('....computing maximum surface conductance (Gsmax) and stomatal slope (G1)')
  
  # Using only measured data
  # -- Removing NA for wind speed and calculating air pressure from elevation data (Elevation is needed)
  
  aaa<- aaa %>% drop_na(WS)
  
  # -- Calculation of aerodynamic conductance
  
  if (dim(aaa)[1] != 0){
    aaa$pressure<-pressure.from.elevation(elevation,aaa$TA,aaa$VPD_kPa)
    Ga <- aerodynamic.conductance(aaa,Tair = "TA", pressure = "pressure",
                                  wind = "WS", ustar = "USTAR", H = "H", 
                                  Rb_model="Thom_1972")[,"Ga_h"]
  }
  
  if (dim(aaa)[1] == 0){
    aaa<-subset(dat.filtered, SW_IN > 200 & USTAR > 0.2)
    aaa$pressure<-pressure.from.elevation(elevation,aaa$TA,aaa$VPD_kPa)
    Ga <- 1
  }
  
  if(all(is.na(aaa$G))){
    Gs <- surface.conductance(aaa,Ga=Ga, Tair = "TA", pressure = "pressure", Rn = "NETRAD",
                              G = NULL, S = NULL, VPD = "VPD_kPa", LE = "LE",  
                              missing.G.as.NA = FALSE, 
                              missing.S.as.NA = FALSE)
    EFPsOut$Gavail<-"no"
  }
  
  if(!all(is.na(aaa$G))){
    Gs <- surface.conductance(aaa,Ga=Ga, Tair = "TA", pressure = "pressure", Rn = "NETRAD",
                              G = "G", S = NULL, VPD = "VPD_kPa", LE = "LE",  
                              missing.G.as.NA = FALSE, 
                              missing.S.as.NA = FALSE)
    EFPsOut$Gavail<-"yes"
  }
  
  aaa$Gs_mol<-Gs$Gs_mol
  
  aaa<- aaa %>% drop_na(Gs_mol)
  aaa <- subset(aaa, VPD_kPa > 0)

  #-- Calculation of maximum surface conductance as the 90th percentile of half hourly Gs
  EFPsOut$GSmax<-quantile(na.omit(Gs$Gs_ms), 0.90)
  
  nmin <- 40 #Set as 40 the minimum number of good data points to calculate the functions
  
  if(dim(aaa)[1] >= nmin){  
    
    if(all(is.na(aaa$CO2))){
      #- Fix CO2 concentration to 400 ppm if not available
      aaa$CO2 <- 400
      ### Use robust regression to minimize influence of outliers in Gs                           
      mod_USO <- stomatal.slope(aaa,model="USO",GPP="GPP_NT",Gs="Gs_mol", Tair = "TA", pressure = "pressure", 
                                VPD = "VPD_kPa", Ca = "CO2",robust.nls=TRUE,nmin=nmin,fitg0=FALSE)
      
      EFPsOut$CO2avail<-"no"
      
    }
    
    if(!all(is.na(aaa$CO2))){
      
      ### Use robust regression to minimize influence of outliers in Gs                           
      mod_USO <- stomatal.slope(aaa,model="USO",GPP="GPP_NT",Gs="Gs_mol", Tair = "TA", pressure = "pressure", 
                                VPD = "VPD_kPa", Ca = "CO2",robust.nls=TRUE,nmin=nmin,fitg0=FALSE)
      
      EFPsOut$CO2avail<-"yes"
      
    }
    
    EFPsOut$g1<-tidy(mod_USO)$estimate
    EFPsOut$g1_stderr<-tidy(mod_USO)$std.error
  }
  
  if(dim(aaa)[1] < nmin){  
    EFPsOut$g1<-NA
    EFPsOut$g1_stderr<-NA
  }

  print('....computing Evaporative fraction for the sites and its amplitude')
  
  aaa$EF <- aaa$LE/(aaa$LE+aaa$H)
  EFPsOut$EF <- median(aaa$EF, na.rm = TRUE)
  EFPsOut$EFampl <- quantile(na.omit(aaa$EF), 0.75, na.rm = TRUE) - quantile(na.omit(aaa$EF), 0.25, na.rm = TRUE)
  
  ### -- print('....computing LRC parameters for the site')
  print('....computing LRC parameters for the site')
  
  myLRC<-function(datafilt){
    
    numNAN<-150
    #if(sum(is.na(datafilt$NEE)) >= numNAN) return(NA)
    #browser()
    if(sum(is.na(datafilt$NEE))/length(datafilt$NEE) >= 0.8) return(NA)
    
    if(sum(is.na(datafilt$NEE))/length(datafilt$NEE) < 0.8){
      #print(paste("...optimizing..", unique(datafilt$FiveDaySeq)))
      # browser()
      result = tryCatch({
        fitLRC<-light.response(datafilt, NEE = "NEE", Reco = "Reco", PPFD = "PPFD",
                               PPFD_ref = 2000)
        out<-tidy(fitLRC)$estimate[2]
        return(out)
      }, error = function(e) {
        return(NA)
        
      })
      
      
    }
  }
  
  #Filter again data out all data with QC > 1 (retaining good quality 0 and 1), growing season, no precip filter
  
  dat.filtered <- filter.data(data.frame(dat.all), quality.control = TRUE, filter.growseas=TRUE, filter.precip=FALSE, 
                              GPP="GPP_NT",doy="doy",year="year",tGPP=GSfilt,
                              precip="P", tprecip=0.1,precip.hours=24,records.per.hour=2,
                              vars.qc=c("TA","H","LE", "NEE", "VPD"), quality.ext="_QC",good.quality=1)
  
  
  dat.filtered$FiveDaySeq<-rep(c(1:ceiling(dim(dat.filtered)[1]/5)),each = 48*5, length.out=dim(dat.filtered)[1])
  
  zzz<-data.frame(NEE=dat.filtered$NEE,
                  PPFD=dat.filtered$PPFD_IN_FROM_SWIN,
                  Reco=dat.filtered$RECO_NT,
                  FiveDaySeq = dat.filtered$FiveDaySeq)
  
  outGPPsat <- unlist(by(zzz, zzz$FiveDaySeq, myLRC), use.names=FALSE)
  
  EFPsOut$GPPsat<-quantile(outGPPsat, 0.90, na.rm = T)  
  EFPsOut$NEPmax<-quantile(na.omit(subset(zzz, PPFD > 200*2.11)$NEE*-1), 0.99)
  
  ### -- print('....computing Basal respiration with REddyProc')
  print('....computing Rb parameters for the site')
  
  ttt<-data.frame(dat.all)
  ttt$DateTime<-ttt$DateTime + 30*30
  TimeZone <- TimeZoneCalculatorFLUXNET(lat, lon)
  
  EddyProc.C <- sEddyProc$new(site, ttt, c('NEE', 'NEE_QC_OK', 'SW_IN', 'SW_IN_QC_OK',
                                           'TA','TA_QC_OK'),LatDeg=as.numeric(lat), LongDeg=as.numeric(lon),TimeZoneHour=TimeZone)
  
  #-- Run the nighttime partitioning for the calculation  of basal respiration
  
  print('Run the nighttime partitioning for the calculation  of basal respiration')
  
  EddyProc.C$sMRFluxPartition(FluxVar.s = "NEE", QFFluxVar.s = "NEE_QC_OK", 
                              QFFluxValue.n = 1, TempVar.s = "TA", QFTempVar.s = "TA_QC_OK", 
                              QFTempValue.n = 1, RadVar.s = "SW_IN", T_ref.n = 273.15 + 15, 
                              Suffix.s = "")
  
  EFPsOut$Rb<-mean(EddyProc.C$sTEMP$R_ref, na.rm = T)
  EFPsOut$Rbmax<-quantile(EddyProc.C$sTEMP$R_ref, 0.95)

  #-- Apparent Carbon Use Efficiency
  print('Calculation of apparent Carbon Use Efficiency, aCUE')
  
  dat.all$Rb <- ifelse(is.null(EddyProc.C$sTEMP$R_ref), NA, EddyProc.C$sTEMP$R_ref)
  
  dat.filtered.CUE <- filter.data(data.frame(dat.all), quality.control = TRUE, filter.growseas=TRUE, filter.precip=FALSE, 
                                  GPP="GPP_NT",doy="doy",year="year",tGPP=GSfilt,
                                  precip="P", tprecip=0.1,precip.hours=24,records.per.hour=2,
                                  vars.qc=c("TA","H","LE", "NEE", "VPD"), quality.ext="_QC",good.quality=1)

  daily.aggr<-ddply(dat.filtered.CUE, .(year, doy), summarize, mean_GPP=mean(GPP_NT), mean_Rb=mean(Rb))
  
  EFPsOut$aCUE <- median(1-(daily.aggr$mean_Rb/daily.aggr$mean_GPP), na.rm=TRUE)
  EFPsOut$TZ<-as.numeric(TimeZone)
  EFPsOut$nyears<-nyears
  EFPsOut$SITE_ID <- site
  
  EFPsF15LT<-unlist(EFPsOut)
  
  names(EFPsF15LT) <- str_replace_all(names(EFPsF15LT),c("ETmax.95%" = "ETmax",
                                     "GSmax.90%" = "GSmax",
                                     "g1" = "G1",
                                     "EFampl.75%" = "EFampl",  
                                     "GPPsat.90%" = "GPPsat",
                                     "NEPmax.99%" = "NEPmax",
                                     "Rbmax.95%" = "Rbmax"))
  
  EFPsF15LT <- data.frame(t(EFPsF15LT))
  output.EFPs <- subset(EFPsF15LT, select = c("uWUE","ETmax","precipAvail","Gavail","GSmax","CO2avail","G1",
                              "EF","EFampl","GPPsat","NEPmax","Rb","Rbmax","aCUE","TZ","nyears","SITE_ID"))
  
  print(paste0("...Finish site ",site))
  
  return(output.EFPs)
}



ClimateCalc <- function(dat.all){
  # ---- Climate Descriptors ----
  print("....computing climate descriptors")
  
  out <- list()
  
  # Mean annual precipitation (mm)
  out$P_mean <- mean(dat.all$P, na.rm = TRUE)
  
  # Growing season filtered data: use same GPP filter as EFPcalc
  GSfilt <- 0.3
  gs_data <- filter.data(
    data.frame(dat.all),
    quality.control = TRUE,
    filter.growseas = TRUE,
    filter.precip = FALSE,
    GPP = "GPP_NT", doy = "doy", year = "year", tGPP = GSfilt,
    precip = "P", tprecip = 0.1, precip.hours = 24, records.per.hour = 2,
    vars.qc = c("TA","H","LE","NEE","VPD"), quality.ext = "_QC", good.quality = 1
  )
  
  # Means during growing season
  out$VPD_mean   <- mean(gs_data$VPD,   na.rm = TRUE)   # hPa
  out$SWin_mean  <- mean(gs_data$SW_IN, na.rm = TRUE)   # W/m2
  out$Tair_mean  <- mean(gs_data$TA,    na.rm = TRUE)   # °C
  
  # Cumulative Soil Water Index (if available)
  if("CSWI" %in% names(dat.all)){
    out$CSWI_cum <- sum(dat.all$CSWI, na.rm = TRUE)
  } else {
    out$CSWI_cum <- NA
  }
  
  return(data.frame(t(unlist(out))))
}
#### add the information of your site
elevation <- 201 #-- Elevation from the FLUXNET BADM
site <- 'DE-Har' 
lat <- 47.9330
lon <- 7.5981
TimeZone <- TimeZoneCalculatorFLUXNET(lat = lat, long = lon)

#### test data from Mirco
dat.all <- get(load('MigliavaccaEcosystemfunctionsReprWorkflow/data/AT-Neu.Rdata'))
dat.all <- flux_all_cleaned %>% 
  filter(siteID == "DE-Har") 

dat.all <- dat.all %>%
  mutate(DateTime = DateTime + lubridate::minutes(15))

syear<-min(range(unique(dat.all$year)))
eyear<-max(range(unique(dat.all$year))) 
nyears<-length(unique(dat.all$year))

## Units conversions and variables calculations

dat.all$ET <- LE.to.ET(dat.all$LE, dat.all$TA)*1800 # Conversion from W/m2 to mmH20
dat.all$precip_mm <- dat.all$P
dat.all$VPD_kPa <- dat.all$VPD/10
dat.all$PPFD_IN_FROM_SWIN <- dat.all$SW_IN*2.11 # Conversion from Shortwave radiation in W/m2 to PPFD in umol/m2/s

safeEFPs <- possibly(EFPcalc, otherwise = "Error") 
out <- safeEFPs(dat.all)

out <- EFPcalc(dat.all)

#### READ THE clean ICOS or AmeriFlux
library(data.table)
flux_all <- fread("clean_data/ICOS_HH_for_EFP.csv")
flux_all <- fread("clean_data/408_site_HH.csv")
flux_all <- combined_df_renamed
colnames(flux_all)
##if you read this file 408_site_HH.csv no need for runing the next line
flux_all <- flux_all %>%
  mutate(
    NEE_QC_OK = NEE_QC,
    SW_IN_QC_OK = SW_IN_QC,
    TA_QC_OK = TA_QC )





DE_Har <- flux_all_cleaned %>% 
  filter(siteID=="DE-Har")
all_tower_loc <- fread("clean_data/combined_site_metadata.csv")

### add the needed column 
### in the new version (408_site_HH) is already added
flux_df <- flux_df %>%
  mutate(
    NEE_QC_OK = NEE_QC,
    SW_IN_QC_OK = SW_IN_QC,
    TA_QC_OK = TA_QC )


flux_df <- flux_all %>% 
  filter(siteID=="DE-Har")
### if you want to test it only for one site
### add the information of interested site
elevation <- 201 #-- Elevation from the FLUXNET BADM
site <- 'DE-Har' 
lat <- 47.933
lon <- 7.5981
TimeZone <- TimeZoneCalculatorFLUXNET(lat = lat, long = lon)

syear <- min(flux_df$year, na.rm = TRUE)
eyear <- max(flux_df$year, na.rm = TRUE)
nyears <- length(unique(flux_df$year))

## Units conversions and variables calculations

flux_df$ET <- LE.to.ET(flux_df$LE, flux_df$TA)*1800 # Conversion from W/m2 to mmH20
flux_df$precip_mm <- flux_df$P
flux_df$VPD_kPa <- flux_df$VPD/10
flux_df$PPFD_IN_FROM_SWIN <- flux_df$SW_IN*2.11 # Conversion from Shortwave radiation in W/m2 to PPFD in umol/m2/s

####Check the DateTiecolumn it should start with 00:15:00 and end with 23:45:00 if not added needed min 
flux_df <- flux_df %>%
  mutate(DateTime = DateTime + lubridate::minutes(15))


safeEFPs <- possibly(EFPcalc, otherwise = "Error")
#run either this
efp_results <- safeEFPs(flux_df)
## or directly this
efp_results <- EFPcalc(flux_df)

########################################################
##### loop over the each year seperately
years <- unique(dat.all$year)

# Safe wrapper
safeEFPs <- possibly(EFPcalc, otherwise = "Error")

# Initialize storage
results_list <- list()

# Loop over years
for (yr in years) {
  message("Running EFPcalc for year: ", yr)
  
  dat_year <- subset(dat.all, year == yr)
  
  out <- safeEFPs(dat_year)
  
  # Only store if no error
  if (!identical(out, "Error")) {
    out$year <- yr
    results_list[[as.character(yr)]] <- out
  }
}

# Combine all outputs
efp_yearly <- do.call(rbind, results_list)
#####loop over all sites
library(dplyr)
library(lubridate)
library(purrr)
######### Here we will take the site Info from tower_meta file and calculate the EFP for each site
# Create a safe version of EFPcalc to avoid breaking the loop
tower_meta <- fread("clean_data/combined_site_metadata.csv")
safeEFPcalc <- purrr::possibly(EFPcalc, otherwise = NA)

# Initialize list to store results
efp_results_list <- list()

# Loop through each unique SITE_ID in tower_meta or Icos_metadata
for (this_site in unique(tower_meta$SITE_ID)) {
  message("Processing site: ", this_site)
  
  # Extract site info
  site_info <- tower_meta %>% filter(SITE_ID == this_site)
  
  # Skip if location info is missing
  if (any(is.na(site_info$LOCATION_ELEV), is.na(site_info$LOCATION_LAT), is.na(site_info$LOCATION_LONG))) {
    warning("Missing location info for site ", this_site, "; skipping.")
    next
  }
  
  # Convert site metadata
  site <- site_info$SITE_ID
  elevation <- as.numeric(site_info$LOCATION_ELEV)
  lat <- as.numeric(site_info$LOCATION_LAT)
  lon <- as.numeric(site_info$LOCATION_LONG)
  
  # Compute timezone
  TimeZone <- TimeZoneCalculatorFLUXNET(lat = lat, long = lon)
  
  # Subset flux data
  flux_df <- flux_all %>% filter(siteID == this_site)
  syear <- min(flux_df$year, na.rm = TRUE)
  eyear <- max(flux_df$year, na.rm = TRUE)
  nyears <- length(unique(flux_df$year))
  # Skip if no data
  if (nrow(flux_df) == 0) {
    warning("No data for site ", this_site, "; skipping.")
    next
  }
  
  # DateTime adjustments
  flux_df <- flux_df %>%
    mutate(
      ET = LE.to.ET(LE, TA) * 1800,
      precip_mm = P,
      VPD_kPa = VPD / 10,
      PPFD_IN_FROM_SWIN = SW_IN * 2.11,
      DateTime = DateTime + minutes(15)
    )
  
  # Run EFPcalc
  efp_result <- safeEFPcalc(flux_df)
  efp_results_list[[this_site]] <- efp_result
}

library(purrr)
library(dplyr)

efp_results_list_df <- efp_results_list[sapply(efp_results_list, is.data.frame)]
efp_all <- bind_rows(efp_results_list_df, .id = "siteID")

efp_with_meta <- merge(efp_all, tower_meta, by= "SITE_ID")

write.csv(efp_with_meta,"clean_data/EFP_per_sitesV01.csv", row.names = FALSE)
###################################################################################
##### if you want to calculate the properties yearly use this:
library(data.table)
library(dplyr)
library(purrr)
library(lubridate)

tower_meta <- fread("clean_data/combined_site_metadata.csv")
flux_all <- fread("clean_data/408_site_HH.csv")
safeEFPcalc <- purrr::possibly(EFPcalc, otherwise = NA)

# Initialize results list
efp_results_list <- list()

# Loop over each site
for (this_site in unique(tower_meta$SITE_ID)) {
  message("Processing site: ", this_site)
  
  # Extract metadata
  site_info <- tower_meta %>% filter(SITE_ID == this_site)
  
  # Skip if any location info is missing
  if (any(is.na(site_info$LOCATION_ELEV), is.na(site_info$LOCATION_LAT), is.na(site_info$LOCATION_LONG))) {
    warning("Missing location info for site ", this_site, "; skipping.")
    next
  }
  
  lat <- as.numeric(site_info$LOCATION_LAT)
  lon <- as.numeric(site_info$LOCATION_LONG)
  elevation <- as.numeric(site_info$LOCATION_ELEV)
  
  # Compute timezone
  TimeZone <- TimeZoneCalculatorFLUXNET(lat = lat, long = lon)
  
  # Subset flux data
  flux_df <- flux_all %>% filter(siteID == this_site)
  
  # Skip if no data
  if (nrow(flux_df) == 0) {
    warning("No data for site ", this_site, "; skipping.")
    next
  }
  
  # Adjust variables
  flux_df <- flux_df %>%
    mutate(
      ET = LE.to.ET(LE, TA) * 1800,
      precip_mm = P,
      VPD_kPa = VPD / 10,
      PPFD_IN_FROM_SWIN = SW_IN * 2.11,
      DateTime = DateTime + minutes(15)
    )
  
  # Loop over each year for this site
  for (yr in unique(flux_df$year)) {
    message("  → Calculating EFPs for year: ", yr)
    
    dat_year <- filter(flux_df, year == yr)
    
    efp_result <- safeEFPcalc(dat_year)
    
    if (!is.null(efp_result) && is.data.frame(efp_result)) {
      efp_result$SITE_ID <- this_site
      efp_result$year <- yr
      efp_results_list[[paste0(this_site, "_", yr)]] <- efp_result
    }
  }
}

# Combine all valid results
efp_results_list_df <- efp_results_list[sapply(efp_results_list, is.data.frame)]
efp_all <- bind_rows(efp_results_list_df)

# Join with metadata
efp_with_meta <- left_join(efp_all, tower_meta, by = "SITE_ID")

# Save to file
write.csv(efp_with_meta, "clean_data/efp_by_site_year_V2.csv", row.names = FALSE)

######
climate_results_list <- list()

for (this_site in unique(tower_meta$SITE_ID)) {
  message("Processing climate vars for site: ", this_site)
  
  flux_df <- flux_all %>% filter(siteID == this_site)
  
  if (nrow(flux_df) == 0) next
  
  for (this_year in unique(flux_df$year)) {
    flux_year <- flux_df %>% filter(year == this_year)
    
    if (nrow(flux_year) == 0) next
    
    climate_result <- ClimateCalc(flux_year)
    climate_result$SITE_ID <- this_site
    climate_result$year <- this_year
    
    climate_results_list[[paste0(this_site, "_", this_year)]] <- climate_result
  }
}

climate_all <- bind_rows(climate_results_list, .id = "siteID")
fwrite(climate_all, "clean_data/climate_yearly_allsite.csv")
### let's read Ulisse's data
input_data <- fread("uligom-EcosystemScaleCoordinationPrinciples/Input data.csv")
getwd()
#################################################################################################################################################

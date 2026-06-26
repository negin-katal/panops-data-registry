setwd("/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes")
getwd()
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
##
## Email: mirco.migliavacca@gmail.com
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
library(lutz)
install.packages("sf")
library(sf)
packages <- c("bigleaf", "purrr", "REddyProc", "stringr", "tidyr", "dplyr", "plyr", "broom", "lutz")

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

EFPcalc <- function(dat.all) {
  GSfilt <- 0.3
  
  if (is.na(summary(dat.all$P)[4]) | (summary(dat.all$P)[4] == 0)) {
    print("##### Warning: no Precipitation data!!! No precipitation Filter")
    dat.filtered <- filter.data(
      data.frame(dat.all), quality.control = TRUE, filter.growseas = TRUE, filter.precip = FALSE,
      GPP = "GPP_NT", doy = "doy", year = "year", tGPP = GSfilt,
      precip = "P", tprecip = 0.1, precip.hours = 24, records.per.hour = 2,
      vars.qc = c("TA", "H", "LE", "NEE", "VPD"), quality.ext = "_QC", good.quality = 1
    )
    precipAvail <- "no"
  } else {
    print("#### Precipitation data available!!! Precipitation Filter Active")
    dat.filtered <- filter.data(
      data.frame(dat.all), quality.control = TRUE, filter.growseas = TRUE, filter.precip = TRUE,
      GPP = "GPP_NT", doy = "doy", year = "year", tGPP = GSfilt,
      precip = "P", tprecip = 0.1, precip.hours = 24, records.per.hour = 2,
      vars.qc = c("TA", "H", "LE", "NEE", "VPD"), quality.ext = "_QC", good.quality = 1
    )
    precipAvail <- "yes"
  }
  
  print('....computing WUE Metrics for the site')
  aaa <- subset(dat.filtered, SW_IN > 200 & USTAR > 0.2)
  EFPsOut <- WUE.metrics(aaa, GPP = "GPP_NT", NEE = "NEE", LE = "LE", VPD = "VPD_kPa",
                         Tair = "TA", constants = bigleaf.constants())
  EFPsOut[["ETmax"]] <- quantile(aaa$ET, 0.95, na.rm = TRUE)[[1]]
  EFPsOut[["precipAvail"]] <- precipAvail
  
  print('....computing maximum surface conductance (Gsmax) and stomatal slope (G1)')
  aaa <- aaa %>% drop_na(WS)
  
  if (nrow(aaa) != 0) {
    aaa$pressure <- pressure.from.elevation(elevation, aaa$TA, aaa$VPD_kPa)
    Ga <- aerodynamic.conductance(aaa, Tair = "TA", pressure = "pressure",
                                  wind = "WS", ustar = "USTAR", H = "H", Rb_model = "Thom_1972")[, "Ga_h"]
  } else {
    aaa <- subset(dat.filtered, SW_IN > 200 & USTAR > 0.2)
    aaa$pressure <- pressure.from.elevation(elevation, aaa$TA, aaa$VPD_kPa)
    Ga <- 1
  }
  
  if (all(is.na(aaa$G))) {
    Gs <- surface.conductance(aaa, Ga = Ga, Tair = "TA", pressure = "pressure", Rn = "NETRAD",
                              G = NULL, S = NULL, VPD = "VPD_kPa", LE = "LE",
                              missing.G.as.NA = FALSE, missing.S.as.NA = FALSE)
    EFPsOut[["Gavail"]] <- "no"
  } else {
    Gs <- surface.conductance(aaa, Ga = Ga, Tair = "TA", pressure = "pressure", Rn = "NETRAD",
                              G = "G", S = NULL, VPD = "VPD_kPa", LE = "LE",
                              missing.G.as.NA = FALSE, missing.S.as.NA = FALSE)
    EFPsOut[["Gavail"]] <- "yes"
  }
  
  aaa$Gs_mol <- Gs$Gs_mol
  aaa <- aaa %>% drop_na(Gs_mol)
  aaa <- subset(aaa, VPD_kPa > 0)
  EFPsOut[["GSmax"]] <- quantile(na.omit(Gs$Gs_ms), 0.90)[[1]]
  
  nmin <- 40
  if (nrow(aaa) >= nmin) {
    if (all(is.na(aaa$CO2))) {
      aaa$CO2 <- 400
      mod_USO <- stomatal.slope(aaa, model = "USO", GPP = "GPP_NT", Gs = "Gs_mol", Tair = "TA", pressure = "pressure",
                                VPD = "VPD_kPa", Ca = "CO2", robust.nls = TRUE, nmin = nmin, fitg0 = FALSE)
      EFPsOut[["CO2avail"]] <- "no"
    } else {
      mod_USO <- stomatal.slope(aaa, model = "USO", GPP = "GPP_NT", Gs = "Gs_mol", Tair = "TA", pressure = "pressure",
                                VPD = "VPD_kPa", Ca = "CO2", robust.nls = TRUE, nmin = nmin, fitg0 = FALSE)
      EFPsOut[["CO2avail"]] <- "yes"
    }
    EFPsOut[["g1"]] <- tidy(mod_USO)$estimate
    EFPsOut[["g1_stderr"]] <- tidy(mod_USO)$std.error
  } else {
    EFPsOut[["g1"]] <- NA
    EFPsOut[["g1_stderr"]] <- NA
  }
  
  print('....computing Evaporative fraction for the sites and its amplitude')
  aaa$EF <- aaa$LE / (aaa$LE + aaa$H)
  EFPsOut[["EF"]] <- median(aaa$EF, na.rm = TRUE)
  EFPsOut[["EFampl"]] <- quantile(aaa$EF, 0.75, na.rm = TRUE)[[1]] - quantile(aaa$EF, 0.25, na.rm = TRUE)[[1]]
  
  print('....computing LRC parameters for the site')
  myLRC <- function(datafilt) {
    if (sum(is.na(datafilt$NEE)) / length(datafilt$NEE) >= 0.8) return(NA)
    tryCatch({
      fitLRC <- light.response(datafilt, NEE = "NEE", Reco = "Reco", PPFD = "PPFD", PPFD_ref = 2000)
      tidy(fitLRC)$estimate[2]
    }, error = function(e) NA)
  }
  
  dat.filtered <- filter.data(data.frame(dat.all), quality.control = TRUE, filter.growseas = TRUE, filter.precip = FALSE,
                              GPP = "GPP_NT", doy = "doy", year = "year", tGPP = GSfilt,
                              precip = "P", tprecip = 0.1, precip.hours = 24, records.per.hour = 2,
                              vars.qc = c("TA", "H", "LE", "NEE", "VPD"), quality.ext = "_QC", good.quality = 1)
  
  dat.filtered$FiveDaySeq <- rep(1:ceiling(nrow(dat.filtered) / (5 * 48)), each = 48 * 5, length.out = nrow(dat.filtered))
  zzz <- data.frame(NEE = dat.filtered$NEE, PPFD = dat.filtered$PPFD_IN_FROM_SWIN, Reco = dat.filtered$RECO_NT,
                    FiveDaySeq = dat.filtered$FiveDaySeq)
  
  outGPPsat <- unlist(by(zzz, zzz$FiveDaySeq, myLRC), use.names = FALSE)
  EFPsOut[["GPPsat"]] <- quantile(outGPPsat, 0.90, na.rm = TRUE)[[1]]
  EFPsOut[["NEPmax"]] <- quantile(na.omit(subset(zzz, PPFD > 200 * 2.11)$NEE * -1), 0.99)[[1]]
  
  print('....computing Rb parameters for the site')
  ttt <- dat.all
  ttt$DateTime <- ttt$DateTime + 30 * 30
  TimeZone <- TimeZoneCalculatorFLUXNET(lat, lon)
  EddyProc.C <- sEddyProc$new(site, ttt, c("NEE", "NEE_QC_OK", "SW_IN", "SW_IN_QC_OK", "TA", "TA_QC_OK"),
                              LatDeg = as.numeric(lat), LongDeg = as.numeric(lon), TimeZoneHour = TimeZone)
  EddyProc.C$sMRFluxPartition("NEE", "NEE_QC_OK", 1, "TA", "TA_QC_OK", 1, "SW_IN", T_ref.n = 273.15 + 15, Suffix.s = "")
  EFPsOut[["Rb"]] <- mean(EddyProc.C$sTEMP$R_ref, na.rm = TRUE)
  EFPsOut[["Rbmax"]] <- quantile(EddyProc.C$sTEMP$R_ref, 0.95)[[1]]
  
  print('Calculation of apparent Carbon Use Efficiency, aCUE')
  dat.all$Rb <- ifelse(is.null(EddyProc.C$sTEMP$R_ref), NA, EddyProc.C$sTEMP$R_ref)
  dat.filtered.CUE <- filter.data(dat.all, quality.control = TRUE, filter.growseas = TRUE, filter.precip = FALSE,
                                  GPP = "GPP_NT", doy = "doy", year = "year", tGPP = GSfilt,
                                  precip = "P", tprecip = 0.1, precip.hours = 24, records.per.hour = 2,
                                  vars.qc = c("TA", "H", "LE", "NEE", "VPD"), quality.ext = "_QC", good.quality = 1)
  daily.aggr <- ddply(dat.filtered.CUE, .(year, doy), summarize,
                      mean_GPP = mean(GPP_NT), mean_Rb = mean(Rb))
  EFPsOut[["aCUE"]] <- median(1 - (daily.aggr$mean_Rb / daily.aggr$mean_GPP), na.rm = TRUE)
  
  EFPsOut[["TZ"]] <- as.numeric(TimeZone)
  EFPsOut[["nyears"]] <- nyears
  EFPsOut[["SITE_ID"]] <- site
  
  EFPsF15LT <- unlist(EFPsOut)
  names(EFPsF15LT) <- str_replace_all(names(EFPsF15LT), c(
    "ETmax.95%" = "ETmax", "GSmax.90%" = "GSmax", "g1" = "G1", "EFampl.75%" = "EFampl",
    "GPPsat.90%" = "GPPsat", "NEPmax.99%" = "NEPmax", "Rbmax.95%" = "Rbmax"
  ))
  EFPsF15LT <- data.frame(t(EFPsF15LT))
  output.EFPs <- subset(EFPsF15LT, select = c("uWUE", "ETmax", "precipAvail", "Gavail", "GSmax", "CO2avail", "G1",
                                              "EF", "EFampl", "GPPsat", "NEPmax", "Rb", "Rbmax", "aCUE", "TZ", "nyears", "SITE_ID"))
  print(paste0("...Finish site ", site))
  return(output.EFPs)
}

elevation <- 970 #-- Elevation from the FLUXNET BADM
site <- 'AT-Neu' 
lat <- 47.1167
lon <- 11.3175
TimeZone <- 1 #-- For other sites can be calculated using the function TimeZoneCalculatorFLUXNET 

dat.all <- get(load('MigliavaccaEcosystemfunctionsReprWorkflow/data/AT-Neu.Rdata'))

syear<-min(range(unique(dat.all$year)))
eyear<-max(range(unique(dat.all$year))) 
nyears<-length(unique(dat.all$year))

## Units conversions and variables calculations

dat.all$ET <- LE.to.ET(dat.all$LE, dat.all$TA)*1800 # Conversion from W/m2 to mmH20
dat.all$precip_mm <- dat.all$P
dat.all$VPD_kPa <- dat.all$VPD/10
dat.all$PPFD_IN_FROM_SWIN <- dat.all$SW_IN*2.11 # Conversion from Shortwave radiation in W/m2 to PPFD in umol/m2/s

safeEFPs <- possibly(EFPcalc, otherwise = "Error") 
out <- EFPcalc(dat.all)
out <- safeEFPs(dat.all)
str(dat.all)
debugonce(EFPcalc)
EFPcalc(dat.all)
print(out) 
str(dat.all)
colnames(dat.all)

print("Available variable names in EFPsF15LT:")
print(names(EFPsF15LT))

library(data.table)
flux_df <- fread("clean_data/NEP_with_GS.csv")

flux_df <- as.data.frame(flux_df)  # if still a data.table

flux_df$GPP_NT <- flux_df$GPP_NT_VUT_REF
flux_df$NEE <- flux_df$NEE_VUT_REF
flux_df$RECO_NT <- flux_df$RECO_NT_VUT_REF
flux_df$ET <- LE.to.ET(flux_df$LE_F_MDS, flux_df$TA_F) * 1800  # W/m² to mm/half-hour
flux_df$TA <- flux_df$TA_F
flux_df$VPD_kPa <- flux_df$VPD_F / 10
flux_df$VPD <- flux_df$VPD_F
flux_df$SW_IN <- flux_df$SW_IN_F_MDS
flux_df$LE <- flux_df$LE_F_MDS
flux_df$H <- flux_df$H_F_MDS
flux_df$USTAR <- flux_df$USTAR
flux_df$WS <- flux_df$WS
flux_df$NETRAD <- flux_df$NETRAD
flux_df$G <- flux_df$G_F_MDS
flux_df$PPFD_IN_FROM_SWIN <- flux_df$SW_IN_F_MDS * 2.11
flux_df$P <- flux_df$P_F
flux_df$DateTime <- flux_df$datetime  # assuming POSIXct already

flux_df$doy <- as.numeric(format(flux_df$DateTime, "%j"))
flux_df$year <- as.numeric(format(flux_df$DateTime, "%Y"))
##### quality control
flux_df$TA_QC_OK <- 1
flux_df$H_QC_OK <- 1
flux_df$LE_QC_OK <- 1
flux_df$NEE_QC_OK <- 1
flux_df$VPD_QC_OK <- 1
flux_df$SW_IN_QC_OK <- 1  # Needed for REddyProc
flux_df$TA_QC <- 0
flux_df$H_QC <- 0
flux_df$LE_QC <- 0
flux_df$NEE_QC <- 0
flux_df$VPD_QC <- 0

str(flux_df)

elevation <- 438 #-- Elevation from the FLUXNET BADM
site <- 'DE-Hai' 
lat <- 51.079212
lon <- 10.452168
syear <- min(flux_df$year, na.rm = TRUE)
eyear <- max(flux_df$year, na.rm = TRUE)
nyears <- length(unique(flux_df$year))


safeEFPs <- possibly(EFPcalc, otherwise = "Error")
efp_results <- safeEFPs(flux_df)


efp_results <- EFPcalc(flux_df)

str(flux_df)

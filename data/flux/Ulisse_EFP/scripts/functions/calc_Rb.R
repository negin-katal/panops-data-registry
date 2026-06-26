#### CALCULATE RESPIRATION (Rb, Rbmax)

### Authors: Ulisse Gomarasca (ugomar@bgc-jena.mpg.de), Mirco Migliavacca
### Attributes --------------
# data    = dataframe containing fluxnet data for single sites
# lat     = latitude scalar for the site
# lon     = longitude scalar for the site
# timezone= 
#           the relative minimum threshold (e.g. 0.3 = 30%) to be excluded from the
#           range of the GPP data.

### Function -----------
calc_Rb <- function(
    data, timezone, site, year,
    SWfilt = NA, GPPfilt = 60, Rfilt = 30
    ) {
  
  ## Utilities ----
  require(dplyr)
  require(lubridate)
  # require(lutz)
  require(REddyProc)
  
  # calc_timezone_shift <- function(data = data, lat = lat, lon = lon) {
  #   print('Calculation of Time zone')
  #   now = as.POSIXct(data$DATETIME[1], tz = tz(data))
  #   nowthere = with_tz(now, tz = tz_lookup_coords(lat, lon, method = "accurate"))
  #   TimeZone_h.n <- hour(nowthere)-hour(now)
  #   return(TimeZone_h.n)
  # }
  
  ## Output by error ----
  err_output <- dplyr::tibble(Rb = NA_real_, Rbmax = NA_real_, E0 = NA_real_)
  
  
  ## Quote & settings ----
  if (rlang::is_empty(year)) {
    site_year <- paste0("site ", site)
  } else if (!rlang::is_empty(year)) {
    data <- data %>% dplyr::mutate(YEAR = lubridate::year(DATETIME), .before = everything()) # add year
    
    year <- data %>% dplyr::pull(YEAR) %>% unique()
    site_year <- paste0("site-year ", site, "-", year)
  }
  
  lat = unique(data$LATITUDE)
  lon = unique(data$LONGITUDE)
  
  
  
  ### Processing ----
  print(glue::glue("..computing respiration parameters (Rb, Rbmax, E0) for {site_year}."))
  
  
  # ## Daylight (+ Friction Velocity filter)
  # # replace with NA instead of filtering to preserve full timeseries for REddyProc functions
  # data <- data %>%
  #   mutate(
  #     across(
  #       .cols = !DATETIME, .fns = if_else(
  #       condition = SW_IN > SWfilt,
  #       true = .x,
  #       false = NA
  #       )
  #     )
  #   )
  
  
  ## Subset for calculations and omit NAs ----
  data_subset <- data %>% 
    dplyr::select(DATETIME, GPP, NEE, NEE_QC, SW_IN, SW_IN_QC, TA, TA_QC) #%>% 
    # tidyr::drop_na()
  
  
  ## Pre-processing ----
  data_subset <- data_subset %>% 
    mutate(
      DATETIME = as.POSIXct(DATETIME) + 30 * 30 # make sure class is POSIX datetime and center on half-hour
      # timezone = calc_timezone_shift(LATITUDE, LONGITUDE)
      ) %>% 
    rename(DateTime = DATETIME)
  
  EddyProc.C <- sEddyProc$new(
    site, data_subset, c('NEE', 'NEE_QC', 'SW_IN', 'SW_IN_QC', 'TA', 'TA_QC'),
    LatDeg = as.numeric(lat), LongDeg = as.numeric(lon), TimeZoneHour = 0
    )
  
  
  ## Run the MR Partitioning ----
  # Also applies quality filtering: NB) only provided value! (https://github.com/EarthyScience/REddyProc/blob/ce598d94a0cbfa024fbb36e3b438b1bb9f27fe6a/R/DataFunctions.R#L604)
  EddyProc.C$sMRFluxPartition(
    FluxVar = "NEE", QFFluxVar = "NEE_QC",
    QFFluxValue = 0, TempVar = "TA", QFTempVar = "TA_QC",
    QFTempValue = 0, RadVar = "SW_IN", TRef = 273.15 + 15,
    suffix = ""
    )
  
  
  # Filter out Rb outliers above threshold (Rfilt)
  EddyProc.C$sTEMP$R_ref[EddyProc.C$sTEMP$R_ref > Rfilt] <- NA_real_
  
  
  ## Calculate metrics ----
  Rb_out <- tibble(
    Rb = mean(EddyProc.C$sTEMP$R_ref[data_subset$GPP < GPPfilt], na.rm = T), # mean basal respiration, filtered 
    Rbmax = quantile(EddyProc.C$sTEMP$R_ref[data_subset$GPP < GPPfilt], 0.95, na.rm = T), # maximum basal respiration
    E0 = mean(EddyProc.C$sTEMP$E_0[data_subset$GPP < GPPfilt], na.rm = T) # activation energy (inverse of temperature sensitivity)
  )
  
  
  ## Output ----
  return(Rb_out)
}


# ### Debug --------------
# debugonce(calc_Rb)
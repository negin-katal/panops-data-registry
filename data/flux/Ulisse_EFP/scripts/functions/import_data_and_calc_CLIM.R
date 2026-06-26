#### EXTRACT CLIMATE

### Author: Ulisse Gomarasca

### Function -------------------------------------------------------------------
import_data_and_calc_CLIM <- function(
    site_list = list("AR-SLu", "AT-Neu", "AU-Cpr"),
    path = "//minerva/BGI/scratch/jnelson/4Sinikka/data20240123/", path2 = "//minerva/BGI/work_1/scratch/fluxcom/sitecube_proc/model_files/",
    future_env = list(savedata, eval_file, grouping_var, rand_sites, QCfilt),
    plotting = F
) {
  
  
  ### Utilities ----------------------------------------------------------------
  require(dplyr)      # tidy data manipulation
  require(lubridate)
  require(ncdf4)
  # library(purrr)      # map functions
  library(REddyProc)  # eddy covariance functions
  library(rlang)      # quoting inside functions
  require(stringr)    # string manipulation
  require(tidyr)      # clean and reshape tidy data
  
  
  
  ### Function inputs ----------------------------------------------------------
  site <- unlist(site_list)       # site of interest (parallized, also works for testing)
  
  savedata <- future_env[[1]]     # save or not
  eval_file <- future_env[[2]]    # evaluation file
  grouping_var <- future_env[[3]] # calculate by year or for full site timeseries
  rand_sites <- future_env[[4]]   # calculate by year or for full site timeseries
  
  QCfilt <- future_env[[5]]       # quality filter
  
  
  # Initialize txt vector for evaluation
  txt_vector <- c()
  
  
  
  ## Output by errors ----
  err_output <- tibble(
    SITE_ID = site, Precip = NA_real_, Temp = NA_real_, SWin = NA_real_, VPD = NA_real_,
    AWCh1 = NA_real_, AWCh2 = NA_real_, AWCh3 = NA_real_, CLAY = NA_real_, ORCDRC = NA_real_, PHIHOX = NA_real_, SAND = NA_real_, SILT = NA_real_
  ) # output when error is encountered
  
  
  
  ### Import data --------------------------------------------------------------
  ## Import data for the current site
  txt <- glue::glue("++++++++++++++++++++++++++++ Site {site} ++++++++++++++++++++++++++++"); print(txt); txt_vector <- c(txt_vector, txt)
  txt <- glue::glue("....Importing data for site {site}."); print(txt); txt_vector <- c(txt_vector, txt)
  
  ## Fluxes
  nc_fluxes <- tryCatch({
    ncdf4::nc_open(filename = glue::glue("{path}{site}.nc")) # fluxes
  }, error = function(err) {
    return(NA)
  })
  if (typeof(nc_fluxes) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the import of flux data for site {site}. Skipping current site."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    return(err_output)
    rlang::interrupt()
  }
  
  nc_fluxes2 <- tryCatch({
    ncdf4::nc_open(filename = glue::glue("{path2}{site}_meteo.nc"))
  }, error = function(err) {
    return(NA)
  })
  if (typeof(nc_fluxes2) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the import of flux data2 for site {site}. Skipping current site."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    return(err_output)
    rlang::interrupt()
  }
  
  # ## Remote sensing
  # # Incl. e.g. LAI and NIRv
  # nc_rs <- tryCatch({
  #  # remote sensing data
  # }, error = function(err) {
  #   return(NA)
  # })
  # if (typeof(nc_rs) == "logical") { # condition to exit computations for current site
  #   txt <- glue::glue("!=> Error in the import of remote sensing data for site {site}. Skipping current site."); warning(txt); txt_vector <- c(txt_vector, txt)
  #   if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
  #   
  #   return(err_output)
  #   rlang::interrupt()
  # }
  
  # Origin for time dimension
  timestart_fluxes <- stringr::str_extract(nc_fluxes[["dim"]][["time"]][["units"]], "[:digit:]{4}-[:digit:]{2}-[:digit:]{2} [:digit:]{2}:[:digit:]{2}:[:digit:]{2}")
  timestart_fluxes2 <- stringr::str_extract(nc_fluxes2[["dim"]][["time"]][["units"]], "[:digit:]{4}-[:digit:]{2}-[:digit:]{2} [:digit:]{2}:[:digit:]{2}:[:digit:]{2}")
  
  
  ## Extract variables ----
  dat <- tryCatch({
    tibble(
      ## Site:
      SITE_ID = site,
      ## Time:
      TIME = nc_fluxes$dim$time$vals, # time dimension (minutes since YYYY-MM-DD 00:00:00)
      ## Coordinates:
      LATITUDE = ncdf4::ncvar_get(nc_fluxes, varid = "tower_lat"),  # latitude (degrees north)
      LONGITUDE = ncdf4::ncvar_get(nc_fluxes, varid = "tower_lon"), # latitude (degrees east)
      ## Meteo with quality flags:
      NETRAD = ncdf4::ncvar_get(nc_fluxes, varid = "NETRAD"),       # net surface radiation (W m-2)
      NETRAD_QC = ncdf4::ncvar_get(nc_fluxes, varid = "NETRAD_QC"), # net radiation quality flag
      # LW_IN = ncdf4::ncvar_get(nc_fluxes, varid = "LW_IN"),         # downward long-wave radiation (W m-2)
      # LW_IN_QC = ncdf4::ncvar_get(nc_fluxes, varid = "LW_IN_QC"),   # downward long-wave radiation quality flag
      Precip = ncdf4::ncvar_get(nc_fluxes, varid = "P"),            # precipitation rate (mm h-1)
      Precip_QC = ncdf4::ncvar_get(nc_fluxes, varid = "P_QC"),      # precipitation rate quality flag
      PA = ncdf4::ncvar_get(nc_fluxes, varid = "PA"),               # surface pressure (Pa)
      PA_QC = ncdf4::ncvar_get(nc_fluxes, varid = "PA_QC"),         # surface pressure quality flag
      # RH = ncdf4::ncvar_get(nc_fluxes, varid = "RH"),               # relative humidity (%)
      # RH_QC = ncdf4::ncvar_get(nc_fluxes, varid = "RH_QC"),         # relative humidity quality flag
      SW_IN = ncdf4::ncvar_get(nc_fluxes, varid = "SW_IN"),         # downward short-wave radiation (W m-2)
      SW_IN_QC = ncdf4::ncvar_get(nc_fluxes, varid = "SW_IN_QC"),   # downward short-wave radiation quality flag
      TA = ncdf4::ncvar_get(nc_fluxes, varid = "TA"),               # near surface air temperature (K)
      TA_QC = ncdf4::ncvar_get(nc_fluxes, varid = "TA_QC"),         # near-surface air temperature quality flag
      USTAR = ncdf4::ncvar_get(nc_fluxes, varid = "USTAR"),         # friction velocity (m s-1)
      USTAR_QC = ncdf4::ncvar_get(nc_fluxes, varid = "USTAR_QC"),   # friction velocity quality flag
      VPD = ncdf4::ncvar_get(nc_fluxes, varid = "VPD"),             # vapor pressure deficit (hPa)
      VPD_QC = ncdf4::ncvar_get(nc_fluxes, varid = "VPD_QC"),       # vapor pressure deficit quality flag
      WS = ncdf4::ncvar_get(nc_fluxes, varid = "WS"),               # near surface wind speed (m s-1)
      WS_QC = ncdf4::ncvar_get(nc_fluxes, varid = "WS_QC"),          # near surface wind speed quality flag
    ) %>%
      mutate(across(.cols = everything(), .fns = as.vector)) %>% # convert every column type (array) to vector
      mutate(across(.cols = where(is.double), .fns = ~ if_else(condition = is.nan(.x), true = NA_real_, false = .x))) %>% # convert NaN to NA
      mutate(TIME = TIME * 60, # convert time from 'minutes from' to 'seconds from'
             DATETIME = lubridate::as_datetime(TIME, origin = timestart_fluxes), # generate date column from correct start for each site
             .after = SITE_ID
      ) %>% 
      dplyr::left_join( # import missing variables from different file location
        tibble(
          SITE_ID = site,
          TIME = nc_fluxes2$dim$time$vals,                               # time dimension (minutes since YYYY-MM-DD 00:00:00)
          IGBP = ncdf4::ncvar_get(nc_fluxes2, varid = "IGBP_veg_short"), # IGBP plant functional type classification
          ## Meteo
          RH = ncdf4::ncvar_get(nc_fluxes2, varid = "RH"),                  # relative humidity (%)
          # RH_QC = ncdf4::ncvar_get(nc_fluxes, varid = "RH_QC"),             # relative humidity quality flag
          # CO2air = ncdf4::ncvar_get(nc_fluxes2, varid = "CO2air") * 1e+06,  # Near surface CO2 concentration [mol mol-1 --> ppm]
          # CO2air_QC = ncdf4::ncvar_get(nc_fluxes2, varid = "CO2air_qc"),    # Near surface CO2 concentration quality flag
          ## Soil information
          AWCh1 = ncdf4::ncvar_get(nc_fluxes2, varid = "AWCh1"),            # Available soil water capacity (volumetric fraction) for h1
          AWCh2 = ncdf4::ncvar_get(nc_fluxes2, varid = "AWCh2"),            # Available soil water capacity (volumetric fraction) for h2
          AWCh3 = ncdf4::ncvar_get(nc_fluxes2, varid = "AWCh3"),            # Available soil water capacity (volumetric fraction) for h3
          # BLDFIE = ncdf4::ncvar_get(nc_fluxes2, varid = "BLDFIE"),          # Bulk density (fine earth) in kg / cubic-meter
          # CECSOL = ncdf4::ncvar_get(nc_fluxes2, varid = "CECSOL"),          # Cation exchange capacity of soil in cmolc/kg
          # CRFVOL = ncdf4::ncvar_get(nc_fluxes2, varid = "CRFVOL"),          # Coarse fragments volumetric in %
          CLAY = ncdf4::ncvar_get(nc_fluxes2, varid = "CLYPPT") / 100,      # Clay content [0-1]
          SAND = ncdf4::ncvar_get(nc_fluxes2, varid = "SLTPPT") / 100,      # Sand content [0-1]
          SILT = ncdf4::ncvar_get(nc_fluxes2, varid = "SNDPPT") / 100,      # Silt content [0-1]
          ORCDRC = ncdf4::ncvar_get(nc_fluxes2, varid = "ORCDRC"),          # Soil organic carbon content (fine earth fraction) [g kg-1]
          PHIHOX = ncdf4::ncvar_get(nc_fluxes2, varid = "PHIHOX"),          # Soil pH x 10 in H2O
          # PHIKCL = ncdf4::ncvar_get(nc_fluxes2, varid = "PHIKCL"),          # Soil pH x 10 in KCl
          # WWP = ncdf4::ncvar_get(nc_fluxes2, varid = "WWP")                 # Available soil water capacity (volumetric fraction) until wilting point
        ) %>%
          mutate(across(.cols = everything(), .fns = as.vector)) %>% # convert every column type (array) to vector
          mutate(across(.cols = where(is.double), .fns = ~ if_else(condition = is.nan(.x), true = NA_real_, false = .x))) %>% # convert NaN to NA
          mutate(TIME = TIME * 60, DATETIME = as_datetime(TIME, origin = timestart_fluxes2)) %>% # generate date column from correct start for each site
          dplyr::select(-TIME), # remove time for to-be-joined tibble to avoid confusion
        by = c("SITE_ID", "DATETIME")
      ) %>% dplyr::relocate(IGBP, .after = LONGITUDE) %>% dplyr::relocate(RH, .after = PA_QC)
    
  }, error = function(err) {
    return(NA)
  })
  if (typeof(dat) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the extraction of variables for site {site}. Skipping current site."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    return(err_output)
    rlang::interrupt()
  }
  
  ## Check empty data
  if (nrow(dat) == 0) {
    txt <- glue::glue("!=> No valid data available for site {site}. Skipping current site.")
    print(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    return(err_output)
    rlang::interrupt()
  }
  
  
  ## Convert units ----
  txt <- glue::glue("....Converting units for site {site}."); print(txt); txt_vector <- c(txt_vector, txt)
  
  dat <- tryCatch({dat %>%
      dplyr::mutate(VPD_kPa = VPD / 10, .after = VPD) %>% # convert units of VPD from [hPa] to [kPa]
      dplyr::mutate(
        TA = dplyr::if_else(TA < -150, true = TA + 273.15, false = TA), # from [K] to [°C], if necessary
        Precip = Precip / 60^2 # from [mm h-1] to [mm s-1]
      )
  }, error = function(err) {
    return(NA)
  })
  if (typeof(dat) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the units conversion for {site}. Skipping current site."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    return(err_output)
    rlang::interrupt()
  }
  
  
  
  ## Calculate missing variables ----
  txt <- glue::glue("....Calculating missing variables for site {site}."); print(txt); txt_vector <- c(txt_vector, txt)
  
  dat <- tryCatch({dat %>%
      ## Time:
      dplyr::mutate(YEAR = year(DATETIME),
                    DOY = yday(DATETIME),
                    HOUR_decimal = (hour(DATETIME) * 60 + minute(DATETIME) + second(DATETIME)) / 60, # extract hours, minutes & seconds, and convert to decimal hour
                    .after = DATETIME
      ) %>%
      ## Climate:
      dplyr::mutate(PAR = SW_IN * 2.11, # calculation of PAR [umol m^-2 s^-1] from SW_IN [W m^-2]
                    PPFD = SW_IN * 2.11, # photosynthetic photon flux density (PPFD) calculated as SW_IN * 2.11
                    SW_IN_POT = fCalcPotRadiation(DoY = DOY, Hour = HOUR_decimal,
                                                  LatDeg = LATITUDE, LongDeg = LONGITUDE, TimeZone = 0) # Timezone is UTC for all sites for the NEON-NCAR product (0)
      )
    
  }, error = function(err) {
    return(NA)
  })
  if (typeof(dat) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the calculation of missing variables for {site}. Skipping current site."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    return(err_output)
    rlang::interrupt()
  }
  
  
  
  ### Plot variable timeseries -------------------------------------------------
  if (plotting & site %in% rand_sites) {
    if (savedata) {savepath <- "results/timeseries"} else {savepath <- NA}
    
    # dat %>% plot_timeseries(y = "LW_IN", color = "LW_IN_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "NETRAD", color = "NETRAD_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "PA", color = "PA_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "Precip", color = "Precip_QC", site = site, savepath = savepath)
    # dat %>% plot_timeseries(y = "RH", color = "RH_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "SW_IN", color = "SW_IN_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "SW_IN_POT", color = "SW_IN_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "TA", color = "TA_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "USTAR", color = "USTAR_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "VPD", color = "VPD_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "WS", color = "WS_QC", site = site, savepath = savepath)
  }
  
  
  
  ### Filtering ??? ------------------------------------------------------------
  
  
  
  
  ### Calculate mean climate (+ QC filter) -------------------------------------
  ## Announce computation
  if (rlang::is_empty(as.character(grouping_var))) {
    txt <- glue::glue("....Aggregating climatic variables for site {site}.")
    print(txt); txt_vector <- c(txt_vector, txt)
  } else if (!rlang::is_empty(as.character(grouping_var))) {
    txt <- glue::glue("....Aggregating climatic variables for each year for site {site}.")
    print(txt); txt_vector <- c(txt_vector, txt)
  }
  
  
  ## Calculate mean climatic variables on each site (and year if specified) ----
  ## Yearly aggregates
  dat_out <- dat %>% 
    dplyr::group_by(SITE_ID, YEAR) %>% # grouping variables for mapping (YEAR: always, otherwise cumulative precipitation is calculated over whole timeseries)
    dplyr::summarise( # calculate yearly means
      Precip = if_else(Precip_QC %in% QCfilt, Precip, NA_real_) %>% # filter quality
        sum(na.rm = T) * 60 * 30, # convert [mm/s] to cumulative [mm/half-hour]   # cumulative annual precipitation [mm/y]
      Temp = if_else(TA_QC %in% QCfilt, TA, NA_real_) %>% mean(na.rm = T),        # mean temperature [°C]
      SWin = if_else(SW_IN_QC %in% QCfilt, SW_IN, NA_real_) %>% mean(na.rm = T),  # mean incident shortwave radiation (incl. night time) [W/m^2]
      VPD = if_else(VPD_QC %in% QCfilt, VPD, NA_real_) %>% mean(na.rm = T),       # mean vapor pressure deficit [hPa]
      # CO2air = if_else(CO2air_QC %in% QCfilt, CO2air, NA_real_) %>% mean(na.rm = T), # mean CO2air
      dplyr::across(.cols = any_of(c("AWCh1", "AWCh2", "AWCh3", "AWCtS", "BLDFIE", "CECSOL", "CLAY",
                                   "CRFVOL", "ORCDRC", "PHIHOX", "PHIKCL", "SAND", "SILT", "WWP")
                                   ),
                    .fns = ~ mean(.x, na.rm = T) # average any other variable potentially present (but without QC flag)
                    ),
      .groups = "drop"
    )
    
  
  ## Site aggregates
  if (rlang::is_empty(as.character(grouping_var))) { # unless already calculated at the previous step (when calculations are done for full sites)
    dat_out <- dat_out %>% 
      dplyr::select(-YEAR) %>% 
      dplyr::group_by(SITE_ID) %>% 
      dplyr::summarise( # mean of annual values
        dplyr::across(.cols = where(is.double), .fns = ~ mean(.x, na.rm = T))
        # Precip = mean(Precip, na.rm = T),
        # Temp = mean(Temp, na.rm = T),
        # SWin = mean(SWin, na.rm = T),
        # VPD = mean(VPD, na.rm = T)
      )
  }
  
  ## Clean output
  dat_out <- dat_out %>% 
    dplyr::mutate(dplyr::across(.cols = dplyr::where(is.double),
                         .fns = ~ dplyr::if_else(condition = is.nan(.x), true = NA_real_, false = .x))
                  ) # convert NaN to NA
  
  
  
  ### Clean memory -------------------------------------------------------------
  nc_close(nc_fluxes); nc_close(nc_fluxes2) # close netcdf files
  rm(nc_fluxes, nc_fluxes2, timestart_fluxes, timestart_fluxes2, dat)
  gc() # clean memory usage
  
  
  
  ### Output -------------------------------------------------------------------
  txt <- glue::glue("==> Climate aggregations performed correctly for site {site}.")
  print(txt); txt_vector <- c(txt_vector, txt)
  if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
  
  
  return(dat_out)
  
  
  
}



# ### Debug ----------------------------------------------------------------------
# debugonce(import_data_and_calc_CLIM)
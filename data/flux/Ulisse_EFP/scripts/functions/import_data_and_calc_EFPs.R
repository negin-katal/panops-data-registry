### Function -------------------------------------------------------------------
import_data_and_calc_EFPs <- function(
    site_list = list("AR-SLu", "AT-Neu", "AU-Cpr"),
    path_fluxes = "//minerva/BGI/scratch/jnelson/4Sinikka/data20240123/", path_meteo = "//minerva/BGI/work_1/scratch/fluxcom/sitecube_proc/model_files/",
    future_env = list(savedata, eval_file, grouping_var, rand_sites, QCfilt, GSfilt, Pfilt, Pfilt_time, SWfilt, USfilt, GPPsatfilt, Rfilt, min_years = 5, min_months = 3),
    plotting = F
) {
  
  
  ### Utilities ----------------------------------------------------------------
  ## Functions
  source("scripts/functions/calc_CUEeco.R")
  source("scripts/functions/calc_EF.R")
  source("scripts/functions/calc_GPPsat_NEPmax.R")
  source("scripts/functions/calc_Gsmax.R")
  source("scripts/functions/calc_Rb.R")
  source("scripts/functions/calc_WUE.R")
  # source("scripts/functions/calc_WUEt.R")
  source("scripts/functions/find_mode.R")
  source("scripts/functions/safe_load_packages.R")
  
  ## Packages
  required_packages <- c(
    "dplyr",        # tidy data manipulation
    "lubridate",    # dates manipulation
    "ncdf4",        # netcdf files
    "stringr",      # tidy string manipulation
    "tidyr"         # clean and reshape tidy data
  )
  safe_load_packages(required_packages)
  
  
  
  ### Function inputs ----------------------------------------------------------
  site <- unlist(site_list)       # site of interest (parallized, also works for testing)
  
  savedata <- future_env[[1]]     # save or not
  eval_file <- future_env[[2]]    # evaluation file
  grouping_var <- future_env[[3]] # calculate by year or for full site timeseries
  rand_sites <- future_env[[4]]   # plots for random subset of sites
  
  QCfilt <- future_env[[5]]       # quality filter
  GSfilt <- future_env[[6]]       # growing season
  Pfilt  <- future_env[[7]]       # precipitation filter
  Pfilt_time <- future_env[[8]]   # period to exclude after precipitation events (hours)
  SWfilt <- future_env[[9]]       # radiation filter (daytime)
  USfilt <- future_env[[10]]      # u* filter
  GPPsatfilt <- future_env[[11]]  # filter for GPPsat outliers
  Rfilt <- future_env[[12]]       # filter for respiration outliers
  min_years <- future_env[[13]]   # minimum number of years EFP calculations
  min_months <- future_env[[14]]  # minimum number of months in a site-year (used to calculated min. half-hourly entries)
  
  
  
  # Initialize txt vector for evaluation
  txt_vector <- c()
  
  
  
  ## Output by errors ----
  efps_nofilt <- c("Rb", "Rbmax", "E0")
  efps_qc_gs <- c("GPPsat", "LUE", "NEP95", "NEP99")
  efps_qc_gs_precip <- c("CUEeco90", "CUEpval90", "Gsmax", "EFampl", "EF", "uWUE", "WUE")
  
  err_output <- tibble( # output when error is encountered
    SITE_ID = site,
    CUEeco90 = NA_real_, CUEpval90 = NA_real_, Rb = NA_real_, Rbmax = NA_real_, E0 = NA_real_,
    GPPsat = NA_real_, LUE = NA_real_, NEP95 = NA_real_, NEP99 = NA_real_,
    Gsmax = NA_real_,
    EFampl = NA_real_, EF = NA_real_,
    uWUE = NA_real_, WUE = NA_real_
  ) %>% 
    dplyr::select(SITE_ID, sort(names(.))) # reorder: SITE, (YEAR), then EFPs alphabetically sorted
  
  if (!rlang::is_empty(as.character(grouping_var))) { # add YEAR column if necessary
    err_output <- bind_cols(err_output, tibble(YEAR = NA_real_)) %>% dplyr::relocate(YEAR, .after = SITE_ID)
  }
  
  
  ### Import data --------------------------------------------------------------
  ## Import data for the current site
  txt <- glue::glue("++++++++++++++++++++++++++++ Site {site} ++++++++++++++++++++++++++++"); print(txt); txt_vector <- c(txt_vector, txt)
  txt <- glue::glue("....Importing data for site {site}."); print(txt); txt_vector <- c(txt_vector, txt)
  
  ## Fluxes
  nc_fluxes <- tryCatch({
    ncdf4::nc_open(filename = glue::glue("{path_fluxes}{site}.nc")) # fluxes
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
    ncdf4::nc_open(filename = glue::glue("{path_meteo}{site}_meteo.nc"))
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
  # nc_rs <- tryCatch({
  # ncdf4::nc_open(filename = glue::glue("{path_meteo}{site}_rs.nc")) # remote sensing data
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
      ## Fluxes with quality flags:
      NEE = ncdf4::ncvar_get(nc_fluxes, varid = "NEE"),             # net ecosystem exchange (µmol m-2 s-1)
      NEE_QC = ncdf4::ncvar_get(nc_fluxes, varid = "NEE_QC"),       # net ecosystem exchange quality flag
      GPP = ncdf4::ncvar_get(nc_fluxes, varid = "GPP_NT"),          # gross primary productivity (µmol m-2 s-1)
      # GPP_QC = ncdf4::ncvar_get(nc_fluxes, varid = "GPP_QC"),       # gross primary productivity quality flag
      RECO = ncdf4::ncvar_get(nc_fluxes, varid = "RECO_NT"),        # ecosystem respiration (µmol m-2 s-1)
      # RECO_QC = ncdf4::ncvar_get(nc_fluxes, varid = "RECO_NT_QC"),  # ecosystem respiration quality flag
      H = ncdf4::ncvar_get(nc_fluxes, varid = "H"),                 # sensible heat flux (W m-2)
      H_QC = ncdf4::ncvar_get(nc_fluxes, varid = "H_QC"),           # sensible heat flux quality flag
      LE = ncdf4::ncvar_get(nc_fluxes, varid = "LE"),               # latent heat flux (W m-2)
      LE_QC = ncdf4::ncvar_get(nc_fluxes, varid = "LE_QC"),         # latent heat flux quality flag
      # G = ncdf4::ncvar_get(nc_fluxes, varid = "G"),                 # ground heat flux (W m-2)
      # G_QC = ncdf4::ncvar_get(nc_fluxes, varid = "G_QC"),           # ground heat flux quality flag
      ## Meteo with quality flags:
      NETRAD = ncdf4::ncvar_get(nc_fluxes, varid = "NETRAD"),       # net surface radiation (W m-2)
      NETRAD_QC = ncdf4::ncvar_get(nc_fluxes, varid = "NETRAD_QC"), # net radiation quality flag
      # LW_IN = ncdf4::ncvar_get(nc_fluxes, varid = "LW_IN"),         # downward long-wave radiation (W m-2)
      # LW_IN_QC = ncdf4::ncvar_get(nc_fluxes, varid = "LW_IN_QC"),   # downward long-wave radiation quality flag
      Precip = ncdf4::ncvar_get(nc_fluxes, varid = "P"),            # precipitation (mm h-1)
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
      WS_QC = ncdf4::ncvar_get(nc_fluxes, varid = "WS_QC")          # near surface wind speed quality flag
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
          RH = ncdf4::ncvar_get(nc_fluxes2, varid = "RH"),               # relative humidity (%)
          # RH_QC = ncdf4::ncvar_get(nc_fluxes, varid = "RH_QC"),          # relative humidity quality flag
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
        # NEE = NEE * 1e+03 / 44.009 * 1e+06,   # from [kg m-2 s-1] to [µmol m-2 s-1] ==> # 1 kg = 1e+03 g;  1 g CO2 = 1/44.009 mol CO2;  1 mol = 1e+06 µmol
        # GPP = GPP * 1e+03 / 44.009 * 1e+06,   # from [kg m-2 s-1] to [µmol m-2 s-1]
        # RECO = RECO * 1e+03 / 44.009 * 1e+06, # from [kg m-2 s-1] to [µmol m-2 s-1]
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
      ## Fluxes:
      dplyr::mutate(ET = REddyProc::fCalcETfromLE(LE = LE, Tair = TA), # evapotranspiration [mmol H20 m-2 s-1]
      ) %>%
      ## Climate:
      dplyr::mutate(PAR = SW_IN * 2.11, # calculation of PAR [umol m^-2 s^-1] from SW_IN [W m^-2]
                    PPFD = SW_IN * 2.11, # photosynthetic photon flux density (PPFD) calculated as SW_IN * 2.11
                    SW_IN_POT = fCalcPotRadiation(DoY = DOY, Hour = HOUR_decimal,
                                                  LatDeg = LATITUDE, LongDeg = LONGITUDE, TimeZone = 0) # Timezone is UTC for all sites for the NEON-NCAR product (0)
      ) %>% 
      ## Quality flags:
      dplyr::mutate(GPP_QC = NEE_QC, RECO_QC = NEE_QC) %>% 
      ## Moving window
      dplyr::mutate(FiveDaySeq = rep(c(1:ceiling(n()/5)), each = 48 * 5, length.out = n()))
    
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
    
    dat %>% plot_timeseries(y = "ET", color = "LE_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "GPP", color = "GPP_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "H", color = "H_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "LE", color = "LE_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "NEE", color = "NEE_QC", site = site, savepath = savepath)
    dat %>% plot_timeseries(y = "RECO", color = "GPP_QC", site = site, savepath = savepath)
  }
  
  
  
  ### Filtering ----------------------------------------------------------------
  # QC, precip, GS, SW, U* filters moved separate to computations, but output is the same!
  
  ## Exclude cropland sites ----
  if (find_mode(unique(dat$IGBP)) %in% c("CRO", "CVM")) {
    txt <- glue::glue("....Excluding cropland sites. Site {site} was excluded."); print(txt); txt_vector <- c(txt_vector, txt)
    
    return(err_output)
    rlang::interrupt()
  }
  
  
  ## Minimum number of valid entries in groups (for single site-years) ----
  if (!rlang::is_empty(as.character(grouping_var))) {
    txt <- "....Excluding site-years with insufficient data (unfiltered)."; print(txt); txt_vector <- c(txt_vector, txt)
    
    dat <- dat %>% 
      dplyr::group_by(!!grouping_var) %>% # grouping variables for mapping
      dplyr::mutate(n_entries = n()) %>%
      dplyr::filter(n_entries > min_months * 30 * 24 * 2) %>% # exclude gappy site-years (timeseries covers less than X months): 3 months * 30 days * 24 hours * 2 half-hours = min 3 months of data per year
      dplyr::ungroup()
  }
  
  
  ## Quality only (Rb, E0) ----
  # No filtering is done because whole gap-filled timeseries is necessary during partitioning 
  
  
  ## Quality + Growing Season (GPPsat, NEPmax, LUE) ----
  txt <- "....Filtering data for GPPsat, NEPmax, LUE calculations."; print(txt); txt_vector <- c(txt_vector, txt)
  
  dat_qc_gs <- bigleaf::filter.data(
    data.frame(dat), quality.control = T, filter.growseas = T, filter.precip = F,
    GPP = "GPP", doy = "DOY", year = "YEAR", tGPP = GSfilt,
    precip = "Precip", tprecip = Pfilt, precip.hours = Pfilt_time, records.per.hour = 2,
    vars.qc = c("TA", "H", "LE", "NEE"), quality.ext = "_QC", good.quality = QCfilt) # missing "RH" QC filter

  
  ## Quality + Growing Season + Precipitation filter (CUEeco, EF, Gsmax, WUE) ----
  txt <- "....Filtering data for CUEeco, EF, EFampl, Gsmax, WUE, uWUE calculations."; print(txt); txt_vector <- c(txt_vector, txt)
  
  dat_qc_gs_precip <- bigleaf::filter.data(
    data.frame(dat), quality.control = T, filter.growseas = T, filter.precip = T,
    GPP = "GPP", doy = "DOY", year = "YEAR", tGPP = GSfilt,
    precip = "Precip", tprecip = Pfilt, precip.hours = Pfilt_time, records.per.hour = 2,
    vars.qc = c("TA", "H", "LE", "NEE"), quality.ext = "_QC", good.quality = QCfilt) # missing "RH" QC filter
  
  
  ## Drop empty rows ----
  dat <- dat %>% tidyr::drop_na(SITE_ID)
  dat_qc_gs <- dat_qc_gs %>% tidyr::drop_na(SITE_ID)
  dat_qc_gs_precip <- dat_qc_gs_precip %>% tidyr::drop_na(SITE_ID)
  
  
  ## Daylight (+ Friction Velocity filter) within single functions ----
  ### EFP calculation ----------------------------------------------------------
  ## Announce computation
  if (rlang::is_empty(as.character(grouping_var))) {
    txt <- glue::glue("....Computing EFPs for site {site}.")
    print(txt); txt_vector <- c(txt_vector, txt)
  } else if (!rlang::is_empty(as.character(grouping_var))) {
    txt <- glue::glue("....Computing EFPs for each site-year for site {site}.")
    print(txt); txt_vector <- c(txt_vector, txt)
  }
  
  
  ## Minimum number of years ----
  # if (rlang::is_empty(as.character(grouping_var))) { # uncomment to exclude only for case of full-site calculations
  if (dat %>% pull(YEAR) %>% unique() %>% length() < min_years) {
    txt <- glue::glue("....Excluding sites with insufficient years. Skipped Rb (etc.) calculations fo site {site}."); print(txt); txt_vector <- c(txt_vector, txt)
    
    dat <- tibble() # empty input to avoid further calculations and return NA output
  }
  
  if (dat_qc_gs %>% pull(YEAR) %>% unique() %>% length() < min_years) {
    txt <- glue::glue("....Excluding sites with insufficient years. Skipped GPPsat, NEPmax (etc.) calculations fo site {site}."); print(txt); txt_vector <- c(txt_vector, txt)
    
    dat_qc_gs <- tibble() # empty input to avoid further calculations and return NA output
  }
  
  if (dat_qc_gs_precip %>% pull(YEAR) %>% unique() %>% length() < min_years) {
    txt <- glue::glue("....Excluding sites with insufficient years. Skipped CUEeco, Gsmax, WUE (etc.) calculations fo site {site}."); print(txt); txt_vector <- c(txt_vector, txt)
    
    dat_qc_gs_precip <- tibble() # empty input to avoid further calculations and return NA output
  }
  # } # uncomment to exclude only for case of full-site calculations
  
  
  ## Calculate ----
  tic(glue::glue("Time to calculate EFPs for site {site}"))
  
  ## EFPs without any additional filtering ----
  # NB: whole gap-filled timeseries needed for partitioning! Which is why NO filtering is done in advance!
  if (nrow(dat) == 0) {
    dat_out_noFilt <- err_output %>% select(SITE_ID, !!grouping_var, any_of(efps_nofilt)) # set to NA
  } else {
    dat_out_noFilt <- tryCatch({dat %>% 
        dplyr::group_by(!!grouping_var) %>% # grouping variables for mapping
        tidyr::nest(data4EFPs = -c(SITE_ID, !!grouping_var)) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(
          ## Rb, Rbmax & E0
          Rbmetrics = purrr::map(
            .x = data4EFPs, .f = calc_Rb,
            site = site, year = as.character(grouping_var),
            SWfilt = SWfilt, GPPfilt = GPPsatfilt, Rfilt = Rfilt
          )
        ) %>%
        tidyr::unnest(cols = c(Rbmetrics)) %>% # extract variables; to keep empty outputs: 'keep_empty = T'
        dplyr::select(-data4EFPs) # remove input data
      
    }, error = function(err) {
      return(NA)
    })
  }
  if (typeof(dat_out_noFilt) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the Rb calculations for site {site}. Setting current EFPs to NA."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    dat_out_noFilt <- err_output %>% select(SITE_ID, !!grouping_var, any_of(efps_nofilt)) # set to NA
  }
  
  
  ## EFPs without precipitation filter ----
  if (nrow(dat_qc_gs) == 0) {
    dat_out_noPfilt <- err_output %>% select(SITE_ID, !!grouping_var, any_of(efps_qc_gs)) # set to NA
  } else {
    dat_out_noPfilt <- tryCatch({dat_qc_gs %>% 
        dplyr::group_by(!!grouping_var) %>% # grouping variables for mapping
        tidyr::nest(data4EFPs = -c(SITE_ID, !!grouping_var)) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(
          ## GPPsat, NEP95 & LUE
          LRCmetrics = purrr::map(
            .x = data4EFPs, .f = calc_GPPsat_NEPmax,
            site = site, year = as.character(grouping_var),
            SWfilt = SWfilt, GPPsatfilt = GPPsatfilt
          )
        ) %>%
        tidyr::unnest(cols = c(LRCmetrics)) %>% # extract variables; to keep empty outputs: 'keep_empty = T'
        dplyr::select(-data4EFPs) # remove input data
      
    }, error = function(err) {
      return(NA)
    })
  }
  if (typeof(dat_out_noPfilt) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the LRC calculations (GPPsat, or NEPmax) for site {site}. Setting current EFPs to NA."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    dat_out_noPfilt <- err_output %>% select(SITE_ID, !!grouping_var, any_of(efps_qc_gs)) # set to NA
  }
  
  ## EFPs with all filters ----
  if (nrow(dat_qc_gs_precip) == 0) {
    dat_out_allFilt <- err_output %>% select(SITE_ID, !!grouping_var, any_of(efps_qc_gs_precip)) # set to NA
  } else {
    dat_out_allFilt <- tryCatch({dat_qc_gs_precip %>% 
        dplyr::group_by(!!grouping_var) %>% # grouping variables for mapping
        tidyr::nest(data4EFPs = -c(SITE_ID, !!grouping_var)) %>%
        dplyr::ungroup() %>%
        dplyr::mutate(
          ## CUEeco
          CUEeco = purrr::map(
            .x = data4EFPs, .f = calc_CUEeco,
            site = site, year = as.character(grouping_var),
            qile = 0.9,
            SWfilt = SWfilt
          ),
          ## EF
          EFmetrics = purrr::map(
            .x = data4EFPs, .f = calc_EF,
            site = site, year = as.character(grouping_var),
            SWfilt = SWfilt * 4, USfilt = USfilt
          ),
          ## Gsmax
          Gsmax = purrr::map_dbl(
            .x = data4EFPs, .f = calc_Gsmax,
            site = site, year = as.character(grouping_var),
            SWfilt = SWfilt * 4, USfilt = USfilt
          ),
          ## WUE
          WUEmetrics = purrr::map(
            .x = data4EFPs, .f = calc_WUE,
            site = site, year = as.character(grouping_var),
            SWfilt = SWfilt * 4
          )
          # ## WUEt
          # # ......................................................................
        ) %>%
        tidyr::unnest(cols = c(CUEeco, EFmetrics, WUEmetrics)) %>% # extract variables; to keep empty outputs: 'keep_empty = T'
        dplyr::select(-data4EFPs) # remove input data
      
    }, error = function(err) {
      return(NA)
    })
  }
  if (typeof(dat_out_allFilt) == "logical") { # condition to exit computations for current site
    txt <- glue::glue("!=> Error in the Water-related EFPs calculations (CUEeco, Gsmax, or WUE...) for site {site}. Setting current EFPs to NA."); warning(txt); txt_vector <- c(txt_vector, txt)
    if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
    
    dat_out_allFilt <- err_output %>% select(SITE_ID, !!grouping_var, any_of(efps_qc_gs_precip)) # set to NA
  }
  
  toc()
  
  
  ## Combine output -----
  dat_out <- dat_out_noFilt %>%
    dplyr::left_join(dat_out_noPfilt, by = c("SITE_ID", as.character(grouping_var))) %>%
    dplyr::left_join(dat_out_allFilt, by = c("SITE_ID", as.character(grouping_var))) %>%
    dplyr::select(SITE_ID, !!grouping_var, sort(names(.))) # reorder: SITE, (YEAR), then EFPs alphabetically sorted
  
  if (sum(is.na(dat_out)) == length(dat_out) - 1) { # condition to return NA output when all calculations failed due to insufficient site-years
    txt <- glue::glue("....All calculations failed likely due to insufficient data. Site {site} was excluded."); print(txt); txt_vector <- c(txt_vector, txt)
    
    return(err_output)
    rlang::interrupt()
  }
  
  
  ### Clean memory -------------------------------------------------------------
  nc_close(nc_fluxes); nc_close(nc_fluxes2) # close netcdf files
  rm(nc_fluxes, nc_fluxes2, timestart_fluxes, timestart_fluxes2,
     dat, dat_out_noFilt, dat_out_noPfilt, dat_out_allFilt, dat_qc_gs, dat_qc_gs_precip)
  gc() # clean memory usage
  
  
  
  ### Output -------------------------------------------------------------------
  txt <- glue::glue("==> EFP calculations performed correctly for site {site}.")
  print(txt); txt_vector <- c(txt_vector, txt)
  if (savedata) {cat(paste0(txt_vector, "\n"), file = eval_file, append = T)} # print to evaluation file
  
  
  return(dat_out)
  
  
  
} # end of function



# ### Debugging ------------------------------------------------------------------
# debugonce(import_data_and_calc_EFPs)
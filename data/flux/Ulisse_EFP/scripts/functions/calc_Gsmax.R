### Function -------------------------------------------------------------------
calc_Gsmax <- function(
    data, site, year,
    SWfilt = 200, USfilt = 0.2
)
{
  
  
  ## Utilities ----
  require(bigleaf)
  require(dplyr)
  require(tidyr)
  
  
  ## Quote & settings ----
  if (rlang::is_empty(year)) {
    site_year <- paste0("site ", site)
  } else if (!rlang::is_empty(year)) {
    data <- data %>% dplyr::mutate(YEAR = lubridate::year(DATETIME), .before = everything()) # add year
    
    year <- data %>% dplyr::pull(YEAR) %>% unique()
    site_year <- paste0("site-year ", site, "-", year)
  }
  
  
  ### Processing ----
  print(glue::glue("..computing Gsmax for {site_year}."))
  
  
  
  ## Filtering ----
  ## Daylight (+ Friction Velocity filter)
  data <- data %>% dplyr::filter(SW_IN > SWfilt & USTAR > USfilt) # filter instead of replacing with NA (SWfilt should be 200 for water EFPs)
  
  # Using only measured data: removing NA for wind speed
  data <- data %>% tidyr::drop_na(WS)
  
  # Convert units if needed
  if (!"VPD_kPa" %in% names(data)) {data <- data %>% dplyr::mutate(VPD_kPa = VPD / 10)} # convert units of VPD from [hPa] to [kPa]
  
  
  ##  Subset for calculations and omit NAs ----
  data_subset <- data %>% 
    dplyr::select(DATETIME, TA, PA, WS, USTAR, H, VPD_kPa, NETRAD, LE) %>% 
    tidyr::drop_na()
  
  
  ## Calculate EFPs ----
  if (nrow(data_subset) == 0) { # if no data is available after filtering
    stop(glue::glue("The {site_year} was skipped because of empty data."))
    output <- NA_real_
    
    
  } else if (nrow(data_subset) != 0) { # if dataframe is not empty
    
    
    output <- data_subset %>%
      ## Calculate aerodynamic conductance
      mutate(Ga = aerodynamic.conductance(., Tair = TA, pressure = PA,
                                          wind = WS, ustar = USTAR, H = H, 
                                          Rb_model = "Thom_1972") %>% 
               pull(Ga_h),
             ## Calculate surface conductance
             Gs = surface.conductance(., Ga = Ga, Tair = TA, pressure = PA, Rn = NETRAD,
                                      G = NULL, S = NULL, VPD = VPD_kPa, LE = LE,  
                                      missing.G.as.NA = F, missing.S.as.NA = F)
      ) %>%
      unnest(Gs) %>%
      ## Other filters
      tidyr::drop_na(Gs_mol) %>%
      dplyr::filter(VPD_kPa > 0) %>%  # VPD filter
      ## Calculate Gsmax (by years if specified) (?)
      summarise(
        Gsmax = quantile(na.omit(Gs_ms), 0.90), # 90th Gsmax quantile
        .groups = "drop"
        ) %>% 
      pull()
  } # end condition of empty data
  
  
  ### Output ----
  return(output)
}



# ### Debug ----------------------------------------------------------------------
# debugonce(calc_Gsmax)
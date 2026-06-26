### Function -------------------------------------------------------------------
calc_GPPsat_NEPmax <- function(
    data, site, year,
    SWfilt = 50, GPPsatfilt = 60
)
{
  
  
  ## Utilities ----
  require(bigleaf)
  require(dplyr)
  require(purrr)
  require(rlang)
  require(tidyr)
  source("scripts/functions/myLRC.R")
  
  
  ## Output by error ----
  err_output <- dplyr::tibble(LUE = NA_real_, GPPsat = NA_real_, NEP95 = NA_real_, NEP99 = NA_real_)
  
  
  ## Quote & settings ----
  if (rlang::is_empty(year)) {
    site_year <- paste0("site ", site)
  } else if (!rlang::is_empty(year)) {
    data <- data %>% dplyr::mutate(YEAR = lubridate::year(DATETIME), .before = everything()) # add year
    
    year <- data %>% dplyr::pull(YEAR) %>% unique()
    site_year <- paste0("site-year ", site, "-", year)
  }
  
  
  ### Processing ----
  print(glue::glue("..computing LRC parameters (GPPsat, LUE, NEPmax) for {site_year}."))
  
  
  ## Filtering ----
  ## Daylight (+ Friction Velocity filter)
  data <- data %>% dplyr::filter(SW_IN > SWfilt) # filter instead of replacing with NA only for GPP (SWfilt should be 50 for GPPsat)
  
  
  ## Subset for calculations and omit NAs ----
  data_subset <- data %>% 
    dplyr::select(DATETIME, NEE, PPFD, RECO, FiveDaySeq) %>% 
    tidyr::drop_na()
  
  
  ## Calculate EFPs ----
  if (nrow(data_subset) == 0) { # if no data is available after filtering
    warning(glue::glue("The {site_year} was skipped because of empty data."))
    output <- err_output
    
    
  } else if (nrow(data_subset) != 0) { # if dataframe is not empty
    output <- data_subset %>% 
      dplyr::group_by(FiveDaySeq) %>% 
      tidyr::nest(data5days = c(DATETIME, NEE, PPFD, RECO)) %>% 
      dplyr::mutate(
        LRC = purrr::map(.x = data5days, .f = myLRC), # calculate GPPsat at 5 days windows
      ) %>% 
      dplyr::ungroup() %>% 
      tidyr::unnest(cols = c(LRC)) %>% 
      mutate(
        GPPsat = dplyr::if_else(GPPsat < GPPsatfilt, GPPsat, NA_real_), # remove outliers
      ) %>% 
      tidyr::unnest(cols = data5days) %>% 
      dplyr::mutate(NEP = -NEE) %>% # take opposite; additional daytime filter not necessary because already filtered: if_else(PPFD > SWfilt * 2 * 2.11, -NEE, NA_real_)) %>% # exclude night values for daily NEP (NB: stricter (x2) than for GPPsat! is this correct?)
      dplyr::summarise(
        LUE = mean(LUE, na.rm = T), # average slope of the light response curve (canopy light-use efficiency)
        GPPsat = quantile(GPPsat, 0.95, na.rm = T), # 95th GPPsat quantile (by years if selected)
        NEP95 = quantile(NEP, 0.95, na.rm = T), # 95th NEP quantile
        NEP99 = quantile(NEP, 0.99, na.rm = T) # 99th NEP quantile
      )
  }
  
  
  ### Output ---------
  return(output)
}


# ### Debug ----------------------------------------------------------------------
# debugonce(calc_GPPsat_NEPmax)
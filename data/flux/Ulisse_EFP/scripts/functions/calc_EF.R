#### Function for filtering, EF calculation (Mirco Migliavacca)
# reorganized and improved, added additional information in output (Ulisse Gomarasca)

### Arguments ----
# data    = dataframe containing fluxnet data for single sites
# site    = character, name of the site
# elevation = Scalar. Single value of altitude for the site
# SWfilt  = Value of minimum threshold for ShortWave filter, e.g. to exclude for
#           nighttime data below 20, 100 or 200.
# USfilt  = Value of minimum threshold for USTAR filter.


### Function ----
calc_EF <- function(
    data, site, year,
    SWfilt = 200, USfilt = 0.2)
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
  
  
  ### Processing -----------------------------
  print(glue::glue('....computing evaporative fraction parameters (EF, EFampl) for {site_year}.'))
  
  ## Filter data ----
  ## Daylight (+ Friction Velocity filter)
  data <- data %>% dplyr::filter(SW_IN > SWfilt & USTAR > USfilt) # filter instead of replacing with NA (SWfilt should be 200 for water EFPs)
  
  ## Using only measured data: removing NA for wind speed
  data <- data %>% tidyr::drop_na(WS)
  
  
  ## Subset for calculations and omit NAs ----
  data_subset <- data %>% 
    dplyr::select(DATETIME, LE, H) %>% 
    tidyr::drop_na()
  
  
  # ## Plot timeseries ----
  # # H
  # ndata <- aaa %>% dplyr::select(H) %>% tidyr::drop_na() %>% nrow()
  # p0 <- aaa %>% dplyr::mutate(H_QC = as.character(H_QC)) %>% ggplot(aes(DATETIME, H, color = H_QC)) +
  #   geom_point(size = 2, alpha = 0.75) +
  #   labs(title = glue::glue("H time series at site {SITEID[i]} ({ndata} datapoints).")) + theme_myclassic
  # if (savedata == T) {
  #   ggsave(glue::glue("/{SITEID[i]}_H_{vers_out}.jpg"), plot = p0, device = "jpeg", path = paste0(folder_path, "/results/plots/timeseries/fluxes_HH_values"), width = 508, height = 285.75, units = "mm", dpi = 150) # 1920 x  1080 px resolution (16:9)
  # }
  # # LE
  # ndata <- aaa %>% dplyr::select(H) %>% tidyr::drop_na() %>% nrow()
  # p0 <- aaa %>% dplyr::mutate(LE_QC = as.character(LE_QC)) %>% ggplot(aes(DATETIME, LE, color = LE_QC)) +
  #   geom_point(size = 2, alpha = 0.75) +
  #   labs(title = glue::glue("LE time series at site {SITEID[i]} ({ndata} datapoints).")) + theme_myclassic
  # if (savedata == T) {
  #   ggsave(glue::glue("/{SITEID[i]}_LE_{vers_out}.jpg"), plot = p0, device = "jpeg", path = paste0(folder_path, "/results/plots/timeseries/fluxes_HH_values"), width = 508, height = 285.75, units = "mm", dpi = 150) # 1920 x  1080 px resolution (16:9)
  # }
  # p0 <- NULL

  ## Calculation of metrics ----
  if (nrow(data_subset) == 0) { # if no data is available after filtering
    warning(glue::glue("The {site_year} was skipped because of empty data."))
    output <- tibble(
      EF = NA_real_,
      EFampl = NA_real_
    )
    
    
  } else if (nrow(data_subset) != 0) { # if dataframe is not empty
    output <- data_subset %>% 
      mutate(EF = LE / (LE + H)) %>% 
      drop_na() %>% # necessary for amplitude to compare same amount of data in both quantiles?
      summarise(
        EFampl = quantile(EF, 0.75, na.rm = TRUE) - quantile(EF, 0.25, na.rm = TRUE),
        EF = median(EF, na.rm = TRUE) # NB after EFampl otherwise overwriting EF values
      )
  }
  
  
  ### Output ----
  return(output)
}
# ### Debug ----
# debugonce(calc_EF)
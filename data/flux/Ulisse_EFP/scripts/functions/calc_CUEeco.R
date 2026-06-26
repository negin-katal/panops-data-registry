### Function -------------------------------------------------------------------
calc_CUEeco <- function(data, site, year,
                        qile = 0.5,
                        SWfilt = 50
)
{
  
  
  ## Utilities ----
  require(dplyr)
  require(purrr)
  require(quantreg) # quantile regression
  require(tidyr)
  
  
  ## Quote & settings ----
  if (rlang::is_empty(year)) {
    site_year <- paste0("site ", site)
  } else if (!rlang::is_empty(year)) {
    data <- data %>% dplyr::mutate(YEAR = lubridate::year(DATETIME), .before = everything()) # add year
    
    year <- data %>% dplyr::pull(YEAR) %>% unique()
    site_year <- paste0("site-year ", site, "-", year)
  }
  
  # generate variable names for CUEeco quantile estimates and p-values
  prob <- as.character(qile * 100) # convert to percentages
  names_vars <- c(paste0("CUEeco", prob), paste0("CUEpval", prob))
  
  
  ### Processing ----
  print(glue::glue("..computing CUEeco for {site_year}."))
  
  
  ## Filtering ----
  ## Daylight (+ Friction Velocity filter)
  data <- data %>% dplyr::filter(SW_IN > SWfilt) # filter instead of replacing with NA (SWfilt should be 200 for water EFPs)
  
  
  ## Subset for calculations and omit NAs ----
  data <- data %>% 
    dplyr::select(NEE, GPP) %>% 
    tidyr::drop_na() # important to remove NA for quantile regression
  
  
  ## Calculate EFPs ----
  if (nrow(data) == 0) { # if no data is available after filtering
    stop(glue::glue("The {site_year} was skipped because of empty data."))
    output <- tibble(
      varnames = names_vars,
      values = NA_real_
    ) %>% 
      pivot_wider(names_from = varnames, values_from = values)
    
    
  } else if (nrow(data) != 0) { # if dataframe is not empty
    # Calculate NEP
    data <- data %>% dplyr::mutate(NEP = -NEE)
    
    # Calculate CUEeco based on specified quantiles, and include p-values
    CUEmodel <- quantreg::rq(data, formula = NEP ~ GPP, tau = qile, method = "fn")
    # Explanation: NEP ~ GPP => NEP = b + a * GPP => assuming b ~ 0, a = NEP / GPP
    
    # Slope coefficients and P-values
    CUEsummary <- summary(CUEmodel, se = "nid") # summary of model with p-values
    if (length(qile) == 1) {
      CUEval <- CUEmodel$coefficients[2]
      CUEpval <- CUEsummary[["coefficients"]][2,4]
    } else if (length(qile) > 1) {
      CUEval <- CUEmodel$coefficients[2,]
      CUEpval <- map_dbl(CUEsummary, function(x){x$coefficients[2,4]})
    }
    
    # To implement pseudo R2, look at these sources:
    # quantreg::FAQ(pkg = "quantreg")
    # https://stat.ethz.ch/pipermail/r-help/2006-August/110386.html
    # https://stackoverflow.com/questions/19861194/extract-r2-from-quantile-regression-summary
    # https://stats.stackexchange.com/questions/129200/r-squared-in-quantile-regression
    # rho <- function(u, tau = qile) u * (tau - (u < 0))
    # R1 <- 1 - fit1$rho / fit0$rho
    
    
    # Combine into tibble
    output <- tibble(
      varnames = names_vars,
      values = c(CUEval, CUEpval) # extract slope coefficients and p-values
    ) %>%
      pivot_wider(names_from = varnames, values_from = values)
    
    ## Output ----
    return(output)
  } # end condition of empty data
}



# ### Debug ----------------------------------------------------------------------
# debugonce(calc_CUEeco)
#### CHECK IF REQUIRED PACKAGES WITHIN FUNCTION ARE INSTALLED AND OPTIONALLY INSTALL THEM

### Author: Ulisse Gomarasca with Bing's Copilot https://support.microsoft.com/en-gb/topic/how-bing-delivers-search-results-d18fc815-ac37-4723-bc67-9229ce3eb6a3


### Function -------------------------------------------------------------------
safe_load_packages <- function(pkgs) {
  # Identify missing packages
  missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  
  if (length(missing_pkgs) > 0) {
    message("The following packages are missing: ", paste(missing_pkgs, collapse = ", "))
    
    # Ask if user wants to install all at once
    answer_all <- readline(prompt = "Do you want to install ALL missing packages? [y/N]: ")
    
    if (tolower(answer_all) %in% c("y", "yes")) {
      install.packages(missing_pkgs)
    } else {
      # Ask individually
      for (pkg in missing_pkgs) {
        answer <- readline(prompt = sprintf("Do you want to install '%s'? [y/N]: ", pkg))
        if (tolower(answer) %in% c("y", "yes")) {
          install.packages(pkg)
        } else {
          stop(sprintf("Package '%s' is required but not installed. Aborting.", pkg), call. = FALSE)
        }
      }
    }
  }
  
  # Load all requested packages quietly
  for (pkg in pkgs) {
    suppressPackageStartupMessages(
      library(pkg, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)
    )
  }
}

# ### Examples -----------------------------------------------------------------
# # Example function using multiple packages
# my_analysis <- function(data) {
#   safe_load_packages(c("dplyr", "ggplot2"))
#   
#   data <- data %>%
#     dplyr::mutate(new_col = row_number())
#   
#   plot <- ggplot2::ggplot(data, ggplot2::aes(x = x, y = new_col)) +
#     ggplot2::geom_point()
#   
#   print(plot)
#   return(data)
# }
# 
# # Example usage
# df <- data.frame(x = 1:5)
# my_analysis(df)
#
#
#
# ### Debug --------------------------------------------------------------------
# debugonce(safe_load_packages)

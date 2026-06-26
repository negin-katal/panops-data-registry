plot_timeseries <- function(data = dat, x = "DATETIME", y = "GPP", color = NA, facet = NA,
                            site = "", savepath = NA) {
  ## Utilities ----
  require(dplyr)
  require(ggplot2)
  require(Hmisc)
  require(rlang)
  
  
  ## Quote ----
  x <- rlang::sym(x)
  y <- rlang::sym(y)
  
  if (site != "") {site <- paste0("_", site)} # when plotted per site specify naming for output
  
  
  ## Specifications ----
  my_theme <- ggplot2::theme(text = element_text(size = 16),
                             title = element_text(size = 16),
                             axis.title = element_text(size = 20),
                             axis.title.x = element_blank(), # remove empty space of xlab
                             axis.text = element_text(size = 14),
                             legend.title = element_text(size = 20),
                             legend.text = element_text(size = 16),
                             strip.text = element_text(size = 16),
                             strip.background = element_blank()
                             )
  
  ## Color option ----
  if (!is.na(color)) {
    color <- rlang::sym(color)
    
    ## Plot
    p0 <- data %>% 
      # dplyr::mutate("{color}" := as.factor(!!color)) %>% 
      ggplot2::ggplot(aes(x = !!x, y = !!y, color = !!color)) +
      ggplot2::geom_point(alpha = 0.5, shape = 20, size = 2, na.rm = T) +
      ggplot2::theme_bw() +
      my_theme +
      ggplot2::guides(color = guide_legend(override.aes = list(alpha = 1, size = 6))) +
      NULL
    
    # Color scale
    if (Hmisc::is.discrete(data %>% pull(!!color))) {
      p0 <- p0 + ggplot2::scale_colour_viridis_d(direction = -1)
    } else {
      p0 <- p0 + ggplot2::scale_colour_viridis_c(direction = -1)
    }
    
  } else {
    ## Plot
    p0 <- data %>% 
      ggplot2::ggplot(aes(x = !!x, y = !!y)) +
      ggplot2::geom_point(alpha = 0.5, shape = 20, size = 2, na.rm = T) +
      ggplot2::theme_bw() +
      my_theme +
      ggplot2::guides(color = guide_legend(override.aes = list(alpha = 1, size = 6))) +
      NULL
  }
  
  
  ## Facets option ----
  if (!is.na(facet)) {
    facet <- rlang::sym(facet)
    p0 <- p0 + ggplot2::facet_wrap(vars(!!facet))
    }
  
  
  ## Save ----
  if (!is.na(savepath)) {
    ggplot2::ggsave(filename = glue::glue("{as.character(y)}{site}.jpg"), plot = p0, device = "jpeg",
                    path = savepath, width = 508, height = 285.75, units = "mm", dpi = 150) # 1920 x  1080 px resolution (16:9)
  }
  
  ## Output ----
  return(p0)
}
# debugonce(plot_timeseries)
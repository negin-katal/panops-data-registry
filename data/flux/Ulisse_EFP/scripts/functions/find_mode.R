find_mode <- function(x, na.rm = T) {
  if (na.rm == T) { # remove NAs
    x <- x[!is.na(x)]
  }
  u <- unique(x)
  tab <- tabulate(match(x, u))
  u[tab == max(tab)]
}
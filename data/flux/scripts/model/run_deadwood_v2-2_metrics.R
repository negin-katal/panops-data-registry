library(reticulate)
library(dplyr)
library(stringr)

use_python("/home/nk1125/miniconda3/bin/python3", required = TRUE)
xr <- import("xarray", delay_load = FALSE)

zarr_dir  <- file.path("deadtree", "deadtrees_maps_v2-2")
zarr_paths <- list.files(zarr_dir, pattern = "_inference\\.zarr$", full.names = TRUE)
cat(sprintf("Found %d sites in v2-2\n", length(zarr_paths)))

get_site_id <- function(zpath) str_replace(basename(zpath), "_inference\\.zarr$", "")

buffer_radii <- c(100, 200, 300, 400, 500)

# Minimum tree cover to compute rate metrics (avoids noise in sparse sites)
TC_MIN    <- 10   # percentage points
# Hard threshold for "significant" pixel-level change (matches old v2 script)
THRESH_PP <- 20   # percentage points

all_results <- list()

for (zpath in zarr_paths) {

  site_id <- get_site_id(zpath)
  message("Processing ", site_id)

  ds   <- xr$open_zarr(zpath, consolidated = FALSE)
  years <- as.integer(py_to_r(ds[["time"]]$values))
  x    <- as.vector(py_to_r(ds[["x"]]$values))
  y    <- as.vector(py_to_r(ds[["y"]]$values))

  x0 <- mean(range(x))
  y0 <- mean(range(y))
  dist2 <- outer((y - y0)^2, (x - x0)^2, "+")   # [row, col] = [y, x]

  mask_list <- setNames(
    lapply(buffer_radii, function(r) dist2 <= r^2),
    paste0(buffer_radii, "m")
  )

  # uint8 → % (0-100)
  tc_arr <- array(as.numeric(py_to_r(ds[["forest"]]$values))   * (100 / 255),
                  dim = dim(py_to_r(ds[["forest"]]$values)))
  dw_arr <- array(as.numeric(py_to_r(ds[["deadwood"]]$values)) * (100 / 255),
                  dim = dim(py_to_r(ds[["deadwood"]]$values)))

  out_list <- vector("list", length(years))

  for (i in seq_along(years)) {

    tc_now <- tc_arr[i, , ]
    dw_now <- dw_arr[i, , ]

    row_out <- list(site_id = site_id, year = years[i])

    # Year-over-year delta arrays (only for i > 1)
    if (i > 1) {
      tc_prev <- tc_arr[i - 1, , ]
      dw_prev <- dw_arr[i - 1, , ]

      # Raw positive change in deadwood (new dead wood appearing)
      dw_gain_pp        <- pmax(dw_now - dw_prev, 0)
      # Thresholded: only count pixels where gain >= THRESH_PP pp
      dw_gain_pp_thresh <- ifelse(dw_now - dw_prev >= THRESH_PP, dw_now - dw_prev, 0)

      # Raw positive loss of tree cover (trees actually removed / fallen)
      tc_loss_pp        <- pmax(tc_prev - tc_now, 0)
      # Thresholded: only count pixels where loss >= THRESH_PP pp
      tc_loss_pp_thresh <- ifelse(tc_prev - tc_now >= THRESH_PP, tc_prev - tc_now, 0)
    }

    for (r in buffer_radii) {

      rlab <- paste0(r, "m")
      mask <- mask_list[[rlab]]

      # ── Group 1: Tree cover state ──────────────────────────────────────
      tc_mean  <- mean(tc_now[mask], na.rm = TRUE)
      dw_mean  <- mean(dw_now[mask], na.rm = TRUE)
      live_tc  <- tc_mean - dw_mean  # live tree cover (can be small)

      row_out[[paste0("tree_cover_mean_pct_",     rlab)]] <- tc_mean
      row_out[[paste0("deadwood_mean_pct_",        rlab)]] <- dw_mean
      row_out[[paste0("live_tree_cover_pct_",      rlab)]] <- live_tc

      # ── Group 2: Mortality stock ───────────────────────────────────────
      # Only compute when tree cover is substantial; otherwise NA
      mort_stock <- ifelse(
        tc_mean >= TC_MIN,
        pmin(dw_mean / tc_mean * 100, 100),   # cap at 100% (model noise)
        NA_real_
      )
      row_out[[paste0("mortality_stock_pct_",      rlab)]] <- mort_stock

      # ── Groups 3 & 4: Year-over-year metrics (NA for first year) ───────
      if (i == 1) {

        row_out[[paste0("new_deadwood_gain_pp_",               rlab)]] <- NA_real_
        row_out[[paste0("new_mortality_rate_pct_",             rlab)]] <- NA_real_
        row_out[[paste0("tree_loss_pp_",                       rlab)]] <- NA_real_
        row_out[[paste0("relative_tree_loss_pct_",             rlab)]] <- NA_real_
        row_out[[paste0("mortality_loss_severity_pct_",        rlab)]] <- NA_real_
        # thresholded versions
        row_out[[paste0("new_deadwood_gain_pp_thresh_",        rlab)]] <- NA_real_
        row_out[[paste0("new_mortality_rate_pct_thresh_",      rlab)]] <- NA_real_
        row_out[[paste0("tree_loss_pp_thresh_",                rlab)]] <- NA_real_
        row_out[[paste0("relative_tree_loss_pct_thresh_",      rlab)]] <- NA_real_
        row_out[[paste0("mortality_loss_severity_pct_thresh_", rlab)]] <- NA_real_

      } else {

        tc_prev_mean <- mean(tc_prev[mask], na.rm = TRUE)

        dg_mean        <- mean(dw_gain_pp[mask],        na.rm = TRUE)
        tl_mean        <- mean(tc_loss_pp[mask],        na.rm = TRUE)
        dg_mean_thresh <- mean(dw_gain_pp_thresh[mask], na.rm = TRUE)
        tl_mean_thresh <- mean(tc_loss_pp_thresh[mask], na.rm = TRUE)

        above_tc <- tc_prev_mean >= TC_MIN

        row_out[[paste0("new_deadwood_gain_pp_",               rlab)]] <- dg_mean
        row_out[[paste0("new_mortality_rate_pct_",             rlab)]] <- ifelse(above_tc, dg_mean / tc_prev_mean * 100, NA_real_)
        row_out[[paste0("tree_loss_pp_",                       rlab)]] <- tl_mean
        row_out[[paste0("relative_tree_loss_pct_",             rlab)]] <- ifelse(above_tc, tl_mean / tc_prev_mean * 100, NA_real_)
        row_out[[paste0("mortality_loss_severity_pct_",        rlab)]] <- ifelse(above_tc, (dg_mean + tl_mean) / tc_prev_mean * 100, NA_real_)
        # thresholded (>= THRESH_PP pp pixel-level change only)
        row_out[[paste0("new_deadwood_gain_pp_thresh_",        rlab)]] <- dg_mean_thresh
        row_out[[paste0("new_mortality_rate_pct_thresh_",      rlab)]] <- ifelse(above_tc, dg_mean_thresh / tc_prev_mean * 100, NA_real_)
        row_out[[paste0("tree_loss_pp_thresh_",                rlab)]] <- tl_mean_thresh
        row_out[[paste0("relative_tree_loss_pct_thresh_",      rlab)]] <- ifelse(above_tc, tl_mean_thresh / tc_prev_mean * 100, NA_real_)
        row_out[[paste0("mortality_loss_severity_pct_thresh_", rlab)]] <- ifelse(above_tc, (dg_mean_thresh + tl_mean_thresh) / tc_prev_mean * 100, NA_real_)
      }
    }  # end buffer loop

    out_list[[i]] <- as.data.frame(row_out, check.names = FALSE)
  }  # end year loop

  all_results[[site_id]] <- bind_rows(out_list)
}

final_df <- bind_rows(all_results)
cat(sprintf("\nTotal rows: %d  |  Sites: %d\n", nrow(final_df), length(unique(final_df$site_id))))

out_csv <- "derived_tables/final_disturbance_v2-2_multibuffer.csv"
write.csv(final_df, out_csv, row.names = FALSE)
cat("Saved:", out_csv, "\n")

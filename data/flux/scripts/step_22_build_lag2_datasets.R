#!/usr/bin/env Rscript
# ============================================================================
# Build the lag2-enabled 24-month datasets for tc>=30 and tc>=50.
#
# WHY: get_predictor_cols() selects the D block by name prefix, so the 24m
# models saw exactly the same disturbance columns as the 12m ones. In the
# all-sites data that means lag2 leaked INTO the 12m models; in the two
# tree-cover-filtered datasets it means lag2 was absent from BOTH. Neither
# matches the documented design (12m: current+lag1; 24m: current+lag1+lag2).
#
# SOURCES - current files only, no stale intermediates:
#   1. v10_rf_ready_with_traits.csv        the 184-site master (2026-07-17).
#      Verified to reproduce the shipped harmonized datasets EXACTLY:
#      0 of 447 shared numeric columns differ, all 395 / 287 site-years found.
#   2. final_disturbance_v2-2_multibuffer.csv   canonical disturbance, 2016-2025.
#      Used only to fill the 34 (tc>=30) / 22 (tc>=50) site-years where the
#      master's own lag2 is NA because the EFP table has year gaps. Verified
#      to reproduce every disturbance metric exactly (max |diff| ~5e-14).
#
# The 93 and 65 site lists are taken verbatim from the shipped datasets, so the
# site / site-year counts are unchanged: 93 / 395 and 65 / 287.
#
# Only B2 gains the lag2 columns (10 stock-metric columns; see note below).
# Only B2 gains the lag2 columns. B1 is copied through untouched, so the 12m
# models - which read B1 - are unaffected and need no code change.
# ============================================================================
suppressMessages(library(data.table))
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")
B <- "derived_tables/outputs_afterEGU_results"

master <- fread(file.path(B, "v10/v10_rf_ready_with_traits.csv"))
can    <- fread("derived_tables/final_disturbance_v2-2_multibuffer.csv")
setnames(can, c("site_id", "year"), c("SITE_ID", "YEAR"))

BUF <- c(100, 200, 300, 400, 500)
RESP <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")

# canonical value of one disturbance variable, for the given (SITE_ID, YEAR)
canon_value <- function(base, buf) {
  direct <- sub("_[0-9]+00m$", "", base)
  if (direct == "absolute_mortality")   return(can[[sprintf("deadwood_mean_pct_%dm",   buf)]])
  if (direct == "relative_mortality")   return(can[[sprintf("mortality_stock_pct_%dm", buf)]])
  if (direct == "relative_disturbance") {
    dw <- can[[sprintf("deadwood_mean_pct_%dm",   buf)]]
    tc <- can[[sprintf("tree_cover_mean_pct_%dm", buf)]]
    tl <- can[[sprintf("tree_loss_pp_%dm",        buf)]]
    return((dw + tl) / (tc + tl) * 100)
  }
  can[[base]]
}

build <- function(in_dir, in_prefix, out_dir, out_prefix, label) {
  cat("\n", strrep("=", 74), "\n", label, "\n", strrep("=", 74), "\n", sep = "")
  dir.create(file.path(B, out_dir), showWarnings = FALSE, recursive = TRUE)

  shp1 <- fread(sprintf("%s/%s/%s_B1_GPPsat_harmonized.csv", B, in_dir, in_prefix))
  sy   <- unique(shp1[, .(SITE_ID, YEAR)])
  cat(sprintf("site-years: %d   sites: %d\n", nrow(sy), uniqueN(sy$SITE_ID)))

  # STOCK-ONLY lag2 (decision 2026-09-08). Of the 11 disturbance families only
  # the two stock metrics have a complete lag2: every change-type metric
  # (new_deadwood_gain, new_mortality_rate, relative_tree_loss,
  # mortality_loss_severity, relative_disturbance) is undefined for site-years
  # whose lag2 lands on 2017, costing 34 site-years (tc>=30) and 22 (tc>=50).
  # Keeping only the stock metrics preserves 93/395 and 65/287 exactly, so the
  # new results stay comparable with every existing run.
  Dl2 <- grep("^(absolute_mortality|relative_mortality)_[0-9]+00m_lag2$",
              names(master), value = TRUE)
  stopifnot(length(Dl2) == 10)

  lag2 <- merge(sy, master[, c("SITE_ID", "YEAR", Dl2), with = FALSE],
                by = c("SITE_ID", "YEAR"), all.x = TRUE)
  n_na_before <- sum(!complete.cases(lag2[, ..Dl2]))

  # fill from the canonical table at YEAR-2, and verify it agrees where master has values
  can_l2 <- copy(can)[, YEAR := YEAR + 2]          # so YEAR now indexes the TARGET year
  mismatch <- 0L; filled <- 0L
  for (v in Dl2) {
    base <- sub("_lag2$", "", v)
    buf  <- as.integer(sub(".*_([0-9]+)00m$", "\\1", base)) * 100
    ref  <- data.table(SITE_ID = can_l2$SITE_ID, YEAR = can_l2$YEAR, val = canon_value(base, buf))
    ref  <- ref[is.finite(val)]
    idx  <- match(paste(lag2$SITE_ID, lag2$YEAR), paste(ref$SITE_ID, ref$YEAR))
    newv <- ref$val[idx]
    both <- !is.na(lag2[[v]]) & !is.na(newv)
    mismatch <- mismatch + sum(abs(lag2[[v]][both] - newv[both]) > 1e-6)
    fill <- is.na(lag2[[v]]) & !is.na(newv)
    filled <- filled + sum(fill)
    set(lag2, which(fill), v, newv[fill])
  }
  cat(sprintf("lag2: rows with NA before fill = %d | values filled from canonical = %d\n",
              n_na_before, filled))
  cat(sprintf("      canonical vs master disagreements where both present: %d (must be 0)\n", mismatch))
  stopifnot(mismatch == 0)
  n_na_after <- sum(!complete.cases(lag2[, ..Dl2]))
  cat(sprintf("      rows with any NA after fill = %d (must be 0)\n", n_na_after))
  stopifnot(n_na_after == 0)

  for (r in RESP) {
    b1 <- fread(sprintf("%s/%s/%s_B1_%s_harmonized.csv", B, in_dir, in_prefix, r))
    b2 <- fread(sprintf("%s/%s/%s_B2_%s_harmonized.csv", B, in_dir, in_prefix, r))
    n1 <- nrow(b1); n2 <- nrow(b2)
    b2new <- merge(b2, lag2, by = c("SITE_ID", "YEAR"), all.x = TRUE, sort = FALSE)
    setorder(b2new, SITE_ID, YEAR)
    stopifnot(nrow(b2new) == n2, sum(complete.cases(b2new)) == n2)
    # every original column must survive untouched
    stopifnot(all(names(b2) %in% names(b2new)))
    for (cc in setdiff(names(b2), c("SITE_ID", "YEAR")))
      stopifnot(isTRUE(all.equal(setorder(copy(b2), SITE_ID, YEAR)[[cc]], b2new[[cc]], tolerance = 1e-12)))
    fwrite(setorder(copy(b1), SITE_ID, YEAR),
           sprintf("%s/%s/%s_B1_%s_harmonized.csv", B, out_dir, out_prefix, r))
    fwrite(b2new, sprintf("%s/%s/%s_B2_%s_harmonized.csv", B, out_dir, out_prefix, r))
    cat(sprintf("  %-7s B1 %d rows x %d cols | B2 %d rows x %d cols  (+%d lag2)\n",
                r, n1, ncol(b1), nrow(b2new), ncol(b2new), ncol(b2new) - ncol(b2)))
  }
}

build("v10",      "v10",      "v10_lag2",      "v10_lag2",      "tc>=30  (93 sites / 395 site-years)")
build("v10_tc50", "v10_tc50", "v10_tc50_lag2", "v10_tc50_lag2", "tc>=50  (65 sites / 287 site-years)")
cat("\nLAG2_DATASETS_DONE\n")

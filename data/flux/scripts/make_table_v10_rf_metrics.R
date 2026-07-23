#!/usr/bin/env Rscript
# ============================================================================
# Generate LaTeX table of V10 RF LOSO metrics (matches table_RF_LOSO_v4 style)
# Two tables (all-sites 113, high-tree-cover 93); 4 panels each
# (12m/24m window × anomaly/raw memory). Cell = R2 (RMSE); bold = best R2/EFP.
# ============================================================================

library(data.table)
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

EFPS <- c("GPPsat", "NEPmax", "ETmax", "uWUE", "WUE")
RMSE_DEC <- c(GPPsat = 2, NEPmax = 2, ETmax = 4, uWUE = 3, WUE = 3)
HDR <- c(GPPsat = "GPP$_\\mathrm{sat}$", NEPmax = "NEP$_\\mathrm{max}$",
         ETmax = "ET$_\\mathrm{max}$", uWUE = "uWUE", WUE = "WUE")
UNIT <- c(GPPsat = "($\\mu$mol m$^{-2}$ s$^{-1}$)", NEPmax = "($\\mu$mol m$^{-2}$ s$^{-1}$)",
          ETmax = "(mm d$^{-1}$)", uWUE = "(g C mm$^{-1}$)", WUE = "(g C mm$^{-1}$)")

MODELS <- list(
  list(id = "M1", pred = "C"),          list(id = "M2", pred = "C + D"),
  list(id = "M3", pred = "C + T"),      list(id = "M4", pred = "C + T + D"),
  list(id = "M5", pred = "C + M"),      list(id = "M6", pred = "C + D + M"),
  list(id = "M7", pred = "C + T + M"),  list(id = "M8", pred = "C + T + D + M")
)

mid <- function(base, mem, win) {
  if (base %in% c("M1", "M2", "M3", "M4")) return(paste0(base, "_", win))
  paste0(base, "_", mem, "_", win)
}

DATASETS <- list(
  list(key = "all_sites",
       file = "derived_tables/outputs_afterEGU_results/RF_v10_all_sites/RF_metrics_LOSO.csv",
       name = "all sites", sites = 113),
  list(key = "filtered",
       file = "derived_tables/outputs_afterEGU_results/RF_v10/RF_metrics_LOSO.csv",
       name = "high tree cover ($>$30\\% canopy)", sites = 93)
)

PANELS <- list(
  list(L = "A", win = "12m", mem = "anom", lab = "Lag1 only --- Anomaly EFP memory"),
  list(L = "B", win = "12m", mem = "raw",  lab = "Lag1 only --- Raw-lag EFP memory"),
  list(L = "C", win = "24m", mem = "anom", lab = "Lag1 + Lag2 --- Anomaly EFP memory"),
  list(L = "D", win = "24m", mem = "raw",  lab = "Lag1 + Lag2 --- Raw-lag EFP memory")
)

emit_panel <- function(dt, p, n_sy) {
  # gather R2/RMSE per model per EFP
  r2m <- matrix(NA_real_, 8, 5, dimnames = list(NULL, EFPS))
  rmsem <- r2m
  for (i in seq_along(MODELS)) {
    id <- mid(MODELS[[i]]$id, p$mem, p$win)
    for (e in EFPS) {
      row <- dt[model == id & response == e]
      if (nrow(row)) { r2m[i, e] <- row$R2; rmsem[i, e] <- row$RMSE }
    }
  }
  best <- apply(r2m, 2, max, na.rm = TRUE)
  lines <- c(
    "\\midrule",
    sprintf("\\multicolumn{8}{l}{\\textit{Panel %s: %s --- %d site-years}} \\\\", p$L, p$lab, n_sy),
    "\\midrule"
  )
  for (i in seq_along(MODELS)) {
    cells <- sapply(EFPS, function(e) {
      s <- sprintf("%.3f (%.*f)", r2m[i, e], RMSE_DEC[[e]], rmsem[i, e])
      if (!is.na(r2m[i, e]) && abs(r2m[i, e] - best[e]) < 1e-9) s <- paste0("\\textbf{", s, "}")
      s
    })
    ncol <- if (i == 1) sprintf("\\multirow{8}{*}{%d}", n_sy) else ""
    lines <- c(lines, sprintf("%s & %s & %s & %s \\\\",
                              MODELS[[i]]$id, MODELS[[i]]$pred, ncol,
                              paste(cells, collapse = " & ")))
  }
  lines
}

emit_table <- function(ds) {
  dt <- fread(ds$file)
  n_sy <- unique(dt$n_pairs)[1]
  hdr1 <- paste(sapply(EFPS, function(e) HDR[[e]]), collapse = " & ")
  hdr2 <- paste(sapply(EFPS, function(e) UNIT[[e]]), collapse = " & ")
  out <- c(
    "\\begin{table}[htbp]",
    "\\centering",
    sprintf(paste0("\\caption{Leave-one-site-out random forest performance for five ecosystem ",
                   "functional properties (EFPs) on the V10 \\textbf{%s} dataset (%d sites, %d site-years). ",
                   "Panels A--B: 12-month climate window (lag1); Panels C--D: 24-month window (lag1+lag2). ",
                   "Panels A,C use anomaly EFP memory; Panels B,D use raw-lag EFP memory. ",
                   "Each cell shows $R^2$ (RMSE in native units). \\textbf{Bold} = best $R^2$ per EFP within each panel.}"),
            ds$name, ds$sites, n_sy),
    sprintf("\\label{tab:RF_LOSO_v10_%s}", ds$key),
    "\\footnotesize",
    "\\setlength{\\tabcolsep}{4pt}",
    "\\begin{tabular}{llcccccc}",
    "\\toprule",
    sprintf("Model & Predictors & $n$ & %s \\\\", hdr1),
    sprintf("  &  &  & %s \\\\", hdr2),
    unlist(lapply(PANELS, function(p) emit_panel(dt, p, n_sy))),
    "\\midrule",
    "\\bottomrule",
    "\\end{tabular}",
    "\\vspace{2pt}",
    "\\begin{minipage}{\\linewidth}",
    "\\footnotesize",
    paste0("\\textit{Note:} C = Climate (TA, VPD, SW$_\\mathrm{IN}$, P; mean/p05/p95); ",
           "T = Plant traits (hydraulic, leaf, stem); ",
           "D = Disturbance (absolute/relative mortality, relative disturbance, new mortality at 100--500\\,m, with lags); ",
           "M = EFP memory (previous-year value; anomaly z-score in Panels A,C; raw lag in Panels B,D). ",
           "12-month window = lag1 only; 24-month window = lag1 + lag2. RMSE in native units in parentheses."),
    "\\end{minipage}",
    "\\end{table}"
  )
  out
}

all_lines <- unlist(lapply(DATASETS, function(ds) c(emit_table(ds), "")))
out_file <- "manuscript/tables/table_RF_LOSO_v10.tex"
writeLines(all_lines, out_file)
cat("Wrote", out_file, "(", length(all_lines), "lines )\n")

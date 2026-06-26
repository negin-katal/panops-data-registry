library(data.table)
library(plotly)
library(jsonlite)

# ============================================================
# PLOT 08: Interactive mortality explorer (self-contained HTML)
#
#  Panel 1 — Violin: mortality intensity by IGBP
#  Panel 2 — Bar:    all 166 sites sorted by peak mortality (click-enabled)
#  Panel 3 — Time series: deadwood + forest loss for clicked site
#
#  Approach: plotly_json() per figure + CDN plotly.js + custom JS
#  Produces a single self-contained HTML file (~5-10 MB).
# ============================================================

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_file   <- "plots/disturbance_effects/interactive_mortality.html"
model_file <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
bench_shap <- "derived_tables/outputs_afterEGU_results/RF_outputs_fixed/RF_site_shap_M04_M08.csv"

EXCLUDE_SITES <- c(
  "CZ-Stn", "DE-Lnf", "US-CMW", "US-Cwt", "US-HBK", "US-xGR", "US-xST",
  "US-xTR", "JP-Fhk", "JP-Tef", "GF-Guy", "KR-WdE", "CA-SCC", "JP-Fjy",
  "NL-Loo", "US-CRK", "US-xSP", "US-xWR", "BE-Vie", "IT-Cp2", "KR-JjM",
  "ES-Agu", "CA-SCB", "IE-Cra", "RU-Ch2", "RU-Che", "US-ALQ", "US-Srr",
  "US-YK1", "US-YK2", "US-xBA"
)

# Colour palette
BG      <- "#0D0D0D"
PANEL   <- "#111827"
GRID    <- "#2A2A3A"
TEXT    <- "#E0E0E0"
SUBTEXT <- "#9CA3AF"
AXIS    <- "#4B5563"

igbp_colours <- c(
  ENF = "#1B6B3A", EBF = "#45B045", DNF = "#2E8B8B", DBF = "#8FBC45",
  MF  = "#5F9EA0", CSH = "#C4843B", OSH = "#D4B483", WSA = "#A9A93A",
  SAV = "#D4C23A", WET = "#4682B4", CRO = "#CC4444", URB = "#888888"
)

# ============================================================
# 1) Load + filter data
# ============================================================

cols_need <- c("SITE_ID", "YEAR", "IGBP",
               "mortality_intensity_pct_500m",
               "deadwood_mean_pct_500m",
               "deadwood_increase_area_frac_500m",
               "forest_mean_pct_500m",
               "loss_area_frac_500m")
dt <- fread(model_file, select = cols_need)
dt <- dt[!SITE_ID %in% EXCLUDE_SITES]

bench_sites <- unique(fread(bench_shap)$test_site)
dt          <- dt[SITE_ID %in% bench_sites]
cat("Sites:", uniqueN(dt$SITE_ID), " | Rows:", nrow(dt), "\n")

site_dt <- dt[, .(
  IGBP      = IGBP[1],
  peak_mort = max(mortality_intensity_pct_500m, na.rm = TRUE),
  mean_mort = mean(mortality_intensity_pct_500m, na.rm = TRUE)
), by = SITE_ID]
setorder(site_dt, -peak_mort)
site_dt[, colour := igbp_colours[IGBP]]
site_dt[is.na(colour), colour := "#888888"]

# ============================================================
# 2) Time-series JSON (all sites, embedded in HTML)
# ============================================================

ts_list <- lapply(split(dt, dt$SITE_ID), function(d) {
  d <- d[order(YEAR)]
  list(
    years           = d$YEAR,
    deadwood        = round(d$deadwood_mean_pct_500m, 3),
    deadwood_incr   = round(d$deadwood_increase_area_frac_500m * 100, 3),
    forest_cover    = round(d$forest_mean_pct_500m, 3),
    forestloss      = round(d$loss_area_frac_500m * 100, 3),
    mortality       = round(d$mortality_intensity_pct_500m, 3),
    igbp            = d$IGBP[1]
  )
})
site_data_json <- toJSON(ts_list, auto_unbox = TRUE)  # embedded lookup for JS

# ============================================================
# 3) Panel 1 — Violin: mortality by IGBP
# ============================================================

igbp_order <- site_dt[, .(med = median(peak_mort)), by = IGBP][order(med), IGBP]

violin_traces <- lapply(as.character(igbp_order), function(ig) {
  ys  <- site_dt[IGBP == ig, peak_mort]
  col <- igbp_colours[ig]
  if (is.na(col)) col <- "#888888"
  list(
    type       = "violin",
    name       = ig,
    y          = as.list(ys),
    x          = as.list(rep(ig, length(ys))),
    box        = list(visible = TRUE),
    points     = "all",
    jitter     = 0.3,
    pointpos   = 0,
    marker     = list(size = 5, opacity = 0.75, color = col),
    line       = list(color = col),
    fillcolor  = paste0(col, "55"),
    showlegend = FALSE,
    hovertemplate = paste0("<b>", ig, "</b><br>Peak mortality: %{y:.1f}%<extra></extra>")
  )
})

violin_layout <- list(
  title        = list(text = "Peak mortality intensity by IGBP class",
                      font = list(size = 14, color = TEXT)),
  xaxis        = list(title = "", gridcolor = GRID, linecolor = AXIS,
                      tickfont = list(color = TEXT)),
  yaxis        = list(title = "Peak mortality intensity (%)",
                      gridcolor = GRID, linecolor = AXIS,
                      tickfont = list(color = TEXT),
                      titlefont = list(color = SUBTEXT)),
  paper_bgcolor = BG,
  plot_bgcolor  = PANEL,
  font          = list(color = TEXT),
  margin        = list(l = 60, r = 20, t = 50, b = 40),
  height        = 320
)

violin_json <- toJSON(list(data = violin_traces, layout = violin_layout),
                      auto_unbox = TRUE)

# ============================================================
# 4) Panel 2 — Bar: sites sorted by peak mortality
# ============================================================

bar_traces <- lapply(unique(site_dt$IGBP), function(ig) {
  sub <- site_dt[IGBP == ig]
  col <- igbp_colours[ig]
  if (is.na(col)) col <- "#888888"
  list(
    type   = "bar",
    name   = ig,
    x      = as.list(sub$SITE_ID),
    y      = as.list(sub$peak_mort),
    marker = list(color = col),
    hovertemplate = paste0(
      "<b>%{x}</b><br>IGBP: ", ig,
      "<br>Peak mortality: %{y:.1f}%<extra></extra>"
    )
  )
})

bar_layout <- list(
  title   = list(
    text = "Sites sorted by peak mortality intensity  (click a bar to see trends)",
    font = list(size = 13, color = TEXT)
  ),
  barmode = "overlay",
  xaxis   = list(
    title         = "",
    categoryorder = "array",
    categoryarray = as.list(site_dt$SITE_ID),
    tickangle     = -60,
    tickfont      = list(size = 7, color = SUBTEXT),
    gridcolor     = GRID,
    linecolor     = AXIS
  ),
  yaxis = list(
    title     = "Peak mortality intensity (%)",
    gridcolor = GRID,
    linecolor = AXIS,
    tickfont  = list(color = TEXT),
    titlefont = list(color = SUBTEXT)
  ),
  paper_bgcolor = BG,
  plot_bgcolor  = PANEL,
  font    = list(color = TEXT),
  legend  = list(
    bgcolor = "#1A1A2E", bordercolor = AXIS, borderwidth = 1,
    font    = list(color = TEXT, size = 10)
  ),
  margin = list(l = 60, r = 20, t = 50, b = 90),
  height = 380
)

bar_json <- toJSON(list(data = bar_traces, layout = bar_layout),
                   auto_unbox = TRUE)

# ============================================================
# 5) Panel 3 — Time series (default = site with highest mortality)
# ============================================================

def_site <- site_dt$SITE_ID[1]
def_d    <- ts_list[[def_site]]

ts_traces <- list(
  list(
    x    = as.list(def_d$years),
    y    = as.list(def_d$deadwood),
    type = "scatter", mode = "lines+markers",
    name = "Standing deadwood (%)",
    yaxis = "y",
    line   = list(color = "#8FBC45", width = 2),
    marker = list(color = "#8FBC45", size = 6),
    hovertemplate = "Year: %{x}<br>Deadwood: %{y:.1f}%<extra></extra>"
  ),
  list(
    x    = as.list(def_d$years),
    y    = as.list(def_d$deadwood_incr),
    type = "scatter", mode = "lines+markers",
    name = "Deadwood increase (area %)",
    yaxis = "y",
    line   = list(color = "#C8E86A", width = 2, dash = "dot"),
    marker = list(color = "#C8E86A", size = 6),
    hovertemplate = "Year: %{x}<br>Deadwood increase: %{y:.2f}%<extra></extra>"
  ),
  list(
    x    = as.list(def_d$years),
    y    = as.list(def_d$forest_cover),
    type = "scatter", mode = "lines+markers",
    name = "Forest cover (%)",
    yaxis = "y2",
    line   = list(color = "#22D4EB", width = 2),
    marker = list(color = "#22D4EB", size = 6),
    hovertemplate = "Year: %{x}<br>Forest cover: %{y:.1f}%<extra></extra>"
  ),
  list(
    x    = as.list(def_d$years),
    y    = as.list(def_d$forestloss),
    type = "scatter", mode = "lines+markers",
    name = "Forest cover loss (area %)",
    yaxis = "y2",
    line   = list(color = "#E8257A", width = 2, dash = "dash"),
    marker = list(color = "#E8257A", size = 6),
    hovertemplate = "Year: %{x}<br>Forest loss: %{y:.2f}%<extra></extra>"
  ),
  list(
    x    = as.list(def_d$years),
    y    = as.list(def_d$mortality),
    type = "scatter", mode = "lines+markers",
    name = "Mortality intensity (%)",
    yaxis = "y",
    line   = list(color = "#FFA500", width = 2, dash = "dash"),
    marker = list(color = "#FFA500", size = 6),
    hovertemplate = "Year: %{x}<br>Mortality: %{y:.1f}%<extra></extra>"
  )
)

ts_layout <- list(
  title  = list(
    text = paste0("Temporal trends - ", def_site, "  (IGBP: ", def_d$igbp, ")"),
    font = list(size = 13, color = TEXT)
  ),
  xaxis  = list(title = "Year", gridcolor = GRID, linecolor = AXIS,
                tickfont = list(color = TEXT), titlefont = list(color = SUBTEXT),
                dtick = 1),
  yaxis  = list(title = "Deadwood / Mortality (%)", side = "left",
                gridcolor = GRID, linecolor = AXIS,
                tickfont = list(color = TEXT), titlefont = list(color = SUBTEXT)),
  yaxis2 = list(title = "Forest cover (%)", side = "right",
                overlaying = "y", showgrid = FALSE,
                linecolor = AXIS,
                tickfont = list(color = TEXT), titlefont = list(color = SUBTEXT)),
  paper_bgcolor = BG,
  plot_bgcolor  = PANEL,
  font   = list(color = TEXT),
  legend = list(
    bgcolor = "#1A1A2E", bordercolor = AXIS, borderwidth = 1,
    font    = list(color = TEXT, size = 10),
    orientation = "h", x = 0, y = -0.28
  ),
  margin = list(l = 60, r = 70, t = 50, b = 100),
  height = 420
)

ts_fig_json <- toJSON(list(data = ts_traces, layout = ts_layout),
                      auto_unbox = TRUE)

# ============================================================
# 6) Build final HTML
# ============================================================

html <- paste0('<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Mortality Intensity Explorer</title>
  <script src="https://cdn.plot.ly/plotly-2.27.0.min.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body  { background:', BG, '; color:', TEXT, ';
            font-family: Arial, sans-serif; padding: 16px; }
    h1    { text-align: center; font-size: 1.3em; color:', TEXT, ';
            margin-bottom: 4px; padding-top: 4px; }
    .sub  { text-align: center; font-size: 0.85em; color:', SUBTEXT, ';
            margin-bottom: 20px; }
    .panel { background:', PANEL, '; border-radius: 8px;
             padding: 6px; margin-bottom: 16px; }
  </style>
</head>
<body>
  <h1>Forest Disturbance &amp; Mortality Explorer</h1>
  <p class="sub">166 FLUXNET sites &nbsp;|&nbsp; Click a site bar to update the time series panel below</p>

  <div class="panel"><div id="violin-plot"></div></div>
  <div class="panel"><div id="bar-plot"></div></div>
  <div class="panel"><div id="ts-plot"></div></div>

<script>
// ---- Embedded time-series data for all sites ----
var siteData = ', site_data_json, ';

// ---- Render Panel 1: Violin ----
var violinSpec = ', violin_json, ';
Plotly.newPlot("violin-plot", violinSpec.data, violinSpec.layout, {responsive: true});

// ---- Render Panel 2: Bar chart ----
var barSpec = ', bar_json, ';
Plotly.newPlot("bar-plot", barSpec.data, barSpec.layout, {responsive: true});

// ---- Render Panel 3: Time series (default site) ----
var tsSpec = ', ts_fig_json, ';
Plotly.newPlot("ts-plot", tsSpec.data, tsSpec.layout, {responsive: true});

// ---- Wire click on bar chart ----
document.getElementById("bar-plot").on("plotly_click", function(eventData) {
  var pt = eventData.points[0];
  var site = pt.x;
  if (!site || !siteData[site]) return;

  var d = siteData[site];

  var traces = [
    {
      x: d.years, y: d.deadwood,
      type: "scatter", mode: "lines+markers",
      name: "Standing deadwood (%)", yaxis: "y",
      line:   {color: "#8FBC45", width: 2},
      marker: {color: "#8FBC45", size: 6},
      hovertemplate: "Year: %{x}<br>Deadwood: %{y:.1f}%<extra></extra>"
    },
    {
      x: d.years, y: d.deadwood_incr,
      type: "scatter", mode: "lines+markers",
      name: "Deadwood increase (area %)", yaxis: "y",
      line:   {color: "#C8E86A", width: 2, dash: "dot"},
      marker: {color: "#C8E86A", size: 6},
      hovertemplate: "Year: %{x}<br>Deadwood increase: %{y:.2f}%<extra></extra>"
    },
    {
      x: d.years, y: d.forest_cover,
      type: "scatter", mode: "lines+markers",
      name: "Forest cover (%)", yaxis: "y2",
      line:   {color: "#22D4EB", width: 2},
      marker: {color: "#22D4EB", size: 6},
      hovertemplate: "Year: %{x}<br>Forest cover: %{y:.1f}%<extra></extra>"
    },
    {
      x: d.years, y: d.forestloss,
      type: "scatter", mode: "lines+markers",
      name: "Forest cover loss (area %)", yaxis: "y2",
      line:   {color: "#E8257A", width: 2, dash: "dash"},
      marker: {color: "#E8257A", size: 6},
      hovertemplate: "Year: %{x}<br>Forest loss: %{y:.2f}%<extra></extra>"
    },
    {
      x: d.years, y: d.mortality,
      type: "scatter", mode: "lines+markers",
      name: "Mortality intensity (%)", yaxis: "y",
      line:   {color: "#FFA500", width: 2, dash: "dash"},
      marker: {color: "#FFA500", size: 6},
      hovertemplate: "Year: %{x}<br>Mortality: %{y:.1f}%<extra></extra>"
    }
  ];

  var layout = {
    title: {
      text: "Temporal trends - " + site + "  (IGBP: " + d.igbp + ")",
      font: {size: 13, color: "', TEXT, '"}
    },
    xaxis:  {title: "Year", gridcolor: "', GRID, '", linecolor: "', AXIS, '",
             tickfont: {color: "', TEXT, '"}, titlefont: {color: "', SUBTEXT, '"}, dtick: 1},
    yaxis:  {title: "Deadwood / Mortality (%)", side: "left",
             gridcolor: "', GRID, '", linecolor: "', AXIS, '",
             tickfont: {color: "', TEXT, '"}, titlefont: {color: "', SUBTEXT, '"}},
    yaxis2: {title: "Forest cover (%)", side: "right",
             overlaying: "y", showgrid: false, linecolor: "', AXIS, '",
             tickfont: {color: "', TEXT, '"}, titlefont: {color: "', SUBTEXT, '"}},
    paper_bgcolor: "', BG, '",
    plot_bgcolor:  "', PANEL, '",
    font:   {color: "', TEXT, '"},
    legend: {bgcolor: "#1A1A2E", bordercolor: "', AXIS, '", borderwidth: 1,
             font: {color: "', TEXT, '", size: 10},
             orientation: "h", x: 0, y: -0.28},
    margin: {l: 60, r: 70, t: 50, b: 100},
    height: 420
  };

  Plotly.react("ts-plot", traces, layout);
});
</script>
</body>
</html>')

writeLines(html, out_file)
cat("Saved:", out_file, "\n")
cat("File size:", round(file.size(out_file) / 1024, 0), "KB\n")

library(data.table)
library(jsonlite)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_file <- "plots/disturbance_effects/efp_explorer.html"
dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

plotly_js <- paste(readLines("/tmp/plotly-2.27.0.min.js", warn = FALSE), collapse = "\n")

# ── Load data ─────────────────────────────────────────────────────────────────
efp_raw <- fread("fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_YEARLY_EFP_min4continuousYears.csv")
meta    <- fread("derived_tables/site_metadata_all_efp.csv")
clim_184 <- fread("/tmp/site_mat_map.csv")   # MAT/MAP for 184 modeling sites

meta[, NETWORK := fifelse(ZIP_FILE == "" | is.na(ZIP_FILE), "Other",
                          sub("_.*", "", ZIP_FILE))]
meta[NETWORK == "AMF",   NETWORK := "AmeriFlux"]
meta[NETWORK == "ICOS",  NETWORK := "ICOS"]
meta[NETWORK == "EUF",   NETWORK := "EuroFlux"]
meta[NETWORK == "TERN",  NETWORK := "TERN"]
meta[NETWORK == "CNF",   NETWORK := "ChinaFlux"]
meta[NETWORK == "JPF",   NETWORK := "JapanFlux"]
meta[NETWORK == "KOF",   NETWORK := "KoFlux"]
meta[NETWORK == "SAEON", NETWORK := "SAEON"]
meta[NETWORK == "FLX",   NETWORK := "FLUXNET"]
meta[NETWORK == "Unknown", NETWORK := "Other"]

efp <- efp_raw[status == "ok"]
efp[meta, `:=`(IGBP      = i.IGBP,
               NETWORK   = i.NETWORK,
               SITE_NAME = i.SITE_NAME,
               LAT       = as.numeric(i.LOCATION_LAT),
               LON       = as.numeric(i.LOCATION_LONG)),
    on = .(SITE_ID)]
efp[is.na(IGBP),    IGBP    := "Unknown"]
efp[is.na(NETWORK), NETWORK := "Other"]

# Add climate for Whittaker plot (184 modeling sites only)
efp[clim_184, `:=`(MAT    = i.MAT,
                    MAP_cm = i.MAP_cm),
    on = .(SITE_ID)]

EFP_COLS <- c("GPPsat","NEPmax","ETmax","uWUE","WUE","G1","EF","EFampl")
all_sites <- sort(unique(efp$SITE_ID))
all_years <- 2017:2025
cat("Sites:", length(all_sites), "| Rows:", nrow(efp), "\n")

# ── Missing values summary ────────────────────────────────────────────────────
n_total_sites <- length(all_sites)
miss_list <- lapply(EFP_COLS, function(col) {
  n_ok    <- efp[, sum(!is.na(get(col)))]
  n_miss  <- efp[, sum( is.na(get(col)))]
  n_sites_any   <- efp[, sum(!is.na(get(col))), by = SITE_ID][V1 > 0, .N]
  n_sites_miss  <- n_total_sites - n_sites_any
  list(col=col, n_ok=n_ok, n_miss=n_miss,
       n_sites_ok=n_sites_any, n_sites_miss=n_sites_miss)
})
json_miss <- toJSON(miss_list, auto_unbox = TRUE)

# ── IGBP site counts ──────────────────────────────────────────────────────────
igbp_counts <- efp[, .(n = uniqueN(SITE_ID)), by = IGBP][order(-n)]
json_igbp   <- toJSON(igbp_counts, auto_unbox = TRUE)

# ── JSON: per-site time series ────────────────────────────────────────────────
setkey(efp, SITE_ID, YEAR)
site_list <- lapply(all_sites, function(s) {
  sd  <- efp[.(s)]
  ts  <- setNames(lapply(EFP_COLS, function(col) {
    vals <- sd[[col]]
    lapply(vals, function(v) if (is.na(v)) NULL else round(v, 4))
  }), EFP_COLS)
  list(name    = sd$SITE_NAME[1],
       igbp    = sd$IGBP[1],
       network = sd$NETWORK[1],
       lat     = round(sd$LAT[1],  4),
       lon     = round(sd$LON[1],  4),
       years   = as.integer(sd$YEAR),
       ts      = ts)
})
names(site_list) <- all_sites
json_ts <- toJSON(site_list, auto_unbox = FALSE, na = "null", digits = 4)

# ── JSON: site summary (mean EFP for map colouring) ──────────────────────────
summary_list <- lapply(all_sites, function(s) {
  sd <- efp[.(s)]
  means <- setNames(lapply(EFP_COLS, function(col) {
    v <- sd[[col]]
    if (all(is.na(v))) NA_real_ else round(mean(v, na.rm = TRUE), 4)
  }), EFP_COLS)
  mat_val <- if (!is.na(sd$MAT[1])) round(sd$MAT[1], 2) else NA_real_
  map_val <- if (!is.na(sd$MAP_cm[1])) round(sd$MAP_cm[1], 1) else NA_real_
  c(list(name    = sd$SITE_NAME[1],
         igbp    = sd$IGBP[1],
         network = sd$NETWORK[1],
         lat     = if (!is.na(sd$LAT[1])) round(sd$LAT[1], 4) else NA_real_,
         lon     = if (!is.na(sd$LON[1])) round(sd$LON[1], 4) else NA_real_,
         nyears  = nrow(sd),
         yr_min  = as.integer(min(sd$YEAR)),
         yr_max  = as.integer(max(sd$YEAR)),
         MAT     = mat_val,
         MAP_cm  = map_val),
    means)
})
names(summary_list) <- all_sites
json_summary <- toJSON(summary_list, auto_unbox = TRUE, na = "null", digits = 4)

# ── JSON: availability matrix ─────────────────────────────────────────────────
# Sort sites by latitude (north→south) for the heatmap
site_lats <- sapply(all_sites, function(s) {
  v <- efp[.(s)]$LAT[1]; if (is.na(v)) 0 else v
})
sites_ns <- all_sites[order(-site_lats)]
avail_z <- lapply(sites_ns, function(s) as.integer(all_years %in% efp[.(s)]$YEAR))
names(avail_z) <- sites_ns
json_avail <- toJSON(avail_z, auto_unbox = FALSE)
json_sites_ns <- toJSON(sites_ns, auto_unbox = FALSE)

# ── Biome polygon JSON ─────────────────────────────────────────────────────────
# Downloaded from kunstler/BIOMEplot. x=MAT(°C), y*10=MAP(cm) in the CSV.
biome_raw <- fread(text = "x,y,biome
29.339,0.213,Subtropical desert
13.971,0.23,Subtropical desert
15.371,1.746,Subtropical desert
17.51,5.351,Subtropical desert
24.131,7.029,Subtropical desert
27.074,8.479,Subtropical desert
28.915,9.924,Subtropical desert
29.201,5.321,Subtropical desert
29.339,0.213,Subtropical desert
13.971,0.23,Temperate grassland/desert
-9.706,0.073,Temperate grassland/desert
-7.572,0.872,Temperate grassland/desert
4.491,3.146,Temperate grassland/desert
17.51,5.351,Temperate grassland/desert
15.371,1.746,Temperate grassland/desert
13.971,0.23,Temperate grassland/desert
17.51,5.351,Woodland/shrubland
4.491,3.146,Woodland/shrubland
-7.572,0.872,Woodland/shrubland
-9.706,0.073,Woodland/shrubland
-6.687,2.026,Woodland/shrubland
-0.949,3.917,Woodland/shrubland
3.098,5.299,Woodland/shrubland
7.147,7.831,Woodland/shrubland
10.165,9.569,Woodland/shrubland
13.918,11.165,Woodland/shrubland
18.626,12.693,Woodland/shrubland
18.176,7.943,Woodland/shrubland
17.51,5.351,Woodland/shrubland
18.626,12.693,Temperate forest
13.918,11.165,Temperate forest
10.165,9.569,Temperate forest
7.147,7.831,Temperate forest
3.098,5.299,Temperate forest
-0.949,3.917,Temperate forest
-6.687,2.026,Temperate forest
-14.051,3.803,Temperate forest
-13.553,7.861,Temperate forest
-8.619,14.302,Temperate forest
-1.547,17.927,Temperate forest
8.173,19.924,Temperate forest
18.626,18.418,Temperate forest
18.626,12.693,Temperate forest
-1.547,17.927,Boreal forest
-8.619,14.302,Boreal forest
-13.553,7.861,Boreal forest
-14.051,3.803,Boreal forest
-12.476,3.786,Boreal forest
-11.404,6.105,Boreal forest
-9.336,8.524,Boreal forest
-6.202,11.109,Boreal forest
-3.068,13.36,Boreal forest
-1.547,17.927,Boreal forest
-1.547,17.927,Temperate rain forest
-3.068,13.36,Temperate rain forest
-6.202,11.109,Temperate rain forest
-9.336,8.524,Temperate rain forest
-11.404,6.105,Temperate rain forest
-12.476,3.786,Temperate rain forest
-12.995,6.638,Temperate rain forest
-11.523,12.294,Temperate rain forest
-6.202,20.443,Temperate rain forest
2.057,25.101,Temperate rain forest
8.173,27.765,Temperate rain forest
18.626,27.765,Temperate rain forest
18.626,18.418,Temperate rain forest
8.173,19.924,Temperate rain forest
-1.547,17.927,Temperate rain forest
18.626,18.418,Tropical forest/savanna
8.173,19.924,Tropical forest/savanna
2.057,25.101,Tropical forest/savanna
8.173,27.765,Tropical forest/savanna
18.626,27.765,Tropical forest/savanna
28.073,27.765,Tropical forest/savanna
27.065,22.608,Tropical forest/savanna
27.065,19.924,Tropical forest/savanna
25.007,19.924,Tropical forest/savanna
18.626,18.418,Tropical forest/savanna
18.626,27.765,Tropical forest/savanna
28.073,27.765,Tropical forest/savanna
27.065,22.608,Tropical rain forest
29.339,18.518,Tropical rain forest
29.339,12.926,Tropical rain forest
27.065,19.924,Tropical rain forest
27.065,22.608,Tropical rain forest
28.073,27.765,Tropical rain forest
-14.051,3.803,Tundra
-9.706,0.073,Tundra
-7.572,0.872,Tundra
-6.687,2.026,Tundra
-14.051,3.803,Tundra
-9.706,0.073,Tundra
-12.476,3.786,Tundra
-11.404,6.105,Tundra
-9.336,8.524,Tundra
-6.202,11.109,Tundra
-3.068,13.36,Tundra
-1.547,17.927,Tundra
-6.687,2.026,Tundra
-9.706,0.073,Tundra
-14.051,3.803,Tundra")

# Convert: biome polygon MAP (cm) = y*10, MAT (°C) = x
biome_polys <- lapply(unique(biome_raw$biome), function(b) {
  pts <- biome_raw[biome == b]
  list(mat = pts$x, map_cm = pts$y * 10)
})
names(biome_polys) <- unique(biome_raw$biome)
json_biomes <- toJSON(biome_polys, auto_unbox = FALSE, digits = 4)

cat("All JSON built\n")
n_sites <- length(all_sites)

# ── HTML ──────────────────────────────────────────────────────────────────────
html <- paste0('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>EFP Explorer — Fluxnet 2017-2025</title>
<script>', plotly_js, '</script>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0D0D0D;color:#E0E0E0;font-family:Arial,sans-serif;padding:16px}
a{color:#22D4EB;text-decoration:none}a:hover{text-decoration:underline}
h1{text-align:center;font-size:1.25em;margin-bottom:4px}
.sub{text-align:center;font-size:0.82em;color:#9CA3AF;margin-bottom:14px}
.panel{background:#111827;border-radius:8px;padding:6px;margin-bottom:14px}
.panel-title{font-size:0.78em;color:#9CA3AF;text-transform:uppercase;
             letter-spacing:.07em;font-weight:bold;padding:6px 6px 2px}
#controls{background:#111827;border-radius:8px;padding:14px 18px;margin-bottom:14px;
          display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start}
.ctrl-group{display:flex;flex-direction:column;gap:8px;min-width:0}
.ctrl-label{font-size:0.75em;color:#9CA3AF;text-transform:uppercase;letter-spacing:.06em;font-weight:bold}
.vdiv{width:1px;background:#2A2A3A;align-self:stretch;margin:0 4px}
.btn-row{display:flex;gap:5px;flex-wrap:wrap}
.tog-btn{background:#1F2937;color:#9CA3AF;border:1px solid #4B5563;border-radius:5px;
         padding:5px 13px;cursor:pointer;font-size:0.82em;transition:all .15s}
.tog-btn:hover{background:#374151}
.tog-btn.active{background:#22D4EB;color:#0D0D0D;border-color:#22D4EB;font-weight:bold}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:14px}
.nav-back{display:inline-block;margin-bottom:10px;font-size:0.85em;
          background:#1F2937;border:1px solid #4B5563;border-radius:5px;padding:5px 14px}
/* summary table */
.miss-table{width:100%;border-collapse:collapse;font-size:0.8em;margin:6px 0}
.miss-table th{color:#9CA3AF;font-weight:normal;text-align:left;padding:3px 8px;border-bottom:1px solid #2A2A3A}
.miss-table td{padding:3px 8px;border-bottom:1px solid #1A1A2E}
.bar-bg{background:#1F2937;border-radius:3px;height:10px;overflow:hidden;min-width:80px}
.bar-fill{height:100%;border-radius:3px;background:#22D4EB;transition:width .3s}
.bar-fill.warn{background:#FFA500}
.bar-fill.bad{background:#E8257A}
</style>
</head>
<body>
<a href="index.html" class="nav-back">&#8592; Back to hub</a>
<h1>Ecosystem Functional Properties Explorer</h1>
<p class="sub">', n_sites, ' FluxNet sites &nbsp;|&nbsp; 2017–2025 &nbsp;|&nbsp;
  Click map, heatmap, or scatter to load site time series</p>

<div id="controls">
  <div class="ctrl-group">
    <div class="ctrl-label">Map colour</div>
    <div class="btn-row">
      <button class="tog-btn active" data-mc="IGBP"    onclick="setMapColor(\'IGBP\')">IGBP</button>
      <button class="tog-btn"        data-mc="NETWORK" onclick="setMapColor(\'NETWORK\')">Network</button>
      <button class="tog-btn"        data-mc="GPPsat"  onclick="setMapColor(\'GPPsat\')">GPPsat</button>
      <button class="tog-btn"        data-mc="NEPmax"  onclick="setMapColor(\'NEPmax\')">NEPmax</button>
      <button class="tog-btn"        data-mc="ETmax"   onclick="setMapColor(\'ETmax\')">ETmax</button>
      <button class="tog-btn"        data-mc="uWUE"    onclick="setMapColor(\'uWUE\')">uWUE</button>
      <button class="tog-btn"        data-mc="EF"      onclick="setMapColor(\'EF\')">EF</button>
      <button class="tog-btn"        data-mc="G1"      onclick="setMapColor(\'G1\')">G1</button>
    </div>
  </div>
  <div class="vdiv"></div>
  <div class="ctrl-group">
    <div class="ctrl-label">Whittaker colour</div>
    <div class="btn-row" id="whit-color-btns"></div>
  </div>
  <div class="vdiv"></div>
  <div class="ctrl-group">
    <div class="ctrl-label">Violin / Time-series EFP</div>
    <div class="btn-row" id="efp-metric-btns"></div>
  </div>
</div>

<!-- Summary row -->
<div class="grid2">
  <div class="panel">
    <div class="panel-title">Sites per ecosystem type (IGBP)</div>
    <div id="igbp-bar"></div>
  </div>
  <div class="panel">
    <div class="panel-title">EFP data completeness</div>
    <div style="padding:6px 10px">
    <table class="miss-table" id="miss-table">
      <tr><th>EFP</th><th>Sites with data</th><th>Missing rows</th><th>Coverage</th></tr>
    </table>
    </div>
  </div>
</div>

<div class="panel">
  <div class="panel-title">World map — click a site to load time series</div>
  <div id="map-plot"></div>
</div>

<div class="grid2">
  <div class="panel">
    <div class="panel-title">Data availability (2017–2025) — click a site row</div>
    <div id="avail-plot"></div>
  </div>
  <div class="panel">
    <div class="panel-title">EFP distribution by IGBP — <span id="violin-label" style="color:#22D4EB">GPPsat</span></div>
    <div id="violin-plot"></div>
  </div>
</div>

<div class="panel">
  <div class="panel-title">Whittaker biome diagram — MAT vs MAP (184 modeling sites, click to load time series)</div>
  <div id="whit-plot"></div>
</div>

<div class="panel">
  <div class="panel-title">Site time series — <span id="ts-site-label" style="color:#22D4EB">click a site above</span> &nbsp;|&nbsp; EFP: <span id="ts-efp-label" style="color:#22D4EB">GPPsat</span></div>
  <div id="ts-plot"></div>
</div>

<script>
// ── Embedded data ─────────────────────────────────────────────────────────────
var SITE_SUMMARY = ', json_summary, ';
var SITE_TS      = ', json_ts, ';
var AVAIL        = ', json_avail, ';
var SITES_NS     = ', json_sites_ns, ';   // north-to-south sorted
var MISS_DATA    = ', json_miss, ';
var IGBP_DATA    = ', json_igbp, ';
var BIOMES       = ', json_biomes, ';

var ALL_YEARS = [2017,2018,2019,2020,2021,2022,2023,2024,2025];
var EFP_COLS  = ["GPPsat","NEPmax","ETmax","uWUE","WUE","G1","EF","EFampl"];
var EFP_UNITS = {GPPsat:"μmol m⁻² s⁻¹",NEPmax:"μmol m⁻² s⁻¹",ETmax:"mm d⁻¹",
                 uWUE:"g C mm⁻¹",WUE:"g C mm⁻¹",G1:"kPa⁰·⁵",EF:"—",EFampl:"—"};

// ── Theme ─────────────────────────────────────────────────────────────────────
var BG="#0D0D0D",PANEL="#111827",GRID="#2A2A3A",TEXT="#E0E0E0",SUB="#9CA3AF",AXIS="#4B5563",LEG_BG="#1A1A2E";

var IGBP_COL={ENF:"#1B6B3A",EBF:"#45B045",DNF:"#2E8B8B",DBF:"#8FBC45",MF:"#5F9EA0",
  CSH:"#C4843B",OSH:"#D4B483",WSA:"#A9A93A",SAV:"#D4C23A",WET:"#4682B4",
  CRO:"#CC4444",URB:"#888888",Unknown:"#666666"};
var NET_COL={AmeriFlux:"#22D4EB",ICOS:"#E8257A",EuroFlux:"#FFA500",TERN:"#45B045",
             ChinaFlux:"#FF6200",JapanFlux:"#9B59B6",KoFlux:"#3DBDAA",
             SAEON:"#D4A017",FLUXNET:"#8FBC45",Other:"#666666"};
var BIOME_COL={
  "Subtropical desert":"#8B6914",
  "Temperate grassland/desert":"#7A5C2E",
  "Woodland/shrubland":"#4E6B1E",
  "Temperate forest":"#1E6B3A",
  "Boreal forest":"#1E4A6B",
  "Temperate rain forest":"#1E6B6B",
  "Tropical rain forest":"#1E3A6B",
  "Tropical forest/savanna":"#3A6B4E",
  "Tundra":"#4B4B5A"
};

// ── State ─────────────────────────────────────────────────────────────────────
var curMapColor="IGBP", curEfpMet="GPPsat", curWhitColor="IGBP", curSite=null;
var mapWired=false, availWired=false, whitWired=false;

// ── Safe value getter ─────────────────────────────────────────────────────────
function sv(d,k){ return (d&&d[k]!=null&&d[k]!==undefined)?d[k]:null; }

// ── Build control buttons ─────────────────────────────────────────────────────
function makeBtn(id, keys, def, fn, attr){
  var box=document.getElementById(id);
  keys.forEach(function(k){
    var b=document.createElement("button");
    b.className="tog-btn"+(k===def?" active":"");
    b.dataset[attr]=k; b.textContent=k;
    b.onclick=function(){fn(k);};
    box.appendChild(b);
  });
}
function setActive(id, attr, key){
  document.querySelectorAll("#"+id+" [data-"+attr+"]").forEach(function(b){
    b.classList.toggle("active",b.dataset[attr]===key);
  });
}

// ── Summary table ─────────────────────────────────────────────────────────────
function buildSummary(){
  var tb=document.getElementById("miss-table");
  var totalSites=Object.keys(SITE_SUMMARY).length;
  MISS_DATA.forEach(function(m){
    var pct=Math.round(m.n_sites_ok/totalSites*100);
    var clr=pct>=90?"#22D4EB":pct>=70?"#FFA500":"#E8257A";
    var tr=document.createElement("tr");
    tr.innerHTML="<td><b>"+m.col+"</b></td>"+
      "<td>"+m.n_sites_ok+" / "+totalSites+"</td>"+
      "<td>"+m.n_miss+" rows</td>"+
      "<td><div class=bar-bg><div class=bar-fill style=\'width:"+pct+"%;background:"+clr+"\'></div></div> "+pct+"%</td>";
    tb.appendChild(tr);
  });
}

// ── IGBP bar chart ────────────────────────────────────────────────────────────
function renderIGBPbar(){
  var sorted=IGBP_DATA.slice().sort(function(a,b){return b.n-a.n;});
  Plotly.react("igbp-bar",[{
    type:"bar",orientation:"h",
    x:sorted.map(function(d){return d.n;}),
    y:sorted.map(function(d){return d.IGBP;}),
    marker:{color:sorted.map(function(d){return IGBP_COL[d.IGBP]||"#888";})},
    hovertemplate:"%{y}: %{x} sites<extra></extra>"
  }],{
    xaxis:{title:"Number of sites",gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    yaxis:{tickfont:{color:TEXT},automargin:true},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:70,r:10,t:10,b:40},height:260
  },{responsive:true});
}

// ── Map ───────────────────────────────────────────────────────────────────────
function renderMap(){
  var sites=Object.keys(SITE_SUMMARY);
  var traces;
  if(curMapColor==="IGBP"||curMapColor==="NETWORK"){
    var field=curMapColor==="IGBP"?"igbp":"network";
    var COL=curMapColor==="IGBP"?IGBP_COL:NET_COL;
    var groups={};
    sites.forEach(function(s){
      var d=SITE_SUMMARY[s];
      if(sv(d,"lat")==null||sv(d,"lon")==null) return;
      var g=d[field]||"Unknown";
      if(!groups[g])groups[g]={lat:[],lon:[],text:[],cs:[]};
      groups[g].lat.push(d.lat); groups[g].lon.push(d.lon);
      groups[g].text.push("<b>"+s+"</b><br>"+(d.name||"")+"<br>IGBP: "+d.igbp+"<br>Net: "+d.network+"<br>Years: "+d.nyears);
      groups[g].cs.push(s);
    });
    traces=Object.keys(groups).sort().map(function(g){
      return{type:"scattergeo",mode:"markers",name:g,
        lat:groups[g].lat,lon:groups[g].lon,text:groups[g].text,hoverinfo:"text",
        marker:{size:8,color:COL[g]||"#888",opacity:0.85,line:{width:0.5,color:"#111"}},
        customdata:groups[g].cs};
    });
  } else {
    var col=curMapColor;
    var valid=sites.filter(function(s){return sv(SITE_SUMMARY[s],"lat")!=null&&sv(SITE_SUMMARY[s],col)!=null;});
    traces=[{type:"scattergeo",mode:"markers",name:col,
      lat:valid.map(function(s){return SITE_SUMMARY[s].lat;}),
      lon:valid.map(function(s){return SITE_SUMMARY[s].lon;}),
      text:valid.map(function(s){
        var d=SITE_SUMMARY[s], v=sv(d,col);
        return "<b>"+s+"</b><br>"+(d.name||"")+"<br>IGBP: "+d.igbp+"<br>"+col+": "+(v!=null?v.toFixed(3):"NA");
      }),
      hoverinfo:"text",
      marker:{size:8,color:valid.map(function(s){return sv(SITE_SUMMARY[s],col)||0;}),
              colorscale:"Viridis",opacity:0.9,
              showscale:true,
              colorbar:{title:{text:col},thickness:12,len:0.7,
                        tickfont:{color:TEXT,size:10},titlefont:{color:SUB,size:11}},
              line:{width:0.5,color:"#111"}},
      customdata:valid}];
  }
  Plotly.react("map-plot",traces,{
    geo:{scope:"world",bgcolor:PANEL,landcolor:"#1A2533",oceancolor:"#0D1117",
         coastlinecolor:"#2A2A3A",showland:true,showocean:true,showcoastlines:true,
         showlakes:false,projection:{type:"natural earth"},
         lonaxis:{range:[-180,180]},lataxis:{range:[-60,82]}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,font:{color:TEXT,size:10},
            x:0.01,y:0.01,xanchor:"left",yanchor:"bottom"},
    margin:{l:0,r:0,t:10,b:0},height:400
  },{responsive:true});
  if(!mapWired){
    mapWired=true;
    document.getElementById("map-plot").on("plotly_click",function(ev){
      var s=ev.points[0].customdata;
      if(typeof s==="string") loadSite(s);
    });
  }
}

// ── Availability heatmap ──────────────────────────────────────────────────────
function renderAvail(){
  var z=SITES_NS.map(function(s){return AVAIL[s]||ALL_YEARS.map(function(){return 0;});});
  Plotly.react("avail-plot",[{
    type:"heatmap",x:ALL_YEARS,y:SITES_NS,z:z,
    colorscale:[[0,"#1A2533"],[1,"#22D4EB"]],
    showscale:false,xgap:1.5,ygap:0.3,
    hovertemplate:"<b>%{y}</b><br>Year: %{x}<br>Has data: %{z}<extra></extra>"
  }],{
    xaxis:{tickfont:{size:9,color:TEXT},gridcolor:GRID,dtick:1},
    yaxis:{tickfont:{size:6,color:SUB},automargin:true,fixedrange:true},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:70,r:10,t:10,b:40},height:520
  },{responsive:true});
  if(!availWired){
    availWired=true;
    document.getElementById("avail-plot").on("plotly_click",function(ev){
      var s=ev.points[0].y;
      if(s) loadSite(s);
    });
  }
}

// ── Violin ────────────────────────────────────────────────────────────────────
function renderViolin(met){
  document.getElementById("violin-label").textContent=met;
  var groups={};
  Object.keys(SITE_SUMMARY).forEach(function(s){
    var d=SITE_SUMMARY[s], g=d.igbp||"Unknown", v=sv(d,met);
    if(v==null) return;
    if(!groups[g])groups[g]=[];
    groups[g].push(v);
  });
  function med(a){var s=a.slice().sort(function(x,y){return x-y;}),n=s.length,m=Math.floor(n/2);return n%2?s[m]:(s[m-1]+s[m])/2;}
  var igbps=Object.keys(groups).sort(function(a,b){return med(groups[a])-med(groups[b]);});
  var traces=igbps.map(function(ig){
    var col=IGBP_COL[ig]||"#888";
    return{type:"violin",name:ig,y:groups[ig],x:groups[ig].map(function(){return ig;}),
      box:{visible:true},points:"all",jitter:0.35,pointpos:0,
      marker:{size:4,opacity:0.6,color:col},line:{color:col},
      fillcolor:col+"55",showlegend:false,
      hovertemplate:"<b>"+ig+"</b><br>"+met+": %{y:.3f}<extra></extra>"};
  });
  Plotly.react("violin-plot",traces,{
    xaxis:{gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT}},
    yaxis:{title:met+" ("+EFP_UNITS[met]+")",gridcolor:GRID,linecolor:AXIS,
           tickfont:{color:TEXT},titlefont:{color:SUB},zeroline:false},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:65,r:10,t:16,b:50},height:400
  },{responsive:true});
}

// ── Whittaker biome scatter ───────────────────────────────────────────────────
function renderWhittaker(){
  var traces=[];
  // Background biome polygons
  Object.keys(BIOMES).forEach(function(bname){
    var b=BIOMES[bname];
    var col=BIOME_COL[bname]||"#333";
    traces.push({
      type:"scatter",mode:"lines",name:bname,
      x:b.mat.concat([b.mat[0]]),   // close polygon
      y:b.map_cm.concat([b.map_cm[0]]),
      fill:"toself",fillcolor:col+"55",line:{color:col,width:1},
      hoverinfo:"name",showlegend:true
    });
  });
  // Site points
  var col=curWhitColor;
  if(col==="IGBP"||col==="NETWORK"){
    var field=col==="IGBP"?"igbp":"network";
    var COL=col==="IGBP"?IGBP_COL:NET_COL;
    var groups={};
    Object.keys(SITE_SUMMARY).forEach(function(s){
      var d=SITE_SUMMARY[s];
      if(sv(d,"MAT")==null||sv(d,"MAP_cm")==null) return;
      var g=d[field]||"Unknown";
      if(!groups[g])groups[g]={x:[],y:[],text:[],cs:[]};
      groups[g].x.push(d.MAT); groups[g].y.push(d.MAP_cm);
      groups[g].text.push("<b>"+s+"</b><br>IGBP: "+d.igbp+"<br>MAT: "+d.MAT.toFixed(1)+"°C<br>MAP: "+d.MAP_cm.toFixed(0)+" cm/yr");
      groups[g].cs.push(s);
    });
    Object.keys(groups).sort().forEach(function(g){
      traces.push({type:"scatter",mode:"markers",name:g,
        x:groups[g].x,y:groups[g].y,text:groups[g].text,hoverinfo:"text",
        marker:{size:9,color:COL[g]||"#888",symbol:"circle",
                line:{width:1,color:"#111"},opacity:0.9},
        customdata:groups[g].cs,showlegend:true});
    });
  } else {
    var valid=Object.keys(SITE_SUMMARY).filter(function(s){
      return sv(SITE_SUMMARY[s],"MAT")!=null&&sv(SITE_SUMMARY[s],"MAP_cm")!=null&&sv(SITE_SUMMARY[s],col)!=null;
    });
    traces.push({type:"scatter",mode:"markers",name:col,
      x:valid.map(function(s){return SITE_SUMMARY[s].MAT;}),
      y:valid.map(function(s){return SITE_SUMMARY[s].MAP_cm;}),
      text:valid.map(function(s){
        var d=SITE_SUMMARY[s];
        return "<b>"+s+"</b><br>IGBP: "+d.igbp+"<br>MAT: "+d.MAT.toFixed(1)+"°C<br>MAP: "+d.MAP_cm.toFixed(0)+" cm/yr<br>"+col+": "+sv(d,col).toFixed(3);
      }),
      hoverinfo:"text",
      marker:{size:9,color:valid.map(function(s){return sv(SITE_SUMMARY[s],col)||0;}),
              colorscale:"Plasma",opacity:0.9,
              showscale:true,symbol:"circle",
              colorbar:{title:{text:col},thickness:12,len:0.6,x:1.01,
                        tickfont:{color:TEXT,size:10},titlefont:{color:SUB,size:11}},
              line:{width:1,color:"#111"}},
      customdata:valid,showlegend:false});
  }
  Plotly.react("whit-plot",traces,{
    xaxis:{title:"Mean annual temperature (°C)",range:[-15,30],
           gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB},zeroline:false},
    yaxis:{title:"Mean annual precipitation (cm/yr)",range:[-5,450],
           gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB},zeroline:false},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,font:{color:TEXT,size:9},
            x:1.01,y:1,xanchor:"left"},
    margin:{l:70,r:160,t:16,b:60},height:460
  },{responsive:true});
  if(!whitWired){
    whitWired=true;
    document.getElementById("whit-plot").on("plotly_click",function(ev){
      var s=ev.points[0].customdata;
      if(typeof s==="string") loadSite(s);
    });
  }
}

// ── Time series ───────────────────────────────────────────────────────────────
function renderTS(site,met){
  var d=SITE_TS[site];
  if(!d||!d.ts||!d.ts[met]) return;
  document.getElementById("ts-site-label").textContent=site+" — "+(d.name||"")+" ("+d.igbp+")";
  document.getElementById("ts-efp-label").textContent=met;
  var col=IGBP_COL[d.igbp||"Unknown"]||"#22D4EB";
  var yvals=d.ts[met];
  Plotly.react("ts-plot",[{
    type:"scatter",mode:"lines+markers",
    x:d.years,y:yvals,
    line:{color:col,width:2.5},marker:{color:col,size:8},
    connectgaps:false,
    hovertemplate:met+": %{y:.3f}<br>Year: %{x}<extra></extra>"
  }],{
    xaxis:{title:"Year",gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB},dtick:1},
    yaxis:{title:met+" ("+EFP_UNITS[met]+")",gridcolor:GRID,linecolor:AXIS,
           tickfont:{color:TEXT},titlefont:{color:SUB},zeroline:false},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:70,r:20,t:20,b:50},height:280
  },{responsive:true});
}

// ── Load site ─────────────────────────────────────────────────────────────────
function loadSite(site){
  curSite=site;
  renderTS(site,curEfpMet);
}

// ── Setters ───────────────────────────────────────────────────────────────────
function setMapColor(key){
  curMapColor=key;
  setActive("controls","mc",key);
  renderMap();
}
function setEfpMet(met){
  curEfpMet=met;
  setActive("efp-metric-btns","efpmet",met);
  renderViolin(met);
  if(curSite) renderTS(curSite,met);
}
function setWhitColor(key){
  curWhitColor=key;
  setActive("whit-color-btns","wc",key);
  renderWhittaker();
}

// ── Init ──────────────────────────────────────────────────────────────────────
window.onload=function(){
  makeBtn("efp-metric-btns", EFP_COLS, "GPPsat", setEfpMet, "efpmet");
  makeBtn("whit-color-btns", ["IGBP","NETWORK"].concat(EFP_COLS), "IGBP", setWhitColor, "wc");
  buildSummary();
  renderIGBPbar();
  renderMap();
  renderAvail();
  renderViolin("GPPsat");
  renderWhittaker();
};
</script>
</body>
</html>')

writeLines(html, out_file)
cat("Saved:", out_file, "\n")
cat("File size:", round(file.size(out_file)/1024/1024, 2), "MB\n")

library(data.table)
library(jsonlite)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_file <- "plots/disturbance_effects/interactive_mortality_v1v2.html"
dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

# Embed plotly.js for standalone use
plotly_js <- paste(readLines("/tmp/plotly-2.27.0.min.js", warn = FALSE), collapse = "\n")

# ── Modeling sites + IGBP ──────────────────────────────────────────────────────
efp_src  <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
efp_map  <- fread(efp_src, select = c("SITE_ID", "IGBP"))[, .(IGBP = IGBP[1]), by = SITE_ID]
model_sites <- efp_map$SITE_ID
cat("Modeling sites:", length(model_sites), "\n")

# ── Site lat/lon for world map ────────────────────────────────────────────────
meta_file <- "derived_tables/site_metadata_from_BIF.csv"
meta_dt   <- fread(meta_file, select = c("SITE_ID", "LOCATION_LAT", "LOCATION_LONG"))
meta_dt   <- meta_dt[SITE_ID %in% model_sites]
meta_dt[efp_map, IGBP := i.IGBP, on = "SITE_ID"]
meta_dt[, LOCATION_LAT  := as.numeric(LOCATION_LAT)]
meta_dt[, LOCATION_LONG := as.numeric(LOCATION_LONG)]
map_list  <- lapply(seq_len(nrow(meta_dt)), function(i) {
  list(lat  = meta_dt$LOCATION_LAT[i],
       lon  = meta_dt$LOCATION_LONG[i],
       igbp = meta_dt$IGBP[i])
})
names(map_list) <- meta_dt$SITE_ID
json_map <- toJSON(map_list, auto_unbox = TRUE, na = "null", digits = 6)
cat("Map sites:", length(map_list), "\n")

# ── Helper: build site JSON from a CSV ────────────────────────────────────────
buffers <- c("100m", "200m", "300m", "400m", "500m")
col_map <- list(
  ms  = "mortality_stock_pct",
  dw  = "deadwood_mean_pct",
  ltc = "live_tree_cover_pct",
  tc  = "tree_cover_mean_pct",
  mr  = "new_mortality_rate_pct",
  mrt = "new_mortality_rate_pct_thresh",
  dg  = "new_deadwood_gain_pp",
  rl  = "relative_tree_loss_pct",
  rlt = "relative_tree_loss_pct_thresh",
  sv  = "mortality_loss_severity_pct",
  svt = "mortality_loss_severity_pct_thresh",
  tl  = "tree_loss_pp",
  tlt = "tree_loss_pp_thresh"
)

build_site_json <- function(csv_path, label) {
  dt <- fread(csv_path)
  dt <- dt[site_id %in% model_sites]
  dt[efp_map, IGBP := i.IGBP, on = .(site_id = SITE_ID)]
  dt[is.na(IGBP), IGBP := "Unknown"]
  setkey(dt, site_id, year)

  sites <- unique(dt$site_id)
  cat(label, "— sites:", length(sites), " rows:", nrow(dt), "\n")

  site_list <- lapply(sites, function(s) {
    sd <- dt[.(s)]
    buf_data <- setNames(lapply(buffers, function(b) {
      setNames(lapply(names(col_map), function(k) {
        round(sd[[paste0(col_map[[k]], "_", b)]], 2)
      }), names(col_map))
    }), buffers)
    c(list(igbp = sd$IGBP[1], years = as.integer(sd$year)), buf_data)
  })
  names(site_list) <- sites

  toJSON(site_list, auto_unbox = FALSE, na = "null", digits = 4)
}

# ── Build EFP JSON (raw + anomaly, version-independent) ───────────────────────
efp_dt <- fread(efp_src,
                select = c("SITE_ID", "YEAR",
                           "GPPsat", "NEPmax", "ETmax", "uWUE",
                           "GPPsat_anom_lag1", "NEPmax_anom_lag1",
                           "ETmax_anom_lag1",  "uWUE_anom_lag1"))
efp_dt <- efp_dt[SITE_ID %in% model_sites]
setkey(efp_dt, SITE_ID, YEAR)

efp_list <- lapply(unique(efp_dt$SITE_ID), function(s) {
  sd <- efp_dt[.(s)]
  list(
    years       = as.integer(sd$YEAR),
    GPPsat      = round(sd$GPPsat,               3),
    NEPmax      = round(sd$NEPmax,               3),
    ETmax       = round(sd$ETmax,                4),
    uWUE        = round(sd$uWUE,                 3),
    GPPsat_anom = round(sd$GPPsat_anom_lag1,     3),
    NEPmax_anom = round(sd$NEPmax_anom_lag1,     3),
    ETmax_anom  = round(sd$ETmax_anom_lag1,      3),
    uWUE_anom   = round(sd$uWUE_anom_lag1,       3)
  )
})
names(efp_list) <- unique(efp_dt$SITE_ID)
json_efp <- toJSON(efp_list, auto_unbox = FALSE, na = "null", digits = 4)
cat("EFP data built for", length(efp_list), "sites\n")

# ── Build both JSONs ──────────────────────────────────────────────────────────
json_v1 <- build_site_json("derived_tables/final_disturbance_v1_multibuffer.csv",  "v1")
json_v2 <- build_site_json("derived_tables/final_disturbance_v2-2_multibuffer.csv", "v2-2")
n_sites <- length(model_sites)

# ── HTML ──────────────────────────────────────────────────────────────────────
html <- paste0('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Forest Disturbance Explorer — v1 / v2-2</title>
<script>', plotly_js, '</script>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0D0D0D;color:#E0E0E0;font-family:Arial,sans-serif;padding:16px}
  h1{text-align:center;font-size:1.25em;margin-bottom:4px}
  .sub{text-align:center;font-size:0.82em;color:#9CA3AF;margin-bottom:14px}
  .panel{background:#111827;border-radius:8px;padding:6px;margin-bottom:14px}

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
  .tog-btn.ver-v1.active{background:#E8257A;border-color:#E8257A;color:#fff}
  .tog-btn.ver-v2.active{background:#22D4EB;border-color:#22D4EB;color:#0D0D0D}

  #trace-boxes{display:flex;flex-wrap:wrap;gap:6px 18px;max-width:900px}
  .trace-cb{display:flex;align-items:center;gap:5px;font-size:0.8em;cursor:pointer;user-select:none;white-space:nowrap}
  .trace-cb input{cursor:pointer;accent-color:#22D4EB;margin:0}
  .t-swatch{width:18px;height:4px;border-radius:2px;flex-shrink:0;display:inline-block}

  /* ── Tooltips ── */
  .has-tip{position:relative;cursor:help}
  .has-tip .tip-box{
    display:none;position:absolute;bottom:calc(100% + 8px);left:0;
    background:#1C2333;border:1px solid #4B5563;color:#E0E0E0;
    padding:8px 11px;border-radius:6px;font-size:0.78em;line-height:1.5;
    width:270px;z-index:9999;pointer-events:none;
    box-shadow:0 4px 16px rgba(0,0,0,.6);white-space:normal;font-weight:normal;
  }
  .has-tip .tip-box .tip-title{color:#22D4EB;font-weight:bold;margin-bottom:3px;display:block}
  .has-tip:hover .tip-box{display:block}
  /* keep tooltip visible when it would go off-screen right */
  .tip-right .tip-box{left:auto;right:0}
  /* buffer/version button tooltips */
  .tog-btn.has-tip .tip-box{width:220px;left:50%;transform:translateX(-50%)}

  #ver-badge{display:inline-block;padding:2px 10px;border-radius:4px;font-size:0.78em;font-weight:bold;margin-left:8px;vertical-align:middle}
</style>
</head>
<body>
<a href="index.html" style="display:inline-block;margin-bottom:10px;font-size:0.85em;background:#1F2937;border:1px solid #4B5563;border-radius:5px;padding:5px 14px;color:#22D4EB;text-decoration:none">&#8592; Back to hub</a>
<h1>Forest Disturbance &amp; Mortality Explorer
  <span id="ver-badge" style="background:#22D4EB;color:#0D0D0D">v2-2</span>
</h1>
<p class="sub">', n_sites, ' modeling sites &nbsp;|&nbsp;
  Switch product version with the buttons below &nbsp;|&nbsp;
  Click a site bar to see temporal trends</p>

<div id="controls">
  <!-- Version selector -->
  <div class="ctrl-group">
    <div class="ctrl-label">Product version</div>
    <div class="btn-row">
      <button class="tog-btn ver-v1 has-tip" data-ver="v1" onclick="setVersion(\'v1\')">v1
        <div class="tip-box"><span class="tip-title">Product v1</span>First generation deadwood model. Variables: forest, deadwood only (no uncertainty bands).</div>
      </button>
      <button class="tog-btn ver-v2 active has-tip" data-ver="v2" onclick="setVersion(\'v2\')">v2-2
        <div class="tip-box"><span class="tip-title">Product v2-2</span>Second generation deadwood model. Includes forest_std and deadwood_std uncertainty bands. Improved model architecture.</div>
      </button>
    </div>
  </div>
  <div class="vdiv"></div>
  <!-- Buffer selector -->
  <div class="ctrl-group">
    <div class="ctrl-label">Buffer radius</div>
    <div class="btn-row">
      <button class="tog-btn has-tip" data-buf="100m" onclick="setBuffer(\'100m\')">100 m
        <div class="tip-box"><span class="tip-title">100 m buffer</span>Circle of radius 100 m around the flux tower. ~314 pixels at 10 m resolution. Best for near-tower footprint.</div>
      </button>
      <button class="tog-btn has-tip" data-buf="200m" onclick="setBuffer(\'200m\')">200 m
        <div class="tip-box"><span class="tip-title">200 m buffer</span>Circle of radius 200 m. ~1,257 pixels. Captures moderate flux footprint extent.</div>
      </button>
      <button class="tog-btn has-tip" data-buf="300m" onclick="setBuffer(\'300m\')">300 m
        <div class="tip-box"><span class="tip-title">300 m buffer</span>Circle of radius 300 m. ~2,827 pixels.</div>
      </button>
      <button class="tog-btn has-tip" data-buf="400m" onclick="setBuffer(\'400m\')">400 m
        <div class="tip-box"><span class="tip-title">400 m buffer</span>Circle of radius 400 m. ~5,027 pixels.</div>
      </button>
      <button class="tog-btn active has-tip" data-buf="500m" onclick="setBuffer(\'500m\')">500 m
        <div class="tip-box"><span class="tip-title">500 m buffer</span>Circle of radius 500 m. ~7,854 pixels at 10 m resolution. Default — best match for typical EC flux footprint.</div>
      </button>
    </div>
  </div>
  <div class="vdiv"></div>
  <!-- Bar/Violin metric -->
  <div class="ctrl-group">
    <div class="ctrl-label">Bar / violin metric</div>
    <div class="btn-row" id="barmet-buttons"></div>
  </div>
  <div class="vdiv"></div>
  <!-- Map colour selector -->
  <div class="ctrl-group">
    <div class="ctrl-label">Map colour</div>
    <div class="btn-row" id="mapcol-buttons"></div>
  </div>
  <div class="vdiv"></div>
  <!-- Trace selector -->
  <div class="ctrl-group">
    <div class="ctrl-label">Time-series traces</div>
    <div id="trace-boxes"></div>
  </div>
</div>

<div class="panel"><div id="map-plot"></div></div>
<div class="panel"><div id="violin-plot"></div></div>
<div class="panel"><div id="bar-plot"></div></div>
<div class="panel"><div id="ts-plot"></div></div>
<div class="panel"><div id="efp-plot"></div></div>
<div class="panel"><div id="anom-plot"></div></div>

<script>
// ── Embedded data ─────────────────────────────────────────────────────────────
var ALL_DATA = {
  v1:  ', json_v1, ',
  v2:  ', json_v2, '
};
var EFP_DATA = ', json_efp, ';
var MAP_DATA = ', json_map, ';

// ── Theme ─────────────────────────────────────────────────────────────────────
var BG="royalblue"||"#0D0D0D",PANEL="#111827",GRID="#2A2A3A",TEXT="#E0E0E0",SUB="#9CA3AF",AXIS="#4B5563",LEG_BG="#1A1A2E";
BG="#0D0D0D";

var IGBP_COL={ENF:"#1B6B3A",EBF:"#45B045",DNF:"#2E8B8B",DBF:"#8FBC45",MF:"#5F9EA0",
  CSH:"#C4843B",OSH:"#D4B483",WSA:"#A9A93A",SAV:"#D4C23A",WET:"#4682B4",
  CRO:"#CC4444",URB:"#888888",Unknown:"#666666"};

var VER_COL={v1:"#E8257A", v2:"#22D4EB"};

var TRACE_DEFS=[
  {key:"ms",  label:"Mortality stock (%)",         color:"#FFA500",yaxis:"y", dash:null,      on:true,
   desc:"<span class=tip-title>Mortality stock</span>What % of standing tree cover is currently dead.<br><b>Formula:</b> deadwood / tree_cover × 100.<br><b>NA</b> when tree cover &lt; 10% (sparse sites excluded)."},
  {key:"dw",  label:"Deadwood standing (%)",        color:"#8FBC45",yaxis:"y", dash:null,      on:true,
   desc:"<span class=tip-title>Deadwood standing</span>Absolute fraction (%) of total ground area covered by standing dead wood. Raw model output — not normalized by tree cover."},
  {key:"tc",  label:"Tree cover total (%)",         color:"#22D4EB",yaxis:"y2",dash:null,      on:true,
   desc:"<span class=tip-title>Total tree cover</span>All canopy cover (alive + dead) as % of ground area within the buffer. Raw model output."},
  {key:"ltc", label:"Live tree cover (%)",          color:"#45D4B0",yaxis:"y2",dash:null,      on:false,
   desc:"<span class=tip-title>Live tree cover</span>Estimated healthy canopy only.<br><b>Formula:</b> tree_cover − deadwood."},
  {key:"mr",  label:"New mort. rate, raw (%)",      color:"#E8257A",yaxis:"y", dash:"dot",     on:true,
   desc:"<span class=tip-title>New mortality rate (raw)</span>New dead wood formed since the prior year, normalized by prior tree cover.<br><b>Formula:</b> max(dw_t − dw_{t-1}, 0) / tree_cover_{t-1} × 100.<br>All positive pixel-level changes counted — detects outbreak events."},
  {key:"mrt", label:"New mort. rate, thresh (%)",   color:"#FF99CC",yaxis:"y", dash:"dot",     on:false,
   desc:"<span class=tip-title>New mortality rate (thresholded)</span>Same as raw new mortality rate but only pixels where deadwood increased by <b>≥ 20 pp</b> contribute. Filters sensor noise; isolates large unambiguous die-off events."},
  {key:"rl",  label:"Rel. tree loss, raw (%)",      color:"#DC143C",yaxis:"y", dash:"dash",    on:false,
   desc:"<span class=tip-title>Relative tree loss (raw)</span>Tree cover lost since prior year as % of prior cover.<br><b>Formula:</b> max(tc_{t-1} − tc_t, 0) / tc_{t-1} × 100.<br>Captures fallen or harvested trees — distinct from dead-but-standing."},
  {key:"rlt", label:"Rel. tree loss, thresh (%)",   color:"#FF7777",yaxis:"y", dash:"dash",    on:false,
   desc:"<span class=tip-title>Relative tree loss (thresholded)</span>Same as raw tree loss but only pixels with <b>≥ 20 pp</b> cover decrease counted."},
  {key:"sv",  label:"Severity raw (%)",             color:"#FF6200",yaxis:"y", dash:"dashdot", on:false,
   desc:"<span class=tip-title>Combined severity (raw)</span>Combines new deadwood formation AND tree cover loss into one index.<br><b>Formula:</b> (new_dw_gain + tree_loss) / tree_cover_{t-1} × 100.<br>Best single disturbance predictor."},
  {key:"svt", label:"Severity thresh (%)",          color:"#FFAA66",yaxis:"y", dash:"dashdot", on:false,
   desc:"<span class=tip-title>Combined severity (thresholded)</span>Same as raw severity but using thresholded pixel values (<b>≥ 20 pp</b> changes only)."}
];

// ── State ─────────────────────────────────────────────────────────────────────
var curVer="v2", curBuf="500m", curSite=null, barWired=false, curBarMetric="ms";
var curMapMetric="igbp", mapWired=false;

var MAP_METRIC_DEFS=[
  {key:"igbp", label:"IGBP"},
  {key:"ms",   label:"Mort. stock"},
  {key:"mr",   label:"New mort. rate"},
  {key:"mrt",  label:"Mort. rate thresh"},
  {key:"sv",   label:"Severity raw"},
  {key:"svt",  label:"Severity thresh"},
  {key:"rl",   label:"Rel. tree loss"},
  {key:"rlt",  label:"Tree loss thresh"},
];

var BAR_METRIC_DEFS=[
  {key:"ms",  label:"Mort. stock (%)"},
  {key:"mr",  label:"New mort. rate (%)"},
  {key:"mrt", label:"New mort. rate thresh (%)"},
  {key:"sv",  label:"Severity raw (%)"},
  {key:"svt", label:"Severity thresh (%)"},
  {key:"rl",  label:"Rel. tree loss (%)"},
  {key:"rlt", label:"Tree loss thresh (%)"},
  {key:"dw",  label:"Deadwood (%)"},
];

function siteData(){ return ALL_DATA[curVer]; }

// ── Helpers ───────────────────────────────────────────────────────────────────
function median(arr){
  var f=arr.filter(v=>v!=null&&isFinite(v)).sort((a,b)=>a-b);
  if(!f.length)return 0;
  var m=Math.floor(f.length/2);
  return f.length%2?f[m]:(f[m-1]+f[m])/2;
}
function peakVal(site,buf,key){
  var vals=(siteData()[site][buf][key]||[]).filter(v=>v!=null);
  return vals.length?Math.max(...vals):0;
}
function peakMort(site,buf){ return peakVal(site,buf,curBarMetric); }
function igbpCol(ig){return IGBP_COL[ig]||"#888888";}
function activeKeys(){
  return TRACE_DEFS.filter(td=>{var cb=document.getElementById("cb-"+td.key);return cb&&cb.checked;}).map(td=>td.key);
}

// ── World map ─────────────────────────────────────────────────────────────────
function renderMap(buf){
  var vc=VER_COL[curVer];
  var sites=Object.keys(MAP_DATA);
  var traces=[];

  if(curMapMetric==="igbp"){
    var groups={};
    sites.forEach(function(s){
      var m=MAP_DATA[s]; if(!m||m.lat==null) return;
      var ig=m.igbp||"Unknown";
      if(!groups[ig]) groups[ig]={lats:[],lons:[],ids:[]};
      groups[ig].lats.push(m.lat);
      groups[ig].lons.push(m.lon);
      groups[ig].ids.push(s);
    });
    Object.keys(groups).sort().forEach(function(ig){
      var g=groups[ig];
      traces.push({
        type:"scattergeo", name:ig,
        lat:g.lats, lon:g.lons,
        customdata:g.ids,
        mode:"markers",
        marker:{color:igbpCol(ig),size:8,opacity:0.88,
                line:{width:0.5,color:"#111"}},
        hovertemplate:"<b>%{customdata}</b><br>IGBP: " + ig + "<extra></extra>",
        showlegend:true
      });
    });
  } else {
    var lats=[],lons=[],ids=[],vals=[],igbps=[];
    sites.forEach(function(s){
      var m=MAP_DATA[s]; if(!m||m.lat==null) return;
      if(!siteData()[s]) return;
      var v=peakVal(s,buf,curMapMetric);
      lats.push(m.lat); lons.push(m.lon);
      ids.push(s); vals.push(v); igbps.push(m.igbp||"Unknown");
    });
    var mLabel=MAP_METRIC_DEFS.find(function(d){return d.key===curMapMetric;}).label;
    traces.push({
      type:"scattergeo", name:mLabel,
      lat:lats, lon:lons, customdata:ids,
      mode:"markers",
      text:ids.map(function(s,i){
        return "<b>"+s+"</b><br>IGBP: "+igbps[i]+"<br>"+mLabel+": "+(vals[i]!=null?vals[i].toFixed(2):"NA")+"%";
      }),
      hoverinfo:"text",
      marker:{
        color:vals, colorscale:[[0,"#FFFFB2"],[0.25,"#FEB24C"],[0.5,"#F03B20"],[1,"#BD0026"]], size:9, opacity:0.9,
        showscale:true,
        colorbar:{title:{text:mLabel+"<br>(%)",font:{color:SUB,size:10}},
                  thickness:14,len:0.75,x:1.01,
                  tickfont:{color:TEXT,size:9}},
        line:{width:0.5,color:"#111"}
      },
      showlegend:false
    });
  }

  var metLabel=curMapMetric==="igbp"?"IGBP":
    MAP_METRIC_DEFS.find(function(d){return d.key===curMapMetric;}).label;

  Plotly.react("map-plot",traces,{
    title:{text:"Site distribution  ["+curVer.toUpperCase()+"  |  "+buf+"]  — colour: "+metLabel+"  — click a site to explore",
           font:{size:13,color:vc}},
    geo:{
      scope:"world",
      projection:{type:"natural earth"},
      showland:true,  landcolor:"#1A2535",
      showocean:true, oceancolor:"#0D1621",
      showlakes:true, lakecolor:"#0D1621",
      showcountries:true, countrycolor:"#2A2A3A",
      showcoastlines:true, coastlinecolor:"#374151",
      bgcolor:PANEL
    },
    paper_bgcolor:BG, font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,
            font:{color:TEXT,size:10},x:1.02,y:1},
    margin:{l:0,r:0,t:46,b:10}, height:440
  },{responsive:true});

  if(!mapWired){
    mapWired=true;
    document.getElementById("map-plot").on("plotly_click",function(ev){
      var s=ev.points[0].customdata;
      if(!s||!siteData()[s]) return;
      curSite=s;
      renderTS(s,curBuf); renderEFP(s); renderAnom(s);
    });
  }
}

function buildMapColButtons(){
  var box=document.getElementById("mapcol-buttons");
  MAP_METRIC_DEFS.forEach(function(d){
    var btn=document.createElement("button");
    btn.className="tog-btn"+(d.key==="igbp"?" active":"");
    btn.dataset.mapcol=d.key;
    btn.textContent=d.label;
    btn.onclick=function(){
      curMapMetric=d.key;
      document.querySelectorAll(".tog-btn[data-mapcol]").forEach(function(b){
        b.classList.toggle("active",b.dataset.mapcol===d.key);
      });
      renderMap(curBuf);
    };
    box.appendChild(btn);
  });
}

// ── Violin ────────────────────────────────────────────────────────────────────
function renderViolin(buf){
  var groups={};
  Object.keys(siteData()).forEach(function(site){
    var ig=siteData()[site].igbp||"Unknown";
    if(!groups[ig])groups[ig]=[];
    groups[ig].push(peakMort(site,buf));
  });
  var igbps=Object.keys(groups).sort((a,b)=>median(groups[a])-median(groups[b]));
  var traces=igbps.map(function(ig){
    var col=igbpCol(ig),ys=groups[ig];
    return{type:"violin",name:ig,y:ys,x:ys.map(()=>ig),
      box:{visible:true},points:"all",jitter:0.3,pointpos:0,
      marker:{size:5,opacity:0.75,color:col},line:{color:col},
      fillcolor:col+"55",showlegend:false,
      hovertemplate:"<b>"+ig+"</b><br>Peak mort. stock: %{y:.1f}%<extra></extra>"};
  });
  var vc=VER_COL[curVer];
  Plotly.react("violin-plot",traces,{
    title:{text:"Sites by peak "+BAR_METRIC_DEFS.find(function(m){return m.key===curBarMetric;}).label+"  ["+curVer.toUpperCase()+" &nbsp;|&nbsp; "+buf+" buffer]",
           font:{size:14,color:vc}},
    xaxis:{gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT}},
    yaxis:{title:"Peak "+BAR_METRIC_DEFS.find(function(m){return m.key===curBarMetric;}).label,gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:60,r:20,t:50,b:40},height:320
  },{responsive:true});
}

// ── Bar ───────────────────────────────────────────────────────────────────────
function renderBar(buf){
  var bmLabel=BAR_METRIC_DEFS.find(function(m){return m.key===curBarMetric;}).label;
  var rows=Object.keys(siteData()).map(function(site){
    return{site:site,igbp:siteData()[site].igbp||"Unknown",peak:peakMort(site,buf)};
  }).sort((a,b)=>b.peak-a.peak);
  var ordered=rows.map(r=>r.site);
  var groups={};
  rows.forEach(function(r){
    var ig=r.igbp;
    if(!groups[ig])groups[ig]={x:[],y:[]};
    groups[ig].x.push(r.site);
    groups[ig].y.push(r.peak>0?r.peak:null);
  });
  var traces=Object.keys(groups).map(function(ig){
    var col=igbpCol(ig);
    return{type:"bar",name:ig,x:groups[ig].x,y:groups[ig].y,marker:{color:col},
      hovertemplate:"<b>%{x}</b><br>IGBP: "+ig+"<br>Peak "+bmLabel+": %{y:.1f}%<extra></extra>"};
  });
  var vc=VER_COL[curVer];
  Plotly.react("bar-plot",traces,{
    title:{text:"Sites sorted by peak "+BAR_METRIC_DEFS.find(function(m){return m.key===curBarMetric;}).label+"  ["+curVer.toUpperCase()+" &nbsp;|&nbsp; "+buf+"]  — click a bar to see trends",
           font:{size:13,color:vc}},
    barmode:"overlay",
    xaxis:{categoryorder:"array",categoryarray:ordered,tickangle:-60,
           tickfont:{size:7,color:SUB},gridcolor:GRID,linecolor:AXIS},
    yaxis:{title:"Peak "+BAR_METRIC_DEFS.find(function(m){return m.key===curBarMetric;}).label,gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,font:{color:TEXT,size:10}},
    margin:{l:60,r:20,t:50,b:90},height:380
  },{responsive:true});

  if(!barWired){
    barWired=true;
    document.getElementById("bar-plot").on("plotly_click",function(ev){
      curSite=ev.points[0].x;
      renderTS(curSite,curBuf);
      renderEFP(curSite);
      renderAnom(curSite);
    });
  }
}

// ── EFP raw panel ─────────────────────────────────────────────────────────────
function renderEFP(site){
  if(!site||!EFP_DATA[site])return;
  var e=EFP_DATA[site];
  var vc=VER_COL[curVer];
  var traces=[
    {x:e.years,y:e.GPPsat,type:"scatter",mode:"lines+markers",name:"GPPsat (μmol m⁻² s⁻¹)",
     yaxis:"y", line:{color:"#4A90D9",width:2},marker:{color:"#4A90D9",size:6},
     hovertemplate:"GPPsat: %{y:.2f}<br>Year: %{x}<extra></extra>"},
    {x:e.years,y:e.NEPmax,type:"scatter",mode:"lines+markers",name:"NEPmax (μmol m⁻² s⁻¹)",
     yaxis:"y", line:{color:"#3DBDAA",width:2},marker:{color:"#3DBDAA",size:6},
     hovertemplate:"NEPmax: %{y:.2f}<br>Year: %{x}<extra></extra>"},
    {x:e.years,y:e.ETmax, type:"scatter",mode:"lines+markers",name:"ETmax (mm d⁻¹)",
     yaxis:"y2",line:{color:"#D4A017",width:2,dash:"dot"},marker:{color:"#D4A017",size:6},
     hovertemplate:"ETmax: %{y:.4f}<br>Year: %{x}<extra></extra>"},
    {x:e.years,y:e.uWUE,  type:"scatter",mode:"lines+markers",name:"uWUE (g C mm⁻¹)",
     yaxis:"y2",line:{color:"#9B59B6",width:2,dash:"dash"},marker:{color:"#9B59B6",size:6},
     hovertemplate:"uWUE: %{y:.3f}<br>Year: %{x}<extra></extra>"}
  ];
  Plotly.react("efp-plot",traces,{
    title:{text:"EFP raw values  —  "+site,font:{size:13,color:vc}},
    xaxis:{title:"Year",gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB},dtick:1},
    yaxis:{title:"GPPsat / NEPmax (μmol m⁻² s⁻¹)",side:"left",
           gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    yaxis2:{title:"ETmax (mm d⁻¹) / uWUE (g C mm⁻¹)",side:"right",
            overlaying:"y",showgrid:false,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,font:{color:TEXT,size:10},
            orientation:"h",x:0,y:-0.32},
    margin:{l:65,r:75,t:46,b:110},height:380
  },{responsive:true});
}

// ── EFP anomaly panel ─────────────────────────────────────────────────────────
function renderAnom(site){
  if(!site||!EFP_DATA[site])return;
  var e=EFP_DATA[site];
  var vc=VER_COL[curVer];
  var traces=[
    {x:e.years,y:e.GPPsat_anom,type:"scatter",mode:"lines+markers",name:"GPPsat anomaly",
     line:{color:"#4A90D9",width:2},marker:{color:"#4A90D9",size:6},
     hovertemplate:"GPPsat anom: %{y:.3f}<br>Year: %{x}<extra></extra>"},
    {x:e.years,y:e.NEPmax_anom,type:"scatter",mode:"lines+markers",name:"NEPmax anomaly",
     line:{color:"#3DBDAA",width:2,dash:"dot"},marker:{color:"#3DBDAA",size:6},
     hovertemplate:"NEPmax anom: %{y:.3f}<br>Year: %{x}<extra></extra>"},
    {x:e.years,y:e.ETmax_anom, type:"scatter",mode:"lines+markers",name:"ETmax anomaly",
     line:{color:"#D4A017",width:2,dash:"dash"},marker:{color:"#D4A017",size:6},
     hovertemplate:"ETmax anom: %{y:.3f}<br>Year: %{x}<extra></extra>"},
    {x:e.years,y:e.uWUE_anom,  type:"scatter",mode:"lines+markers",name:"uWUE anomaly",
     line:{color:"#9B59B6",width:2,dash:"dashdot"},marker:{color:"#9B59B6",size:6},
     hovertemplate:"uWUE anom: %{y:.3f}<br>Year: %{x}<extra></extra>"},
    // zero reference line
    {x:e.years,y:e.years.map(()=>0),type:"scatter",mode:"lines",name:"zero",
     line:{color:"#4B5563",width:1,dash:"dot"},showlegend:false,
     hoverinfo:"skip"}
  ];
  Plotly.react("anom-plot",traces,{
    title:{text:"EFP anomalies (z-score, lag-1)  —  "+site,font:{size:13,color:vc}},
    xaxis:{title:"Year",gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB},dtick:1},
    yaxis:{title:"Anomaly (z-score)",gridcolor:GRID,linecolor:AXIS,
           zeroline:true,zerolinecolor:"#4B5563",zerolinewidth:1,
           tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,font:{color:TEXT,size:10},
            orientation:"h",x:0,y:-0.32},
    margin:{l:65,r:30,t:46,b:110},height:360
  },{responsive:true});
}

// ── Time series ───────────────────────────────────────────────────────────────
function renderTS(site,buf){
  if(!site||!siteData()[site])return;
  curSite=site;
  var d=siteData()[site],bd=d[buf],yrs=d.years;
  var keys=activeKeys();
  var vc=VER_COL[curVer];
  var traces=TRACE_DEFS.filter(td=>keys.includes(td.key)).map(function(td){
    return{x:yrs,y:bd[td.key],type:"scatter",mode:"lines+markers",
      name:td.label,yaxis:td.yaxis,
      line:{color:td.color,width:2,dash:td.dash||undefined},
      marker:{color:td.color,size:6},connectgaps:false,
      hovertemplate:"%{fullData.name}: %{y:.2f}<br>Year: %{x}<extra></extra>"};
  });
  Plotly.react("ts-plot",traces,{
    title:{text:"Temporal trends  —  "+site+"   (IGBP: "+d.igbp+",  "+curVer.toUpperCase()+",  "+buf+")",
           font:{size:13,color:vc}},
    xaxis:{title:"Year",gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB},dtick:1},
    yaxis:{title:"Deadwood / Mortality (%)",side:"left",gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    yaxis2:{title:"Tree cover (%)",side:"right",overlaying:"y",showgrid:false,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,font:{color:TEXT,size:10},orientation:"h",x:0,y:-0.35},
    margin:{l:65,r:75,t:52,b:130},height:460
  },{responsive:true});
}

// ── Checkboxes ────────────────────────────────────────────────────────────────
function buildCheckboxes(){
  var box=document.getElementById("trace-boxes");
  TRACE_DEFS.forEach(function(td){
    var lbl=document.createElement("label");
    lbl.className="trace-cb has-tip";

    var cb=document.createElement("input");cb.type="checkbox";cb.id="cb-"+td.key;cb.checked=td.on;
    cb.onchange=function(){if(curSite)renderTS(curSite,curBuf);};

    var sw=document.createElement("span");sw.className="t-swatch";sw.style.background=td.color;
    if(td.dash==="dot"){sw.style.backgroundImage="repeating-linear-gradient(to right,"+td.color+" 0,"+td.color+" 4px,transparent 4px,transparent 7px)";sw.style.background="none";}
    else if(td.dash==="dash"){sw.style.backgroundImage="repeating-linear-gradient(to right,"+td.color+" 0,"+td.color+" 7px,transparent 7px,transparent 11px)";sw.style.background="none";}
    else if(td.dash==="dashdot"){sw.style.backgroundImage="repeating-linear-gradient(to right,"+td.color+" 0,"+td.color+" 6px,transparent 6px,transparent 9px,"+td.color+" 9px,"+td.color+" 11px,transparent 11px,transparent 14px)";sw.style.background="none";}

    var tip=document.createElement("div");tip.className="tip-box";tip.innerHTML=td.desc;

    lbl.appendChild(cb);lbl.appendChild(sw);lbl.appendChild(document.createTextNode(" "+td.label));
    lbl.appendChild(tip);
    box.appendChild(lbl);
  });
}

// ── Bar metric selector ───────────────────────────────────────────────────────
function buildBarMetricButtons(){
  var box=document.getElementById("barmet-buttons");
  BAR_METRIC_DEFS.forEach(function(m){
    var btn=document.createElement("button");
    btn.className="tog-btn"+(m.key==="ms"?" active":"");
    btn.dataset.barmet=m.key;
    btn.textContent=m.label;
    btn.onclick=function(){setBarMetric(m.key);};
    box.appendChild(btn);
  });
}
function setBarMetric(key){
  curBarMetric=key;
  document.querySelectorAll(".tog-btn[data-barmet]").forEach(function(b){
    b.classList.toggle("active",b.dataset.barmet===key);
  });
  renderViolin(curBuf);
  renderBar(curBuf);
}

// ── Version toggle ────────────────────────────────────────────────────────────
function setVersion(ver){
  curVer=ver;
  var badge=document.getElementById("ver-badge");
  badge.textContent=ver==="v1"?"v1":"v2-2";
  badge.style.background=VER_COL[ver];
  badge.style.color=ver==="v1"?"#fff":"#0D0D0D";
  document.querySelectorAll(".tog-btn[data-ver]").forEach(function(b){
    b.classList.toggle("active",b.dataset.ver===ver);
  });
  renderMap(curBuf);
  renderViolin(curBuf);
  renderBar(curBuf);
  var site=curSite&&siteData()[curSite]?curSite:topSite();
  curSite=site;
  renderTS(site,curBuf);
  renderEFP(site);
  renderAnom(site);
}

// ── Buffer toggle ─────────────────────────────────────────────────────────────
function setBuffer(buf){
  curBuf=buf;
  document.querySelectorAll(".tog-btn[data-buf]").forEach(function(b){
    b.classList.toggle("active",b.dataset.buf===buf);
  });
  renderMap(buf);renderViolin(buf);renderBar(buf);
  if(curSite){renderTS(curSite,buf);renderEFP(curSite);renderAnom(curSite);}
}

// ── Init ──────────────────────────────────────────────────────────────────────
function topSite(){
  var sites=Object.keys(siteData());
  return sites.reduce(function(best,s){return peakMort(s,curBuf)>peakMort(best,curBuf)?s:best;},sites[0]);
}

window.onload=function(){
  buildCheckboxes();
  buildBarMetricButtons();
  buildMapColButtons();
  renderMap(curBuf);
  renderViolin(curBuf);renderBar(curBuf);
  curSite=topSite();
  renderTS(curSite,curBuf);
  renderEFP(curSite);
  renderAnom(curSite);
};
</script>
</body>
</html>')

writeLines(html, out_file)
cat("Saved:", out_file, "\n")
cat("File size:", round(file.size(out_file)/1024/1024, 2), "MB\n")

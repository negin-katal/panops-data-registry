library(data.table)
library(jsonlite)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_file <- "plots/disturbance_effects/interactive_mortality_v2.html"
dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

# Embed plotly.js for standalone / localhost use
plotly_js <- readLines("/tmp/plotly-2.27.0.min.js", warn = FALSE)
plotly_js  <- paste(plotly_js, collapse = "\n")

# ── Load data ──────────────────────────────────────────────────────────────────
dt <- fread("derived_tables/final_disturbance_v2-2_multibuffer.csv")
cat("Loaded:", nrow(dt), "rows,", uniqueN(dt$site_id), "sites\n")

# IGBP + modeling site filter — keep only the 184 EFP modeling sites
efp_src <- "derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
efp_map <- fread(efp_src, select = c("SITE_ID", "IGBP"))[, .(IGBP = IGBP[1]), by = SITE_ID]
model_sites <- efp_map$SITE_ID
cat("Modeling sites:", length(model_sites), "\n")

dt <- dt[site_id %in% model_sites]
cat("After filter:", nrow(dt), "rows,", uniqueN(dt$site_id), "sites\n")

dt[efp_map, IGBP := i.IGBP, on = .(site_id = SITE_ID)]
dt[is.na(IGBP), IGBP := "Unknown"]
setkey(dt, site_id, year)

# ── Build per-site JS data object ──────────────────────────────────────────────
buffers  <- c("100m", "200m", "300m", "400m", "500m")
buf_keys <- c("ms","dw","ltc","tc","mr","mrt","dg","rl","rlt","sv","svt","tl","tlt")

# column → short key mapping (per buffer suffix)
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

sites <- unique(dt$site_id)
cat("Building site data for", length(sites), "sites...\n")

site_list <- lapply(sites, function(s) {
  sd <- dt[.(s)]

  buf_data <- setNames(lapply(buffers, function(b) {
    setNames(lapply(names(col_map), function(k) {
      col <- paste0(col_map[[k]], "_", b)
      v   <- sd[[col]]
      round(v, 2)   # NAs stay as NA → become JSON null
    }), names(col_map))
  }), buffers)

  c(list(igbp = sd$IGBP[1], years = as.integer(sd$year)), buf_data)
})
names(site_list) <- sites

site_json <- toJSON(site_list, auto_unbox = FALSE, na = "null", digits = 4)
n_sites   <- length(sites)
cat("JSON built. Sites:", n_sites, "\n")

# ── HTML template ──────────────────────────────────────────────────────────────
html <- paste0('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Forest Disturbance Explorer v2-2</title>
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

  .buf-btns{display:flex;gap:5px;flex-wrap:wrap}
  .buf-btn{background:#1F2937;color:#9CA3AF;border:1px solid #4B5563;border-radius:5px;
           padding:5px 13px;cursor:pointer;font-size:0.82em;transition:all .15s}
  .buf-btn:hover{background:#374151}
  .buf-btn.active{background:#22D4EB;color:#0D0D0D;border-color:#22D4EB;font-weight:bold}

  #trace-boxes{display:flex;flex-wrap:wrap;gap:6px 18px;max-width:900px}
  .trace-cb{display:flex;align-items:center;gap:5px;font-size:0.8em;cursor:pointer;user-select:none;white-space:nowrap}
  .trace-cb input{cursor:pointer;accent-color:#22D4EB;margin:0}
  .t-swatch{width:18px;height:4px;border-radius:2px;flex-shrink:0;display:inline-block}
</style>
</head>
<body>
<h1>Forest Disturbance &amp; Mortality Explorer &nbsp;<small style="font-size:.7em;color:#9CA3AF;font-weight:normal">(deadwood v2-2)</small></h1>
<p class="sub">', n_sites, ' sites &nbsp;|&nbsp;
  Use the buffer buttons to change spatial scale &nbsp;|&nbsp;
  Toggle traces below to customise the time series &nbsp;|&nbsp;
  Click any site bar to see its temporal trends</p>

<div id="controls">
  <div class="ctrl-group">
    <div class="ctrl-label">Buffer radius</div>
    <div class="buf-btns">
      <button class="buf-btn" data-buf="100m" onclick="setBuffer(\'100m\')">100 m</button>
      <button class="buf-btn" data-buf="200m" onclick="setBuffer(\'200m\')">200 m</button>
      <button class="buf-btn" data-buf="300m" onclick="setBuffer(\'300m\')">300 m</button>
      <button class="buf-btn" data-buf="400m" onclick="setBuffer(\'400m\')">400 m</button>
      <button class="buf-btn active" data-buf="500m" onclick="setBuffer(\'500m\')">500 m</button>
    </div>
  </div>
  <div class="vdiv"></div>
  <div class="ctrl-group">
    <div class="ctrl-label">Time-series traces</div>
    <div id="trace-boxes"></div>
  </div>
</div>

<div class="panel"><div id="violin-plot"></div></div>
<div class="panel"><div id="bar-plot"></div></div>
<div class="panel"><div id="ts-plot"></div></div>

<script>
// ── Data ─────────────────────────────────────────────────────────────────────
var siteData = ', site_json, ';

// ── Theme ────────────────────────────────────────────────────────────────────
var BG      = "#0D0D0D";
var PANEL   = "#111827";
var GRID    = "#2A2A3A";
var TEXT    = "#E0E0E0";
var SUB     = "#9CA3AF";
var AXIS    = "#4B5563";
var LEG_BG  = "#1A1A2E";

var IGBP_COL = {
  ENF:"#1B6B3A", EBF:"#45B045", DNF:"#2E8B8B", DBF:"#8FBC45",
  MF:"#5F9EA0",  CSH:"#C4843B", OSH:"#D4B483", WSA:"#A9A93A",
  SAV:"#D4C23A", WET:"#4682B4", CRO:"#CC4444", URB:"#888888",
  Unknown:"#666666"
};

// trace definitions: key matches siteData[site][buf][key]
var TRACE_DEFS = [
  {key:"ms",  label:"Mortality stock (%)",           color:"#FFA500", yaxis:"y",  dash:null,       on:true },
  {key:"dw",  label:"Deadwood standing (%)",         color:"#8FBC45", yaxis:"y",  dash:null,       on:true },
  {key:"tc",  label:"Tree cover total (%)",          color:"#22D4EB", yaxis:"y2", dash:null,       on:true },
  {key:"ltc", label:"Live tree cover (%)",           color:"#45D4B0", yaxis:"y2", dash:null,       on:false},
  {key:"mr",  label:"New mort. rate, raw (%)",       color:"#E8257A", yaxis:"y",  dash:"dot",      on:true },
  {key:"mrt", label:"New mort. rate, thresh (%)",    color:"#FF99CC", yaxis:"y",  dash:"dot",      on:false},
  {key:"rl",  label:"Rel. tree loss, raw (%)",       color:"#DC143C", yaxis:"y",  dash:"dash",     on:false},
  {key:"rlt", label:"Rel. tree loss, thresh (%)",    color:"#FF7777", yaxis:"y",  dash:"dash",     on:false},
  {key:"sv",  label:"Severity raw (%)",              color:"#FF6200", yaxis:"y",  dash:"dashdot",  on:false},
  {key:"svt", label:"Severity thresh (%)",           color:"#FFAA66", yaxis:"y",  dash:"dashdot",  on:false}
];

// ── State ────────────────────────────────────────────────────────────────────
var curSite   = null;
var curBuf    = "500m";
var barWired  = false;

// ── Helpers ──────────────────────────────────────────────────────────────────
function median(arr){
  var f=arr.filter(v=>v!=null&&isFinite(v)).sort((a,b)=>a-b);
  if(!f.length)return 0;
  var m=Math.floor(f.length/2);
  return f.length%2?f[m]:(f[m-1]+f[m])/2;
}

function peakMort(site,buf){
  var ms=siteData[site][buf].ms.filter(v=>v!=null);
  return ms.length?Math.max(...ms):0;
}

function igbpCol(ig){ return IGBP_COL[ig]||"#888888"; }

function activeKeys(){
  return TRACE_DEFS.filter(td=>{
    var cb=document.getElementById("cb-"+td.key);
    return cb&&cb.checked;
  }).map(td=>td.key);
}

// ── Violin ───────────────────────────────────────────────────────────────────
function renderViolin(buf){
  var groups={};
  Object.keys(siteData).forEach(function(site){
    var ig=siteData[site].igbp||"Unknown";
    if(!groups[ig])groups[ig]=[];
    groups[ig].push(peakMort(site,buf));
  });
  var igbps=Object.keys(groups).sort((a,b)=>median(groups[a])-median(groups[b]));
  var traces=igbps.map(function(ig){
    var col=igbpCol(ig), ys=groups[ig];
    return{type:"violin",name:ig,y:ys,x:ys.map(()=>ig),
      box:{visible:true},points:"all",jitter:0.3,pointpos:0,
      marker:{size:5,opacity:0.75,color:col},line:{color:col},
      fillcolor:col+"55",showlegend:false,
      hovertemplate:"<b>"+ig+"</b><br>Peak mort. stock: %{y:.1f}%<extra></extra>"};
  });
  var layout={
    title:{text:"Peak mortality stock by IGBP  [buffer: "+buf+"]",font:{size:14,color:TEXT}},
    xaxis:{gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT}},
    yaxis:{title:"Peak mortality stock (%)",gridcolor:GRID,linecolor:AXIS,
           tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:60,r:20,t:50,b:40},height:320
  };
  Plotly.react("violin-plot",traces,layout,{responsive:true});
}

// ── Bar ──────────────────────────────────────────────────────────────────────
function renderBar(buf){
  var rows=Object.keys(siteData).map(function(site){
    return{site:site,igbp:siteData[site].igbp||"Unknown",peak:peakMort(site,buf)};
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
    return{type:"bar",name:ig,x:groups[ig].x,y:groups[ig].y,
      marker:{color:col},
      hovertemplate:"<b>%{x}</b><br>IGBP: "+ig+"<br>Peak mort. stock: %{y:.1f}%<extra></extra>"};
  });

  var layout={
    title:{text:"Sites sorted by peak mortality stock  ["+buf+"]  — click a bar to see trends",
           font:{size:13,color:TEXT}},
    barmode:"overlay",
    xaxis:{categoryorder:"array",categoryarray:ordered,tickangle:-60,
           tickfont:{size:7,color:SUB},gridcolor:GRID,linecolor:AXIS},
    yaxis:{title:"Peak mortality stock (%)",gridcolor:GRID,linecolor:AXIS,
           tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,font:{color:TEXT,size:10}},
    margin:{l:60,r:20,t:50,b:90},height:380
  };
  Plotly.react("bar-plot",traces,layout,{responsive:true});

  // Wire click once (survives react())
  if(!barWired){
    barWired=true;
    document.getElementById("bar-plot").on("plotly_click",function(ev){
      curSite=ev.points[0].x;
      renderTS(curSite,curBuf);
    });
  }
}

// ── Time series ──────────────────────────────────────────────────────────────
function renderTS(site,buf){
  if(!site||!siteData[site])return;
  curSite=site;
  var d=siteData[site], bd=d[buf], yrs=d.years;
  var keys=activeKeys();

  var traces=TRACE_DEFS.filter(td=>keys.includes(td.key)).map(function(td){
    return{
      x:yrs, y:bd[td.key],
      type:"scatter",mode:"lines+markers",
      name:td.label, yaxis:td.yaxis,
      line:{color:td.color,width:2,dash:td.dash||undefined},
      marker:{color:td.color,size:6},
      connectgaps:false,
      hovertemplate:"%{fullData.name}: %{y:.2f}<br>Year: %{x}<extra></extra>"
    };
  });

  var layout={
    title:{text:"Temporal trends  —  "+site+"   (IGBP: "+d.igbp+",  buffer: "+buf+")",
           font:{size:13,color:TEXT}},
    xaxis:{title:"Year",gridcolor:GRID,linecolor:AXIS,
           tickfont:{color:TEXT},titlefont:{color:SUB},dtick:1},
    yaxis:{title:"Deadwood / Mortality (%)",side:"left",
           gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    yaxis2:{title:"Tree cover (%)",side:"right",overlaying:"y",showgrid:false,
            linecolor:AXIS,tickfont:{color:TEXT},titlefont:{color:SUB}},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    legend:{bgcolor:LEG_BG,bordercolor:AXIS,borderwidth:1,
            font:{color:TEXT,size:10},orientation:"h",x:0,y:-0.35},
    margin:{l:65,r:75,t:52,b:130},height:460
  };
  Plotly.react("ts-plot",traces,layout,{responsive:true});
}

// ── Checkboxes ───────────────────────────────────────────────────────────────
function buildCheckboxes(){
  var box=document.getElementById("trace-boxes");
  TRACE_DEFS.forEach(function(td){
    var lbl=document.createElement("label");
    lbl.className="trace-cb";
    var cb=document.createElement("input");
    cb.type="checkbox"; cb.id="cb-"+td.key; cb.checked=td.on;
    cb.onchange=function(){if(curSite)renderTS(curSite,curBuf);};
    var sw=document.createElement("span");
    sw.className="t-swatch";
    sw.style.background=td.color;
    if(td.dash==="dot"){
      sw.style.backgroundImage="repeating-linear-gradient(to right,"+td.color+" 0,"+td.color+" 4px,transparent 4px,transparent 7px)";
      sw.style.background="none";
    }else if(td.dash==="dash"){
      sw.style.backgroundImage="repeating-linear-gradient(to right,"+td.color+" 0,"+td.color+" 7px,transparent 7px,transparent 11px)";
      sw.style.background="none";
    }else if(td.dash==="dashdot"){
      sw.style.backgroundImage="repeating-linear-gradient(to right,"+td.color+" 0,"+td.color+" 6px,transparent 6px,transparent 9px,"+td.color+" 9px,"+td.color+" 11px,transparent 11px,transparent 14px)";
      sw.style.background="none";
    }
    lbl.appendChild(cb);
    lbl.appendChild(sw);
    lbl.appendChild(document.createTextNode(" "+td.label));
    box.appendChild(lbl);
  });
}

// ── Buffer toggle ─────────────────────────────────────────────────────────────
function setBuffer(buf){
  curBuf=buf;
  document.querySelectorAll(".buf-btn").forEach(function(b){
    b.classList.toggle("active",b.dataset.buf===buf);
  });
  renderViolin(buf);
  renderBar(buf);
  if(curSite)renderTS(curSite,buf);
}

// ── Init ──────────────────────────────────────────────────────────────────────
window.onload=function(){
  buildCheckboxes();
  renderViolin(curBuf);
  renderBar(curBuf);
  // default: site with highest peak mortality at 500m
  var sites=Object.keys(siteData);
  curSite=sites.reduce(function(best,s){
    return peakMort(s,curBuf)>peakMort(best,curBuf)?s:best;
  },sites[0]);
  renderTS(curSite,curBuf);
};
</script>
</body>
</html>')

writeLines(html, out_file)
cat("Saved:", out_file, "\n")
cat("File size:", round(file.size(out_file)/1024/1024, 2), "MB\n")

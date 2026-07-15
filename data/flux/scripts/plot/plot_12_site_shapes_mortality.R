library(data.table)
library(jsonlite)

setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

out_file <- "plots/mortality_site_shapes/site_shapes_mortality.html"
dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)

plotly_js <- paste(readLines("/tmp/plotly-2.27.0.min.js", warn = FALSE), collapse = "\n")

# ── Load merged data ──────────────────────────────────────────────────────────
df <- fread("/tmp/efp_with_mortality.csv")
df[is.na(IGBP), IGBP := "Unknown"]

# Per-site peak new mortality rate (500m) — used for coloring
site_mr <- df[!is.na(new_mortality_rate_pct_500m),
              .(peak_mr = max(new_mortality_rate_pct_500m, na.rm = TRUE)),
              by = SITE_ID]
df[site_mr, peak_mr := i.peak_mr, on = .(SITE_ID)]
df[is.na(peak_mr), peak_mr := 0]

# IGBP order: by median GPPsat
igbp_order <- df[!is.na(GPPsat), .(med = median(GPPsat, na.rm=TRUE)), by=IGBP][order(med)]$IGBP

EFP_COLS  <- c("GPPsat","NEPmax","ETmax","uWUE","WUE","G1","EF","EFampl")
EFP_UNITS <- c(GPPsat="μmol m⁻² s⁻¹", NEPmax="μmol m⁻² s⁻¹", ETmax="mm d⁻¹",
               uWUE="g C mm⁻¹", WUE="g C mm⁻¹", G1="kPa⁰·⁵", EF="—", EFampl="—")
ALL_IGBP  <- igbp_order

# Build JSON: one entry per IGBP × EFP combination
# For each site-year observation: EFP value + peak_mr + IGBP + SITE_ID + YEAR
obs_list <- lapply(EFP_COLS, function(ecol) {
  sub_df <- df[!is.na(get(ecol))]
  list(
    igbp   = sub_df$IGBP,
    site   = sub_df$SITE_ID,
    year   = as.integer(sub_df$YEAR),
    val    = round(sub_df[[ecol]], 4),
    mr     = round(sub_df$peak_mr, 3)
  )
})
names(obs_list) <- EFP_COLS
json_obs <- toJSON(obs_list, auto_unbox = FALSE, na = "null", digits = 4)

# Per-site summary for the strip chart (one dot = one site, mean EFP)
site_summary <- df[, lapply(.SD, function(x) round(mean(x, na.rm=TRUE), 4)),
                   by = .(SITE_ID, IGBP, peak_mr),
                   .SDcols = EFP_COLS]
site_summary[, peak_mr := round(peak_mr, 3)]
json_sites <- toJSON(site_summary, auto_unbox = TRUE, na = "null", digits = 4)

json_igbp  <- toJSON(ALL_IGBP, auto_unbox = FALSE)
json_units <- toJSON(as.list(EFP_UNITS), auto_unbox = TRUE)

cat("Sites:", df[, uniqueN(SITE_ID)], "| Rows:", nrow(df), "\n")
cat("IGBP order:", paste(igbp_order, collapse=", "), "\n")

# ── HTML ──────────────────────────────────────────────────────────────────────
html <- paste0('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Site Shape Plots — Mortality Intensity</title>
<script>', plotly_js, '</script>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0D0D0D;color:#E0E0E0;font-family:Arial,sans-serif;padding:16px}
a{color:#22D4EB;text-decoration:none}a:hover{text-decoration:underline}
h1{text-align:center;font-size:1.2em;margin-bottom:4px}
.sub{text-align:center;font-size:0.82em;color:#9CA3AF;margin-bottom:14px}
.panel{background:#111827;border-radius:8px;padding:6px;margin-bottom:14px}
.panel-title{font-size:0.78em;color:#9CA3AF;text-transform:uppercase;letter-spacing:.07em;font-weight:bold;padding:6px 6px 2px}
#controls{background:#111827;border-radius:8px;padding:14px 18px;margin-bottom:14px;
          display:flex;flex-wrap:wrap;gap:18px;align-items:flex-start}
.ctrl-group{display:flex;flex-direction:column;gap:8px}
.ctrl-label{font-size:0.75em;color:#9CA3AF;text-transform:uppercase;letter-spacing:.06em;font-weight:bold}
.btn-row{display:flex;gap:5px;flex-wrap:wrap}
.vdiv{width:1px;background:#2A2A3A;align-self:stretch;margin:0 4px}
.tog-btn{background:#1F2937;color:#9CA3AF;border:1px solid #4B5563;border-radius:5px;
         padding:5px 13px;cursor:pointer;font-size:0.82em;transition:all .15s}
.tog-btn:hover{background:#374151}
.tog-btn.active{background:#22D4EB;color:#0D0D0D;border-color:#22D4EB;font-weight:bold}
.nav-back{display:inline-block;margin-bottom:10px;font-size:0.85em;
          background:#1F2937;border:1px solid #4B5563;border-radius:5px;padding:5px 14px}
.colorbar-label{font-size:0.75em;color:#9CA3AF;text-align:center;margin-top:4px}
</style>
</head>
<body>
<a href="../disturbance_effects/index.html" class="nav-back">&#8592; Back to hub</a>
<h1>Site Shape Plots — EFP distributions coloured by new mortality rate raw</h1>
<p class="sub">184 modeling sites &nbsp;|&nbsp; v2-2 &nbsp;|&nbsp;
  Dot colour = peak new mortality rate raw (%, 500 m buffer) &nbsp;|&nbsp; Yellow → Red = low → high disturbance</p>

<div id="controls">
  <div class="ctrl-group">
    <div class="ctrl-label">EFP</div>
    <div class="btn-row" id="efp-btns"></div>
  </div>
  <div class="vdiv"></div>
  <div class="ctrl-group">
    <div class="ctrl-label">Plot type</div>
    <div class="btn-row">
      <button class="tog-btn active" data-pt="violin" onclick="setPlotType(\'violin\')">Violin + dots</button>
      <button class="tog-btn"        data-pt="strip"  onclick="setPlotType(\'strip\')">Strip (site means)</button>
    </div>
  </div>
  <div class="vdiv"></div>
  <div class="ctrl-group">
    <div class="ctrl-label">IGBP filter</div>
    <div class="btn-row" id="igbp-btns"></div>
  </div>
</div>

<div class="panel">
  <div class="panel-title" id="main-title">EFP distribution by IGBP — dots coloured by peak new mortality rate raw (500 m)</div>
  <div id="main-plot"></div>
</div>

<script>
// ── Data ──────────────────────────────────────────────────────────────────────
var OBS       = ', json_obs, ';
var SITES     = ', json_sites, ';
var ALL_IGBP  = ', json_igbp, ';
var EFP_UNITS = ', json_units, ';
var EFP_COLS  = ["GPPsat","NEPmax","ETmax","uWUE","WUE","G1","EF","EFampl"];

// ── Theme ─────────────────────────────────────────────────────────────────────
var BG="#0D0D0D",PANEL="#111827",GRID="#2A2A3A",TEXT="#E0E0E0",SUB="#9CA3AF",AXIS="#4B5563",LEG_BG="#1A1A2E";
var IGBP_COL={ENF:"#1B6B3A",EBF:"#45B045",DNF:"#2E8B8B",DBF:"#8FBC45",MF:"#5F9EA0",
  CSH:"#C4843B",OSH:"#D4B483",WSA:"#A9A93A",SAV:"#D4C23A",WET:"#4682B4",Unknown:"#666666"};

// ── State ─────────────────────────────────────────────────────────────────────
var curEFP="GPPsat", curPT="violin", curIGBP=null;

// ── Helpers ───────────────────────────────────────────────────────────────────
function setActive(id,attr,key){
  document.querySelectorAll("#"+id+" [data-"+attr+"]").forEach(function(b){
    b.classList.toggle("active",b.dataset[attr]===key);
  });
}

// ── Build controls ────────────────────────────────────────────────────────────
function buildControls(){
  var eb=document.getElementById("efp-btns");
  EFP_COLS.forEach(function(c){
    var b=document.createElement("button");
    b.className="tog-btn"+(c==="GPPsat"?" active":"");
    b.dataset.efp=c; b.textContent=c;
    b.onclick=function(){curEFP=c;setActive("efp-btns","efp",c);render();};
    eb.appendChild(b);
  });
  var ib=document.getElementById("igbp-btns");
  // "All" button
  var all=document.createElement("button");
  all.className="tog-btn active"; all.dataset.ig="ALL"; all.textContent="All";
  all.onclick=function(){curIGBP=null;setActive("igbp-btns","ig","ALL");render();};
  ib.appendChild(all);
  ALL_IGBP.forEach(function(ig){
    var b=document.createElement("button");
    b.className="tog-btn"; b.dataset.ig=ig; b.textContent=ig;
    b.style.borderLeft="3px solid "+(IGBP_COL[ig]||"#888");
    b.onclick=function(){curIGBP=ig;setActive("igbp-btns","ig",ig);render();};
    ib.appendChild(b);
  });
}

function setPlotType(pt){
  curPT=pt;
  setActive("controls","pt",pt);
  render();
}

// ── Colorbar helper trace ─────────────────────────────────────────────────────
function colorbarTrace(vals){
  return{
    type:"scatter",mode:"markers",
    x:[null],y:[null],
    marker:{color:[Math.min.apply(null,vals),Math.max.apply(null,vals)],
            colorscale:"YlOrRd",showscale:true,
            colorbar:{title:{text:"New mort.<br>rate raw (%)",font:{color:SUB,size:10}},
                      thickness:14,len:0.8,x:1.01,
                      tickfont:{color:TEXT,size:9}},
            size:0,opacity:0},
    showlegend:false,hoverinfo:"skip"
  };
}

// ── Violin + jittered dots ────────────────────────────────────────────────────
function renderViolin(){
  var d=OBS[curEFP];
  var igbps=curIGBP?[curIGBP]:ALL_IGBP;
  var traces=[];
  var all_mr=[];

  igbps.forEach(function(ig){
    var mask=d.igbp.map(function(v,i){return v===ig&&d.val[i]!=null;});
    var vals=d.val.filter(function(_,i){return mask[i];});
    var mrs=d.mr.filter(function(_,i){return mask[i];});
    var sites=d.site.filter(function(_,i){return mask[i];});
    var years=d.year.filter(function(_,i){return mask[i];});
    if(!vals.length) return;
    all_mr=all_mr.concat(mrs);

    // Violin background
    traces.push({
      type:"violin",name:ig,y:vals,x:vals.map(function(){return ig;}),
      box:{visible:true},meanline:{visible:true},
      points:false,
      line:{color:IGBP_COL[ig]||"#888",width:1},
      fillcolor:(IGBP_COL[ig]||"#888")+"33",
      showlegend:false,hoverinfo:"none",opacity:0.7
    });

    // Jittered dots coloured by mortality rate
    var jitter=vals.map(function(){return (Math.random()-0.5)*0.35;});
    traces.push({
      type:"scatter",mode:"markers",name:ig+" pts",
      x:vals.map(function(_,i){return ig;}),
      y:vals,
      text:sites.map(function(s,i){
        return "<b>"+s+"</b> ("+ig+")<br>Year: "+years[i]+"<br>"+
               curEFP+": "+vals[i].toFixed(3)+" "+EFP_UNITS[curEFP]+"<br>"+
               "Peak new mort. rate: "+mrs[i].toFixed(2)+"%";
      }),
      hoverinfo:"text",
      marker:{
        color:mrs,colorscale:"YlOrRd",size:6,opacity:0.85,
        line:{width:0.5,color:"#111"},
        showscale:false
      },
      showlegend:false,
      xaxis:"x",yaxis:"y"
    });
  });

  if(all_mr.length) traces.push(colorbarTrace(all_mr));

  var unit=EFP_UNITS[curEFP]||"";
  Plotly.react("main-plot",traces,{
    violinmode:"overlay",
    xaxis:{gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT,size:11},zeroline:false},
    yaxis:{title:curEFP+" ("+unit+")",gridcolor:GRID,linecolor:AXIS,
           tickfont:{color:TEXT},titlefont:{color:SUB},zeroline:false},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:70,r:140,t:20,b:50},height:520
  },{responsive:true});
}

// ── Strip chart (one dot = one site = mean over years) ───────────────────────
function renderStrip(){
  var igbps=curIGBP?[curIGBP]:ALL_IGBP;
  var traces=[];
  var all_mr=[];

  igbps.forEach(function(ig){
    var rows=SITES.filter(function(r){return r.IGBP===ig&&r[curEFP]!=null;});
    if(!rows.length) return;
    var vals=rows.map(function(r){return r[curEFP];});
    var mrs=rows.map(function(r){return r.peak_mr||0;});
    var ids=rows.map(function(r){return r.SITE_ID;});
    all_mr=all_mr.concat(mrs);

    // Jitter on x
    var jitter=rows.map(function(){return (Math.random()-0.5)*0.4;});
    traces.push({
      type:"scatter",mode:"markers",name:ig,
      x:rows.map(function(_,i){return ig;}),
      y:vals,
      text:ids.map(function(s,i){
        return "<b>"+s+"</b> ("+ig+")<br>Mean "+curEFP+": "+vals[i].toFixed(3)+
               " "+EFP_UNITS[curEFP]+"<br>Peak new mort. rate: "+mrs[i].toFixed(2)+"%";
      }),
      hoverinfo:"text",
      marker:{
        color:mrs,colorscale:"YlOrRd",size:10,opacity:0.9,
        line:{width:0.8,color:"#111"},showscale:false
      },
      showlegend:false
    });
  });

  if(all_mr.length) traces.push(colorbarTrace(all_mr));

  var unit=EFP_UNITS[curEFP]||"";
  Plotly.react("main-plot",traces,{
    xaxis:{gridcolor:GRID,linecolor:AXIS,tickfont:{color:TEXT,size:11},zeroline:false},
    yaxis:{title:"Mean "+curEFP+" ("+unit+")",gridcolor:GRID,linecolor:AXIS,
           tickfont:{color:TEXT},titlefont:{color:SUB},zeroline:false},
    paper_bgcolor:BG,plot_bgcolor:PANEL,font:{color:TEXT},
    margin:{l:70,r:140,t:20,b:50},height:460
  },{responsive:true});
}

function render(){
  var ig_label=curIGBP?" ["+curIGBP+"]":" [all IGBP]";
  var pt_label=curPT==="violin"?"Violin + site-year dots":"Strip — site means";
  document.getElementById("main-title").textContent=
    curEFP+" distribution"+ig_label+" — "+pt_label+" — colour: peak new mortality rate raw (500 m)";
  if(curPT==="violin") renderViolin();
  else renderStrip();
}

window.onload=function(){
  buildControls();
  render();
};
</script>
</body>
</html>')

writeLines(html, out_file)
cat("Saved:", out_file, "\n")
cat("File size:", round(file.size(out_file)/1024/1024, 2), "MB\n")

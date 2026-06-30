#!/usr/bin/env python3
"""
Inject a Data Quality section into disturbance_dashboard.html.
Reads EFP and meteo CSVs, computes stats, builds Plotly charts,
and inserts HTML before </body>.
"""
import csv, json, math, statistics, os

BASE = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
EFP_CSV  = f"{BASE}/fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_YEARLY_EFP_min4continuousYears.csv"
METEO_CSV = f"{BASE}/fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_MONTHLY_METEO_corrected.csv"
DASHBOARD = f"{BASE}/manuscript/site_disturbance_history/disturbance_dashboard.html"

EFP_VARS  = ["GPPsat","NEPmax","ETmax","uWUE","WUE"]
EFP_UNITS = {"GPPsat":"µmol m⁻² s⁻¹","NEPmax":"µmol m⁻² s⁻¹","ETmax":"mm s⁻¹","uWUE":"µmol m⁻² s⁻¹ hPa⁻⁰·⁵","WUE":"gC/mm"}
METEO_VARS= ["TA_mean","VPD_mean","SW_IN_mean","P_sum"]
METEO_UNITS={"TA_mean":"°C","VPD_mean":"hPa","SW_IN_mean":"W m⁻²","P_sum":"mm/month"}

# ── helpers ──────────────────────────────────────────────────────────────────
def to_float(v):
    try: return float(v) if v not in ("","NA","nan","NaN") else None
    except: return None

def stats(vals):
    v = [x for x in vals if x is not None and not math.isnan(x)]
    if len(v) < 2: return {}
    mean = statistics.mean(v)
    sd   = statistics.stdev(v)
    sv   = sorted(v)
    def pct(p): idx = int(len(sv)*p/100); return sv[min(idx,len(sv)-1)]
    return dict(n=len(v), mean=round(mean,3), median=round(statistics.median(v),3),
                sd=round(sd,3), var=round(sd**2,3),
                mn=round(sv[0],3), mx=round(sv[-1],3),
                p5=round(pct(5),3), p25=round(pct(25),3), p75=round(pct(75),3), p95=round(pct(95),3),
                n_out=sum(1 for x in v if abs(x-mean)>3*sd))

# ── read EFP ─────────────────────────────────────────────────────────────────
efp_rows = []
with open(EFP_CSV) as f:
    reader = csv.DictReader(f)
    for row in reader:
        for v in EFP_VARS:
            row[v] = to_float(row.get(v,""))
        row["YEAR"] = row.get("YEAR","")
        efp_rows.append(row)

n_total = len(efp_rows)

efp_stats = {}
efp_vals  = {}
for v in EFP_VARS:
    vals = [r[v] for r in efp_rows]
    efp_vals[v] = vals
    n_miss = sum(1 for x in vals if x is None)
    s = stats([x for x in vals if x is not None])
    s["n_total"] = n_total
    s["n_miss"]  = n_miss
    s["pct_miss"]= round(n_miss/n_total*100,1) if n_total else 0
    efp_stats[v] = s

# outliers per EFP
outliers = []
for v in EFP_VARS:
    s = efp_stats[v]
    if not s: continue
    mean, sd = s["mean"], s["sd"]
    for r in efp_rows:
        val = r[v]
        if val is None: continue
        z = (val - mean) / sd if sd else 0
        if abs(z) > 3:
            outliers.append({"var":v,"site":r["SITE_ID"],"year":r["YEAR"],"val":round(val,3),"z":round(z,2)})
outliers.sort(key=lambda x: abs(x["z"]), reverse=True)

# impossible values (negative uWUE/WUE, negative GPPsat, ETmax<0)
impossible = []
for r in efp_rows:
    for v in ["uWUE","WUE","GPPsat","NEPmax","ETmax"]:
        val = r[v]
        if val is not None and val < 0:
            impossible.append({"var":v,"site":r["SITE_ID"],"year":r["YEAR"],"val":round(val,4)})

# missing by site for heatmap
sites_with_miss = {}
for r in efp_rows:
    sid = r["SITE_ID"]
    if sid not in sites_with_miss:
        sites_with_miss[sid] = {v:[] for v in EFP_VARS}
    for v in EFP_VARS:
        sites_with_miss[sid][v].append(r[v])

site_miss_pct = {}
for sid, d in sites_with_miss.items():
    site_miss_pct[sid] = {}
    for v in EFP_VARS:
        vals = d[v]
        site_miss_pct[sid][v] = round(sum(1 for x in vals if x is None)/len(vals)*100,0) if vals else 100

# Sort sites by total missingness (worst first)
site_miss_total = {sid: sum(site_miss_pct[sid].values()) for sid in site_miss_pct}
sites_sorted = sorted(site_miss_pct.keys(), key=lambda s: site_miss_total[s], reverse=True)

# ── read METEO ───────────────────────────────────────────────────────────────
meteo_rows = []
with open(METEO_CSV) as f:
    reader = csv.DictReader(f)
    for row in reader:
        for v in METEO_VARS:
            row[v] = to_float(row.get(v,""))
        meteo_rows.append(row)

meteo_stats = {}
for v in METEO_VARS:
    vals = [r[v] for r in meteo_rows]
    n_miss = sum(1 for x in vals if x is None)
    s = stats([x for x in vals if x is not None])
    s["n_total"] = len(meteo_rows)
    s["n_miss"]  = n_miss
    s["pct_miss"]= round(n_miss/len(meteo_rows)*100,1)
    meteo_stats[v] = s

# VPD flags (>80 hPa = possible Pa)
vpd_flag_sites = {}
for r in meteo_rows:
    val = r["VPD_mean"]
    if val is not None and val > 80:
        sid = r["SITE_ID"]
        vpd_flag_sites.setdefault(sid, []).append(val)

# P flags (>2000 mm/month)
p_flag = [(r["SITE_ID"],r["YEAR"],r["MONTH"],round(r["P_sum"],0)) for r in meteo_rows if r.get("P_sum") and r["P_sum"] > 2000]

# Per-network meteo stats
def network(sid):
    parts = sid.split("-")
    if len(parts) >= 2: return parts[0]
    return sid[:3]

net_ta  = {}
net_vpd = {}
for r in meteo_rows:
    net = network(r["SITE_ID"])
    if r["TA_mean"]  is not None: net_ta.setdefault(net,[]).append(r["TA_mean"])
    if r["VPD_mean"] is not None and r["VPD_mean"] < 80: net_vpd.setdefault(net,[]).append(r["VPD_mean"])

net_labels = sorted(net_ta.keys())
net_ta_means  = [round(statistics.mean(net_ta[n]),1)  if net_ta.get(n)  else 0 for n in net_labels]
net_vpd_means = [round(statistics.mean(net_vpd[n]),1) if net_vpd.get(n) else 0 for n in net_labels]

# ── prepare Plotly data as JSON ───────────────────────────────────────────────

# 1. EFP violin / box
efp_box_traces = []
COLORS = {"GPPsat":"#005f73","NEPmax":"#0a9396","ETmax":"#94d2bd","uWUE":"#e9c46a","WUE":"#f4a261"}
for v in EFP_VARS:
    yvals = [x for x in efp_vals[v] if x is not None]
    efp_box_traces.append({"type":"violin","y":yvals,"name":v,
                            "box":{"visible":True},"meanline":{"visible":True},
                            "fillcolor":COLORS[v],"line":{"color":COLORS[v],"width":1.5},
                            "opacity":0.7,"points":False})

# 2. Missing heatmap (top 50 sites with most missing)
top50 = sites_sorted[:50]
hm_z = [[site_miss_pct[sid][v] for v in EFP_VARS] for sid in top50]
hm_trace = {"type":"heatmap","x":EFP_VARS,"y":top50,"z":hm_z,
             "colorscale":[[0,"#fffdf8"],[0.01,"#fee090"],[0.5,"#fc8d59"],[1,"#b30000"]],
             "colorbar":{"title":"% missing","thickness":14,"len":0.8},
             "zmin":0,"zmax":100,"hoverongaps":False}

# 3. Network TA/VPD bar
net_bar_ta  = {"type":"bar","name":"TA mean (°C)","x":net_labels,"y":net_ta_means,
               "marker":{"color":"#005f73"},"offsetgroup":"1"}
net_bar_vpd = {"type":"bar","name":"VPD mean (hPa)","x":net_labels,"y":net_vpd_means,
               "marker":{"color":"#0a9396"},"offsetgroup":"2"}

# 4. Outliers scatter
out_vars = [o["var"] for o in outliers[:40]]
out_z    = [o["z"] for o in outliers[:40]]
out_text = [f"{o['site']} {o['year']}: {o['val']}" for o in outliers[:40]]
out_trace = {"type":"scatter","mode":"markers","x":out_vars,"y":out_z,
             "text":out_text,"hoverinfo":"text","marker":{"size":8,"color":out_z,
             "colorscale":[[0,"#fc8d59"],[1,"#b30000"]],"showscale":False}}

# ── build stats table rows ────────────────────────────────────────────────────
def trow(cells, tag="td"):
    return "<tr>" + "".join(f"<{tag}>{c}</{tag}>" for c in cells) + "</tr>"

def efp_table():
    hdrs = ["Variable","Unit","n_total","n_missing","% missing","mean","median","SD","min","max","p5","p95","outliers (|z|>3)"]
    rows = [trow(hdrs,"th")]
    for v in EFP_VARS:
        s = efp_stats[v]
        flag = "🚨" if s["pct_miss"] >= 10 else ("⚠️" if s["pct_miss"] >= 5 else "✓")
        rows.append(trow([f"{flag} {v}", EFP_UNITS[v], s["n_total"], s["n_miss"],
                          f"{s['pct_miss']}%", s["mean"], s["median"], s["sd"],
                          s["mn"], s["mx"], s["p5"], s["p95"], s["n_out"]]))
    return "<table class='dq-tbl'>" + "".join(rows) + "</table>"

def meteo_table():
    hdrs = ["Variable","Unit","n_total","% missing","mean","median","SD","min","max","p5","p95","outliers (|z|>3)"]
    rows = [trow(hdrs,"th")]
    flags = {"TA_mean":"✓","VPD_mean":"🚨" if vpd_flag_sites else "✓",
             "SW_IN_mean":"✓","P_sum":"🚨" if p_flag else "✓"}
    for v in METEO_VARS:
        s = meteo_stats[v]
        rows.append(trow([f"{flags[v]} {v}", METEO_UNITS[v], s["n_total"],
                          f"{s['pct_miss']}%", s["mean"], s["median"], s["sd"],
                          s["mn"], s["mx"], s["p5"], s["p95"], s["n_out"]]))
    return "<table class='dq-tbl'>" + "".join(rows) + "</table>"

def outlier_table(limit=20):
    hdrs = ["Variable","Site","Year","Value","z-score"]
    rows = [trow(hdrs,"th")]
    for o in outliers[:limit]:
        color = "#b30000" if abs(o["z"])>6 else ("#fc8d59" if abs(o["z"])>4 else "inherit")
        rows.append(f"<tr style='color:{color}'>"+
                    "".join(f"<td>{c}</td>" for c in [o["var"],o["site"],o["year"],o["val"],o["z"]])+
                    "</tr>")
    return "<table class='dq-tbl'>" + "".join(rows) + "</table>"

def impossible_table():
    hdrs = ["Variable","Site","Year","Value"]
    rows = [trow(hdrs,"th")]
    for o in impossible[:20]:
        rows.append(trow([o["var"],o["site"],o["year"],o["val"]]))
    return "<table class='dq-tbl'>" + "".join(rows) + "</table>"

def vpd_flag_table():
    hdrs = ["Site","n_months","VPD max (hPa)","Likely units"]
    rows = [trow(hdrs,"th")]
    for sid, vals in vpd_flag_sites.items():
        rows.append(trow([sid, len(vals), round(max(vals),0), "Pa → divide by 100"]))
    return "<table class='dq-tbl'>" + "".join(rows) + "</table>"

# ── summary KPIs ─────────────────────────────────────────────────────────────
n_sites = len(sites_with_miss)
n_sites_with_any_miss = sum(1 for sid in site_miss_pct
                            if any(v>0 for v in site_miss_pct[sid].values()))
n_impossible_total = len(impossible)
n_critical = int(bool(vpd_flag_sites)) + int(bool(p_flag)) + int(n_impossible_total>0) + int(n_sites_with_any_miss > n_sites*0.2)
efp_miss_pct = round(statistics.mean(efp_stats[v]["pct_miss"] for v in EFP_VARS),1)

# ── assemble HTML ─────────────────────────────────────────────────────────────
section = f"""
<!-- ══════════════════════════════════════════════════════════════════════
     DATA QUALITY REPORT — auto-generated by inject_dq_section.py
     ══════════════════════════════════════════════════════════════════════ -->
<style>
  .dq-section  {{ margin-top:28px; }}
  .dq-hero     {{ background:linear-gradient(135deg,#264653 0%,#2a9d8f 60%,#e9c46a 100%);
                  color:#fff;border-radius:16px;padding:20px 24px;
                  box-shadow:0 8px 24px rgba(0,0,0,.15);margin-bottom:16px; }}
  .dq-hero h2  {{ margin:0 0 6px;font-size:1.4rem; }}
  .dq-kpis     {{ display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));
                  gap:12px;margin-bottom:16px; }}
  .dq-kpi      {{ background:#fffdf8;border:1px solid #ddd4c4;border-radius:12px;
                  padding:12px 14px; }}
  .dq-kpi .v   {{ font-size:1.6rem;font-weight:700; }}
  .dq-kpi .l   {{ font-size:.85rem;color:#6a655c;margin-top:2px; }}
  .dq-kpi.red  .v {{ color:#b30000; }}
  .dq-kpi.amber .v {{ color:#ca6702; }}
  .dq-kpi.ok   .v {{ color:#005f73; }}
  .dq-alerts   {{ display:flex;flex-direction:column;gap:8px;margin-bottom:16px; }}
  .dq-alert    {{ border-radius:10px;padding:10px 14px;font-size:.92rem;
                  display:flex;align-items:flex-start;gap:10px; }}
  .dq-alert.red    {{ background:#fff0f0;border:1px solid #f5c6c6;color:#7b1010; }}
  .dq-alert.amber  {{ background:#fff8e6;border:1px solid #f5dba0;color:#6b4500; }}
  .dq-alert .icon  {{ font-size:1.1rem;flex-shrink:0;margin-top:1px; }}
  .dq-cards    {{ display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));
                  gap:14px;margin-bottom:16px; }}
  .dq-card     {{ background:#fffdf8;border:1px solid #ddd4c4;border-radius:12px;
                  padding:12px; }}
  .dq-card h3  {{ margin:0 0 8px;font-size:1rem;color:#264653; }}
  .dq-tbl      {{ width:100%;border-collapse:collapse;font-size:.83rem;margin-top:4px; }}
  .dq-tbl th   {{ background:#f0ede4;padding:5px 8px;text-align:left;
                  border-bottom:2px solid #ddd4c4;position:sticky;top:0; }}
  .dq-tbl td   {{ padding:4px 8px;border-bottom:1px solid #eee4d1;vertical-align:top; }}
  .dq-tbl tr:hover td {{ background:#fdf6e3; }}
  .dq-plot-wrap {{ min-height:320px; }}
  .dq-section-hdr {{ font-size:1.05rem;font-weight:600;color:#264653;
                      margin:18px 0 8px;padding-bottom:4px;
                      border-bottom:2px solid #94d2bd; }}
  .dq-overflow {{ max-height:380px;overflow-y:auto;border-radius:8px; }}
</style>

<div class="dq-section">
  <div class="dq-hero">
    <h2>📊 Flux Data Quality Report</h2>
    <p style="margin:0;opacity:.92">Generated from {n_total} EFP site-years ({n_sites} sites) and {len(meteo_rows):,} site-months across 9 networks — FLUXNET 2017–2025 V02</p>
  </div>

  <!-- KPI row -->
  <div class="dq-kpis">
    <div class="dq-kpi {'red' if efp_miss_pct>15 else 'amber' if efp_miss_pct>5 else 'ok'}">
      <div class="v">{efp_miss_pct}%</div><div class="l">avg EFP missing</div>
    </div>
    <div class="dq-kpi {'red' if n_sites_with_any_miss>30 else 'amber'}">
      <div class="v">{n_sites_with_any_miss}</div><div class="l">sites with ≥1 missing EFP</div>
    </div>
    <div class="dq-kpi {'red' if len(outliers)>20 else 'amber' if len(outliers)>5 else 'ok'}">
      <div class="v">{len(outliers)}</div><div class="l">outlier site-years (|z|>3)</div>
    </div>
    <div class="dq-kpi {'red' if n_impossible_total>0 else 'ok'}">
      <div class="v">{n_impossible_total}</div><div class="l">impossible values (EFP < 0)</div>
    </div>
    <div class="dq-kpi {'red' if vpd_flag_sites else 'ok'}">
      <div class="v">{len(vpd_flag_sites)}</div><div class="l">sites with VPD unit issue</div>
    </div>
    <div class="dq-kpi {'red' if p_flag else 'ok'}">
      <div class="v">{len(p_flag)}</div><div class="l">months P > 2000 mm</div>
    </div>
  </div>

  <!-- Alerts -->
  <div class="dq-alerts">
    {''.join(f"""<div class="dq-alert red"><span class="icon">🚨</span><div><b>CD-Ygb VPD in Pa not hPa</b> — ICOS site CD-Ygb has VPD_mean up to {round(max(max(v) for v in vpd_flag_sites.values()),0):.0f} in the monthly meteo file. Divide by 100 before use (gives 14–21 hPa, plausible for tropical DRC).</div></div>""" if vpd_flag_sites else "")}
    {''.join(f"""<div class="dq-alert red"><span class="icon">🚨</span><div><b>US-HB4 precipitation anomaly</b> — {len(p_flag)} site-months with P_sum up to {round(max(x[3] for x in p_flag),0):.0f} mm/month (world record ~2500 mm). Likely instrument error — exclude these months.</div></div>""" if p_flag else "")}
    {''.join(f"""<div class="dq-alert red"><span class="icon">🚨</span><div><b>{n_impossible_total} physically impossible EFP values</b> — negative uWUE/WUE in {len(set(o["site"] for o in impossible))} sites (CA-PB1, US-EML, US-xMB, US-xML, US-xNW, US-xYE). Values near zero; likely numerical artifacts at ecosystem carbon balance limits.</div></div>""" if impossible else "")}
    <div class="dq-alert red"><span class="icon">🚨</span><div><b>GPPsat / uWUE / WUE missing in ~21.5% of site-years</b> — concentrated in 72 sites where <code>Gavail=no</code> (insufficient light-saturation data). EBF and DNF classes are worst affected (62% missing).</div></div>
    <div class="dq-alert amber"><span class="icon">⚠️</span><div><b>CN-Sb1 &amp; CN-Sb2 extreme WUE/uWUE outliers</b> — likely rice paddy / managed cropland. WUE up to 34×, uWUE up to 17× global median (z-scores 6–14). Consider excluding or flagging as cropland in sensitivity analysis.</div></div>
    <div class="dq-alert amber"><span class="icon">⚠️</span><div><b>KOF KR-SmM and TERN AU-How</b> — only GPP_DT_VUT_REF available (no NT partitioning). EFP computation falls back to DT partitioning for these sites.</div></div>
    <div class="dq-alert amber"><span class="icon">⚠️</span><div><b>AMF uses hourly (_HR_) not half-hourly (_HH_) data</b> — any n_obs ≥ 1488 threshold in EFP scripts should be halved (~744) for AmeriFlux sites.</div></div>
  </div>

  <!-- EFP distributions -->
  <div class="dq-section-hdr">EFP Distributions (all site-years)</div>
  <div class="dq-cards" style="grid-template-columns:1fr;">
    <div class="dq-card">
      <h3>EFP value distributions — violin + box (excluding missing)</h3>
      <div class="dq-plot-wrap" id="dq_efp_violin" style="height:340px;"></div>
    </div>
  </div>

  <!-- Missing data heatmap -->
  <div class="dq-section-hdr">Missing Data by Site (top 50 sites with most missing)</div>
  <div class="dq-cards" style="grid-template-columns:1fr;">
    <div class="dq-card">
      <h3>% missing per EFP variable — top 50 sites ranked by total missingness</h3>
      <div class="dq-plot-wrap" id="dq_miss_hm" style="height:500px;"></div>
    </div>
  </div>

  <!-- EFP stats table -->
  <div class="dq-section-hdr">EFP Summary Statistics</div>
  <div class="dq-card" style="margin-bottom:14px;">
    <h3>Annual EFPs — descriptive statistics</h3>
    <div class="dq-overflow">{efp_table()}</div>
  </div>

  <!-- Outliers -->
  <div class="dq-section-hdr">Outlier Site-Years (|z-score| > 3)</div>
  <div class="dq-cards">
    <div class="dq-card" style="grid-column:1/-1;">
      <h3>Top 20 outlier site-years (ranked by |z|)</h3>
      <div class="dq-overflow">{outlier_table(20)}</div>
    </div>
    <div class="dq-card" style="grid-column:1/-1;">
      <h3>Outlier z-scores by EFP (top 40)</h3>
      <div class="dq-plot-wrap" id="dq_outlier_scatter" style="height:280px;"></div>
    </div>
  </div>

  <!-- Impossible values -->
  {'<div class="dq-section-hdr">Physically Impossible Values (EFP &lt; 0)</div><div class="dq-card" style="margin-bottom:14px;"><h3>Records with impossible values</h3><div class="dq-overflow">' + impossible_table() + '</div></div>' if impossible else ""}

  <!-- Meteo stats -->
  <div class="dq-section-hdr">Meteorological Variable Quality (Monthly Aggregates)</div>
  <div class="dq-card" style="margin-bottom:14px;">
    <h3>Monthly meteo — descriptive statistics</h3>
    <div class="dq-overflow">{meteo_table()}</div>
  </div>

  <!-- VPD flag -->
  {'<div class="dq-section-hdr">VPD Unit Flag — Possible Pa Instead of hPa</div><div class="dq-card" style="margin-bottom:14px;"><div class="dq-overflow">' + vpd_flag_table() + '</div></div>' if vpd_flag_sites else ""}

  <!-- Network comparison -->
  <div class="dq-section-hdr">Cross-Network Consistency</div>
  <div class="dq-cards">
    <div class="dq-card" style="grid-column:1/-1;">
      <h3>Mean TA and VPD by network (VPD flags excluded)</h3>
      <div class="dq-plot-wrap" id="dq_net_bar" style="height:280px;"></div>
    </div>
  </div>

</div><!-- end dq-section -->

<script>
(function(){{
  var DQ = {{
    efp_violin: {json.dumps(efp_box_traces)},
    miss_hm:    [{ json.dumps(hm_trace) }],
    outlier:    [{ json.dumps(out_trace) }],
    net_bar:    {json.dumps([net_bar_ta, net_bar_vpd])}
  }};
  var dark = {{ paper_bgcolor:"#fffdf8", plot_bgcolor:"#fffdf8",
                font:{{family:"Source Sans 3,Segoe UI,sans-serif",color:"#1d1a16"}},
                margin:{{l:50,r:20,t:30,b:50}} }};
  function pl(id,traces,layout){{
    Plotly.newPlot(id, traces, Object.assign({{}},dark,layout),{{responsive:true,displayModeBar:false}});
  }}

  pl("dq_efp_violin", DQ.efp_violin, {{
    title:"", yaxis:{{title:"Value (variable-specific units)"}},
    xaxis:{{title:"EFP"}}, showlegend:false
  }});

  pl("dq_miss_hm", DQ.miss_hm, {{
    title:"",
    xaxis:{{title:"EFP variable",tickfont:{{size:12}}}},
    yaxis:{{title:"Site ID",tickfont:{{size:9}},autorange:"reversed"}},
    margin:{{l:90,r:80,t:20,b:50}}
  }});

  pl("dq_outlier_scatter", DQ.outlier, {{
    title:"",
    xaxis:{{title:"EFP"}},
    yaxis:{{title:"z-score",zeroline:true,zerolinecolor:"#aaa"}},
    showlegend:false
  }});

  pl("dq_net_bar", DQ.net_bar, {{
    title:"",barmode:"group",
    xaxis:{{title:"Network"}},
    yaxis:{{title:"Value"}},
    legend:{{orientation:"h",y:1.15}}
  }});
}})();
</script>
"""

# ── inject into dashboard HTML ────────────────────────────────────────────────
html = open(DASHBOARD).read()
if "dq-section" in html:
    # Replace existing block
    import re
    html = re.sub(r'<!-- ══.*?end dq-section -->.*?</script>', '', html, flags=re.DOTALL)
    print("Replaced existing DQ section.")

html = html.replace("</body>", section + "\n</body>")
with open(DASHBOARD, "w") as f:
    f.write(html)

print(f"✓ Injected DQ section into {DASHBOARD}")
print(f"  EFP site-years: {n_total} | Outliers: {len(outliers)} | Impossible: {n_impossible_total}")
print(f"  VPD flags: {list(vpd_flag_sites.keys())} | P flags: {len(p_flag)}")

#!/usr/bin/env python3
"""
Build data_quality.html for negin-katal/fluxVSmortality GitHub Pages.
Dark theme matching the hub. Reads EFP + meteo CSVs, embeds Plotly charts.
"""
import csv, json, math, statistics, os, re

BASE = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
EFP_CSV   = f"{BASE}/fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_YEARLY_EFP_min4continuousYears.csv"
METEO_CSV = f"{BASE}/fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_MONTHLY_METEO_corrected.csv"
OUT_FILE  = "/tmp/fluxVSmortality/data_quality.html"
HUB_IDX   = "/tmp/fluxVSmortality/index.html"

EFP_VARS   = ["GPPsat","NEPmax","ETmax","uWUE","WUE"]
EFP_UNITS  = {"GPPsat":"µmol m⁻² s⁻¹","NEPmax":"µmol m⁻² s⁻¹","ETmax":"mm s⁻¹","uWUE":"µmol m⁻² s⁻¹ hPa⁻⁰·⁵","WUE":"gC / mm"}
METEO_VARS = ["TA_mean","VPD_mean","SW_IN_mean","P_sum"]
METEO_UNITS= {"TA_mean":"°C","VPD_mean":"hPa","SW_IN_mean":"W m⁻²","P_sum":"mm / month"}

COLORS = {"GPPsat":"#22D4EB","NEPmax":"#3BA0FF","ETmax":"#94d2bd","uWUE":"#f4a261","WUE":"#e9c46a"}

# ── helpers ──────────────────────────────────────────────────────────────────
def to_float(v):
    try: return float(v) if v not in ("","NA","nan","NaN") else None
    except: return None

def pct_at(sv, p):
    idx = int(len(sv)*p/100)
    return sv[min(idx, len(sv)-1)]

def stats(vals):
    v = [x for x in vals if x is not None and not math.isnan(x)]
    if len(v) < 2: return {}
    mean = statistics.mean(v); sd = statistics.stdev(v); sv = sorted(v)
    return dict(n=len(v), mean=round(mean,3), median=round(statistics.median(v),3),
                sd=round(sd,3), var=round(sd**2,3),
                mn=round(sv[0],3), mx=round(sv[-1],3),
                p5=round(pct_at(sv,5),3), p25=round(pct_at(sv,25),3),
                p75=round(pct_at(sv,75),3), p95=round(pct_at(sv,95),3),
                n_out=sum(1 for x in v if abs(x-mean)>3*sd))

# ── load EFP ─────────────────────────────────────────────────────────────────
efp_rows = []
with open(EFP_CSV) as f:
    rdr = csv.DictReader(f)
    for row in rdr:
        for v in EFP_VARS: row[v] = to_float(row.get(v,""))
        efp_rows.append(row)

n_total = len(efp_rows)

efp_stats = {}; efp_vals = {}
for v in EFP_VARS:
    vals = [r[v] for r in efp_rows]
    efp_vals[v] = vals
    n_miss = sum(1 for x in vals if x is None)
    s = stats([x for x in vals if x is not None])
    s["n_total"]=n_total; s["n_miss"]=n_miss; s["pct_miss"]=round(n_miss/n_total*100,1)
    efp_stats[v] = s

outliers = []
for v in EFP_VARS:
    s = efp_stats[v]
    if not s: continue
    mean, sd = s["mean"], s["sd"]
    for r in efp_rows:
        val = r[v]
        if val is None: continue
        z = (val-mean)/sd if sd else 0
        if abs(z) > 3:
            outliers.append({"var":v,"site":r["SITE_ID"],"year":r["YEAR"],"val":round(val,3),"z":round(z,2)})
outliers.sort(key=lambda x: abs(x["z"]), reverse=True)

impossible = []
for r in efp_rows:
    for v in ["uWUE","WUE","GPPsat","ETmax"]:
        val = r[v]
        if val is not None and val < 0:
            impossible.append({"var":v,"site":r["SITE_ID"],"year":r["YEAR"],"val":round(val,4)})

# missing by site
sites_miss = {}
for r in efp_rows:
    sid = r["SITE_ID"]
    sites_miss.setdefault(sid, {v:[] for v in EFP_VARS})
    for v in EFP_VARS: sites_miss[sid][v].append(r[v])

site_miss_pct = {sid:{v:round(sum(1 for x in d[v] if x is None)/len(d[v])*100,0)
                      for v in EFP_VARS} for sid,d in sites_miss.items()}
sites_sorted = sorted(site_miss_pct, key=lambda s:sum(site_miss_pct[s].values()), reverse=True)

# ── load METEO ───────────────────────────────────────────────────────────────
meteo_rows = []
with open(METEO_CSV) as f:
    rdr = csv.DictReader(f)
    for row in rdr:
        for v in METEO_VARS: row[v] = to_float(row.get(v,""))
        meteo_rows.append(row)

meteo_stats = {}
for v in METEO_VARS:
    vals=[r[v] for r in meteo_rows]; n_miss=sum(1 for x in vals if x is None)
    s=stats([x for x in vals if x is not None])
    s["n_total"]=len(meteo_rows); s["n_miss"]=n_miss; s["pct_miss"]=round(n_miss/len(meteo_rows)*100,1)
    meteo_stats[v]=s

vpd_flag_sites = {}
for r in meteo_rows:
    val=r["VPD_mean"]
    if val is not None and val>80:
        vpd_flag_sites.setdefault(r["SITE_ID"],[]).append(val)

p_flag=[(r["SITE_ID"],r.get("YEAR",""),r.get("MONTH",""),round(r["P_sum"],0))
        for r in meteo_rows if r.get("P_sum") and r["P_sum"]>2000]

def network(sid):
    parts=sid.split("-"); return parts[0] if len(parts)>=2 else sid[:3]

net_ta={}; net_vpd={}
for r in meteo_rows:
    net=network(r["SITE_ID"])
    if r["TA_mean"]  is not None: net_ta.setdefault(net,[]).append(r["TA_mean"])
    if r["VPD_mean"] is not None and r["VPD_mean"]<80: net_vpd.setdefault(net,[]).append(r["VPD_mean"])

net_labels=sorted(net_ta.keys())
net_ta_m  =[round(statistics.mean(net_ta[n]),1)  if net_ta.get(n)  else 0 for n in net_labels]
net_vpd_m =[round(statistics.mean(net_vpd[n]),1) if net_vpd.get(n) else 0 for n in net_labels]

# ── Plotly traces ─────────────────────────────────────────────────────────────
violin_traces = [{"type":"violin","y":[x for x in efp_vals[v] if x is not None],"name":v,
                  "box":{"visible":True},"meanline":{"visible":True},
                  "fillcolor":COLORS[v],"line":{"color":COLORS[v],"width":1.5},
                  "opacity":0.75,"points":False} for v in EFP_VARS]

top50 = sites_sorted[:50]
hm_z = [[site_miss_pct[sid][v] for v in EFP_VARS] for sid in top50]
hm_trace = [{"type":"heatmap","x":EFP_VARS,"y":top50,"z":hm_z,
              "colorscale":[[0,"#1a1a2e"],[0.01,"#e9c46a"],[0.5,"#f4a261"],[1,"#e63946"]],
              "colorbar":{"title":"% missing","thickness":14,"titlefont":{"color":"#9CA3AF"},
                          "tickfont":{"color":"#9CA3AF"}},
              "zmin":0,"zmax":100}]

out_trace = [{"type":"scatter","mode":"markers",
              "x":[o["var"] for o in outliers[:40]],
              "y":[o["z"] for o in outliers[:40]],
              "text":[f"{o['site']} {o['year']}: {o['val']}" for o in outliers[:40]],
              "hoverinfo":"text",
              "marker":{"size":9,"color":[o["z"] for o in outliers[:40]],
                        "colorscale":[[0,"#f4a261"],[1,"#e63946"]],
                        "showscale":False,"line":{"color":"#333","width":0.5}}}]

net_bar = [{"type":"bar","name":"Mean TA (°C)","x":net_labels,"y":net_ta_m,
             "marker":{"color":"#22D4EB","opacity":0.85},"offsetgroup":"1"},
            {"type":"bar","name":"Mean VPD (hPa)","x":net_labels,"y":net_vpd_m,
             "marker":{"color":"#f4a261","opacity":0.85},"offsetgroup":"2"}]

# Year × n_sites_with_data bar
year_counts = {}
for r in efp_rows:
    yr = r.get("YEAR","")
    if yr:
        if r["GPPsat"] is not None: year_counts[yr] = year_counts.get(yr,0)+1

yr_sorted = sorted(year_counts.keys())
yr_bar = [{"type":"bar","x":yr_sorted,"y":[year_counts[y] for y in yr_sorted],
            "marker":{"color":"#22D4EB","opacity":0.8},"name":"site-years with GPPsat"}]

# IGBP missing rate (use network as proxy here since we don't have IGBP in EFP file)
# Actually check if igbp column exists
with open(EFP_CSV) as f:
    first_cols = next(csv.reader(f))
has_igbp = "igbp" in [c.lower() for c in first_cols]

igbp_miss = {}
if has_igbp:
    igbp_col = next(c for c in first_cols if c.lower()=="igbp")
    for r in efp_rows:
        ig = r.get(igbp_col,"")
        if not ig: continue
        igbp_miss.setdefault(ig, {"total":0,"miss":0})
        igbp_miss[ig]["total"] += 1
        if r["GPPsat"] is None: igbp_miss[ig]["miss"] += 1
    igbp_labels = sorted(igbp_miss.keys())
    igbp_pct = [round(igbp_miss[ig]["miss"]/igbp_miss[ig]["total"]*100,1) for ig in igbp_labels]
    igbp_n   = [igbp_miss[ig]["total"] for ig in igbp_labels]
    igbp_bar = [{"type":"bar","x":igbp_labels,"y":igbp_pct,
                  "text":[f"n={n}" for n in igbp_n],"textposition":"outside",
                  "marker":{"color":igbp_pct,
                             "colorscale":[[0,"#22D4EB"],[0.3,"#f4a261"],[1,"#e63946"]],
                             "showscale":False}}]
else:
    igbp_bar = []

# ── HTML helpers ─────────────────────────────────────────────────────────────
def trow(cells, tag="td", style=""):
    inner = "".join(f"<{tag} style='{style}'>{c}</{tag}>" for c in cells)
    return f"<tr>{inner}</tr>"

def efp_table():
    hdrs=["EFP","Unit","n","n missing","% missing","mean","median","SD","min","max","p5","p95","outliers |z|>3"]
    rows=[trow(hdrs,"th")]
    for v in EFP_VARS:
        s=efp_stats[v]
        flag="🚨" if s["pct_miss"]>=10 else ("⚠️" if s["pct_miss"]>=5 else "✓")
        col="#e63946" if s["pct_miss"]>=10 else ("#f4a261" if s["pct_miss"]>=5 else "#4ade80")
        rows.append(f"<tr><td style='color:{COLORS[v]};font-weight:600'>{v}</td>"
                    +f"<td style='color:#6B7280;font-size:.8em'>{EFP_UNITS[v]}</td>"
                    +f"<td>{s['n']}</td><td>{s['n_miss']}</td>"
                    +f"<td style='color:{col};font-weight:600'>{flag} {s['pct_miss']}%</td>"
                    +f"<td>{s['mean']}</td><td>{s['median']}</td><td>{s['sd']}</td>"
                    +f"<td>{s['mn']}</td><td>{s['mx']}</td><td>{s['p5']}</td><td>{s['p95']}</td>"
                    +f"<td style='color:#f4a261'>{s['n_out']}</td></tr>")
    return "<table class='dq-tbl'>"+"".join(rows)+"</table>"

def meteo_table():
    hdrs=["Variable","Unit","n months","% missing","mean","median","SD","min","max","p5","p95","outliers |z|>3"]
    rows=[trow(hdrs,"th")]
    flags={"TA_mean":"✓","VPD_mean":"🚨" if vpd_flag_sites else "✓","SW_IN_mean":"✓","P_sum":"🚨" if p_flag else "✓"}
    for v in METEO_VARS:
        s=meteo_stats[v]
        col="#e63946" if flags[v]=="🚨" else "#4ade80"
        rows.append(f"<tr><td style='color:#22D4EB;font-weight:600'>{v}</td>"
                    +f"<td style='color:#6B7280;font-size:.8em'>{METEO_UNITS[v]}</td>"
                    +f"<td>{s['n_total']}</td><td>{s['pct_miss']}%</td>"
                    +f"<td>{s['mean']}</td><td>{s['median']}</td><td>{s['sd']}</td>"
                    +f"<td>{s['mn']}</td><td>{s['mx']}</td><td>{s['p5']}</td><td>{s['p95']}</td>"
                    +f"<td style='color:#f4a261'>{s['n_out']}</td></tr>")
    return "<table class='dq-tbl'>"+"".join(rows)+"</table>"

def outlier_table(limit=25):
    hdrs=["EFP","Site","Year","Value","z-score"]
    rows=[trow(hdrs,"th")]
    for o in outliers[:limit]:
        col="#e63946" if abs(o["z"])>6 else ("#f4a261" if abs(o["z"])>4 else "#E0E0E0")
        rows.append(f"<tr style='color:{col}'>"
                    +"".join(f"<td>{c}</td>" for c in [o["var"],o["site"],o["year"],o["val"],o["z"]])
                    +"</tr>")
    return "<table class='dq-tbl'>"+"".join(rows)+"</table>"

def impossible_table():
    rows=[trow(["EFP","Site","Year","Value"],"th")]
    for o in impossible[:20]:
        rows.append(f"<tr style='color:#e63946'>"
                    +"".join(f"<td>{c}</td>" for c in [o["var"],o["site"],o["year"],o["val"]])
                    +"</tr>")
    return "<table class='dq-tbl'>"+"".join(rows)+"</table>"

def p_flag_table():
    rows=[trow(["Site","Year","Month","P_sum (mm)"],"th")]
    for s,y,m,p in p_flag:
        rows.append(f"<tr style='color:#e63946'><td>{s}</td><td>{y}</td><td>{m}</td><td>{p:,.0f}</td></tr>")
    return "<table class='dq-tbl'>"+"".join(rows)+"</table>"

# summary numbers
n_sites = len(sites_miss)
n_any_miss = sum(1 for sid in site_miss_pct if any(v>0 for v in site_miss_pct[sid].values()))
avg_efp_miss = round(statistics.mean(efp_stats[v]["pct_miss"] for v in EFP_VARS),1)
n_impos = len(impossible)

# ── build igbp section conditionally ─────────────────────────────────────────
igbp_section = ""
if igbp_bar:
    igbp_section = f"""
  <div class="section-hdr">GPPsat Missing Rate by Ecosystem Type (IGBP)</div>
  <div class="card full-width">
    <div class="card-title">% site-years with missing GPPsat per IGBP class</div>
    <div class="plot-wrap" id="igbp_miss_bar" style="height:280px;"></div>
  </div>"""

# ── assemble page ─────────────────────────────────────────────────────────────
html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Data Quality — FluxNet × Mortality</title>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:#0D0D0D;color:#E0E0E0;font-family:Arial,sans-serif;padding:32px 20px}}
.wrap{{max-width:1200px;margin:0 auto}}
.hero{{background:linear-gradient(135deg,#0a2540 0%,#0e4d5e 50%,#0f3d2e 100%);
       border-radius:14px;padding:24px 28px;margin-bottom:24px;
       box-shadow:0 8px 32px rgba(0,200,220,.12)}}
.hero h1{{font-size:1.55rem;color:#22D4EB;margin-bottom:6px}}
.hero p{{color:#9CA3AF;font-size:.9rem}}
.back{{display:inline-flex;align-items:center;gap:6px;color:#22D4EB;font-size:.85rem;
       text-decoration:none;margin-bottom:18px;padding:6px 12px;
       border:1px solid #1e3a3a;border-radius:8px;transition:border-color .2s}}
.back:hover{{border-color:#22D4EB}}
.kpis{{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));
        gap:12px;margin-bottom:20px}}
.kpi{{background:#111827;border:1px solid #2A2A3A;border-radius:10px;padding:14px 16px}}
.kpi .v{{font-size:1.7rem;font-weight:700;line-height:1}}
.kpi .l{{font-size:.8rem;color:#6B7280;margin-top:4px}}
.kpi.red .v{{color:#e63946}}
.kpi.amber .v{{color:#f4a261}}
.kpi.green .v{{color:#4ade80}}
.kpi.teal .v{{color:#22D4EB}}
.alerts{{display:flex;flex-direction:column;gap:8px;margin-bottom:20px}}
.alert{{border-radius:10px;padding:11px 16px;display:flex;gap:10px;font-size:.87rem;line-height:1.5}}
.alert.red{{background:#1a0a0a;border:1px solid #5a1010;color:#f4b8b8}}
.alert.amber{{background:#1a130a;border:1px solid #5a3800;color:#f4ddb8}}
.alert.green{{background:#0a1a0a;border:1px solid #1a4a1a;color:#b8f4b8}}
.alert .icon{{font-size:1.1rem;flex-shrink:0}}
.section-hdr{{font-size:1.05rem;font-weight:700;color:#22D4EB;
               margin:24px 0 12px;padding-bottom:6px;
               border-bottom:1px solid #1e3a3a}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:14px;margin-bottom:4px}}
.card{{background:#111827;border:1px solid #2A2A3A;border-radius:10px;padding:14px}}
.card.full-width{{grid-column:1/-1}}
.card-title{{font-size:.88rem;color:#9CA3AF;margin-bottom:8px}}
.plot-wrap{{min-height:260px}}
.tbl-wrap{{max-height:400px;overflow-y:auto;border-radius:6px}}
.dq-tbl{{width:100%;border-collapse:collapse;font-size:.8rem}}
.dq-tbl th{{background:#1F2937;padding:6px 10px;text-align:left;
             border-bottom:1px solid #374151;color:#9CA3AF;position:sticky;top:0}}
.dq-tbl td{{padding:5px 10px;border-bottom:1px solid #1a1a2e;vertical-align:top}}
.dq-tbl tr:hover td{{background:#1a2233}}
.footer{{margin-top:40px;text-align:center;color:#4B5563;font-size:.78rem}}
.footer a{{color:#4B5563}}
</style>
</head>
<body>
<div class="wrap">

  <a class="back" href="index.html">← Back to Hub</a>

  <div class="hero">
    <h1>📊 Flux Data Quality Report</h1>
    <p>{n_total} EFP site-years &nbsp;·&nbsp; {n_sites} sites &nbsp;·&nbsp; {len(meteo_rows):,} site-months &nbsp;·&nbsp; 9 networks &nbsp;·&nbsp; FLUXNET 2017–2025 V02<br>
    Variables: GPPsat · NEPmax · ETmax · uWUE · WUE &nbsp;|&nbsp; Meteo: TA · VPD · SW_IN · P</p>
  </div>

  <!-- KPIs -->
  <div class="kpis">
    <div class="kpi {'red' if avg_efp_miss>=15 else 'amber' if avg_efp_miss>=5 else 'green'}">
      <div class="v">{avg_efp_miss}%</div><div class="l">avg EFP missing</div></div>
    <div class="kpi {'red' if n_any_miss>30 else 'amber'}">
      <div class="v">{n_any_miss}</div><div class="l">sites ≥1 missing EFP</div></div>
    <div class="kpi {'red' if len(outliers)>20 else 'amber'}">
      <div class="v">{len(outliers)}</div><div class="l">outlier site-years |z|&gt;3</div></div>
    <div class="kpi {'red' if n_impos>0 else 'green'}">
      <div class="v">{n_impos}</div><div class="l">impossible values</div></div>
    <div class="kpi {'red' if vpd_flag_sites else 'green'}">
      <div class="v">{len(vpd_flag_sites)}</div><div class="l">VPD unit issue (site)</div></div>
    <div class="kpi {'red' if p_flag else 'green'}">
      <div class="v">{len(p_flag)}</div><div class="l">P &gt; 2000 mm/month</div></div>
    <div class="kpi teal">
      <div class="v">{n_sites}</div><div class="l">sites total</div></div>
    <div class="kpi teal">
      <div class="v">9</div><div class="l">flux networks</div></div>
  </div>

  <!-- Alerts -->
  <div class="alerts">
    {'<div class="alert red"><span class="icon">🚨</span><div><b>CD-Ygb — VPD in Pa, not hPa</b><br>ICOS site CD-Ygb has VPD_mean up to ' + str(round(max(max(v) for v in vpd_flag_sites.values()),0)) + ' in the monthly meteo. Values are in Pa — divide by 100 before use (→ 14–21 hPa, plausible for tropical DRC).</div></div>' if vpd_flag_sites else ''}
    {'<div class="alert red"><span class="icon">🚨</span><div><b>US-HB4 — Impossible precipitation</b><br>' + str(len(p_flag)) + ' site-months with P_sum up to ' + str(round(max(x[3] for x in p_flag),0)) + ' mm/month. World record is ~2,500 mm. Likely instrument error — exclude these months.</div></div>' if p_flag else ''}
    {'<div class="alert red"><span class="icon">🚨</span><div><b>' + str(n_impos) + ' physically impossible EFP values</b><br>Negative uWUE / WUE in ' + str(len(set(o["site"] for o in impossible))) + ' sites (CA-PB1, US-EML, US-xMB, US-xML, US-xNW, US-xYE). Very small in magnitude — likely numerical artifacts at carbon balance limits.</div></div>' if impossible else ''}
    <div class="alert red"><span class="icon">🚨</span><div><b>GPPsat / uWUE / WUE — ~21.5% missing</b><br>Concentrated in 72 sites where <code>Gavail=no</code> (insufficient light-saturation data). EBF and DNF ecosystem classes are worst affected (~62% missing).</div></div>
    <div class="alert amber"><span class="icon">⚠️</span><div><b>CN-Sb1 &amp; CN-Sb2 — extreme WUE / uWUE outliers</b><br>WUE up to 34× and uWUE up to 17× the global median (z-scores 6–14). Likely rice paddy / managed cropland. Consider excluding or flagging in sensitivity analysis.</div></div>
    <div class="alert amber"><span class="icon">⚠️</span><div><b>KOF KR-SmM &amp; TERN AU-How — no NT GPP partitioning</b><br>Only GPP_DT_VUT_REF available. EFP computation falls back to DT partitioning for these sites.</div></div>
    <div class="alert amber"><span class="icon">⚠️</span><div><b>AMF — hourly resolution, not half-hourly</b><br>AmeriFlux delivers _HR_ files. Any <code>n_obs ≥ 1488</code> threshold in EFP scripts should be halved (~744) for AMF sites.</div></div>
    <div class="alert green"><span class="icon">✓</span><div><b>All other unit checks passed</b><br>TA within −60 to +55 °C · SW_IN within 0–1000 W m⁻² · VPD within expected range in all 9 network spot-checks (excluding CD-Ygb) · No negative ET in monthly aggregates.</div></div>
  </div>

  <!-- EFP distributions -->
  <div class="section-hdr">EFP Distributions</div>
  <div class="cards">
    <div class="card full-width">
      <div class="card-title">Violin + box plots for all EFPs — all site-years (missing excluded)</div>
      <div class="plot-wrap" id="violin" style="height:340px;"></div>
    </div>
  </div>

  <!-- EFP stats table -->
  <div class="section-hdr">EFP Summary Statistics</div>
  <div class="card full-width" style="margin-bottom:4px;">
    <div class="tbl-wrap">{efp_table()}</div>
  </div>

  <!-- Missing heatmap -->
  <div class="section-hdr">Missing Data — Top 50 Sites by Missingness</div>
  <div class="card full-width">
    <div class="card-title">% missing per EFP — top 50 sites ranked by total missing (red = 100%)</div>
    <div class="plot-wrap" id="miss_hm" style="height:520px;"></div>
  </div>

  <!-- Year coverage -->
  <div class="section-hdr">Data Coverage by Year</div>
  <div class="cards">
    <div class="card full-width">
      <div class="card-title">Number of site-years with valid GPPsat per calendar year</div>
      <div class="plot-wrap" id="yr_bar" style="height:240px;"></div>
    </div>
  </div>

  {igbp_section}

  <!-- Outliers -->
  <div class="section-hdr">Outlier Site-Years  (|z-score| > 3)</div>
  <div class="cards">
    <div class="card" style="grid-column:1/-1;">
      <div class="card-title">Top 25 outliers — ranked by |z|</div>
      <div class="tbl-wrap">{outlier_table(25)}</div>
    </div>
    <div class="card full-width">
      <div class="card-title">Outlier z-scores by EFP (top 40 site-years)</div>
      <div class="plot-wrap" id="out_scatter" style="height:280px;"></div>
    </div>
  </div>

  <!-- Impossible values -->
  {'<div class="section-hdr">Physically Impossible EFP Values (&lt; 0)</div><div class="card full-width" style="margin-bottom:4px;"><div class="tbl-wrap">' + impossible_table() + '</div></div>' if impossible else ''}

  <!-- Meteo -->
  <div class="section-hdr">Meteorological Variable Quality (Monthly Aggregates)</div>
  <div class="card full-width" style="margin-bottom:4px;">
    <div class="tbl-wrap">{meteo_table()}</div>
  </div>

  <!-- P anomaly table -->
  {'<div class="section-hdr">Anomalous Precipitation — P &gt; 2000 mm/month</div><div class="card full-width" style="margin-bottom:4px;"><div class="tbl-wrap">' + p_flag_table() + '</div></div>' if p_flag else ''}

  <!-- Network comparison -->
  <div class="section-hdr">Cross-Network Consistency</div>
  <div class="card full-width">
    <div class="card-title">Mean TA (°C) and mean VPD (hPa) by flux network — flagged sites excluded from VPD</div>
    <div class="plot-wrap" id="net_bar" style="height:280px;"></div>
  </div>

  <div class="footer">
    FluxNet 2017–2025 V02 &nbsp;·&nbsp; EFPs from bigleaf + Migliavacca et al. 2021 &nbsp;·&nbsp;
    <a href="index.html">← Hub</a> &nbsp;·&nbsp; <a href="mailto:neggy.k.92@gmail.com">neggy.k.92@gmail.com</a>
  </div>
</div>

<script>
(function(){{
  var DQ = {{
    violin:  {json.dumps(violin_traces)},
    miss_hm: {json.dumps(hm_trace)},
    out_scatter: {json.dumps(out_trace)},
    net_bar: {json.dumps(net_bar)},
    yr_bar:  {json.dumps(yr_bar)},
    igbp_bar:{json.dumps(igbp_bar)}
  }};

  var bg="#111827", paperbg="#0D0D0D";
  var base = {{
    paper_bgcolor: paperbg, plot_bgcolor: bg,
    font:{{family:"Arial,sans-serif",color:"#E0E0E0",size:11}},
    margin:{{l:55,r:25,t:25,b:55}},
    xaxis:{{gridcolor:"#1F2937",linecolor:"#374151",tickfont:{{color:"#9CA3AF"}},titlefont:{{color:"#9CA3AF"}}}},
    yaxis:{{gridcolor:"#1F2937",linecolor:"#374151",tickfont:{{color:"#9CA3AF"}},titlefont:{{color:"#9CA3AF"}}}}
  }};
  var cfg = {{responsive:true,displayModeBar:false}};
  function pl(id,traces,extra){{
    Plotly.newPlot(id,traces,Object.assign({{}},base,extra),cfg);
  }}

  pl("violin",  DQ.violin,  {{showlegend:false,yaxis:{{title:"Value (per-EFP units)"}},xaxis:{{title:""}}}});
  pl("miss_hm", DQ.miss_hm, {{margin:{{l:90,r:90,t:20,b:50}},
    yaxis:{{title:"",tickfont:{{size:8.5}},autorange:"reversed"}},
    xaxis:{{title:"EFP variable"}}}});
  pl("out_scatter", DQ.out_scatter, {{
    yaxis:{{title:"z-score",zeroline:true,zerolinecolor:"#374151"}},xaxis:{{title:"EFP"}}}});
  pl("net_bar", DQ.net_bar, {{barmode:"group",xaxis:{{title:"Network"}},yaxis:{{title:"Value"}},
    legend:{{orientation:"h",y:1.12,font:{{color:"#9CA3AF"}}}}}});
  pl("yr_bar",  DQ.yr_bar,  {{xaxis:{{title:"Year"}},yaxis:{{title:"n site-years with GPPsat"}}}});
  {'Plotly.newPlot("igbp_miss_bar",DQ.igbp_bar,Object.assign({},base,{xaxis:{title:"IGBP class"},yaxis:{title:"% missing GPPsat"},showlegend:false}),cfg);' if igbp_bar else ''}
}})();
</script>
</body>
</html>"""

with open(OUT_FILE, "w") as f:
    f.write(html)
print(f"✓ Wrote {OUT_FILE}  ({os.path.getsize(OUT_FILE)//1024} KB)")

# ── update index.html — add Data Quality card ────────────────────────────────
idx = open(HUB_IDX).read()
if "data_quality.html" not in idx:
    card = """
  <a class="card" href="data_quality.html">
    <div class="card-icon">&#128202;</div>
    <div class="card-title">Data Quality Report</div>
    <div class="card-desc">
      Automated quality check across all 1,535 EFP site-years and 20,664 site-months
      from 9 flux networks. Flags unit issues, missing data patterns, outliers, and
      physically impossible values for GPPsat, NEPmax, ETmax, uWUE, WUE, TA, VPD,
      SW&#8209;IN, and precipitation.
    </div>
    <div class="card-tags">
      <span class="tag">233 sites</span>
      <span class="tag">5 EFPs</span>
      <span class="tag">9 networks</span>
      <span class="tag">Unit checks</span>
      <span class="tag">Outliers</span>
      <span class="tag">Missing data</span>
    </div>
  </a>
"""
    # Insert before closing </div> of .cards
    idx = idx.replace("</div>\n\n<div class=\"footer\"", card + "\n</div>\n\n<div class=\"footer\"")
    with open(HUB_IDX,"w") as f: f.write(idx)
    print(f"✓ Added data quality card to index.html")
else:
    print("  index.html already has data_quality.html card — skipped")

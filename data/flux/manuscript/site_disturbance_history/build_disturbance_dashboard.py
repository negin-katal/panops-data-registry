import csv
import json
import re
from pathlib import Path

BASE = Path('.')
FILES = sorted(BASE.glob('batch*.md'))

EXPECTED = [
    'Site_ID', 'IGBP', 'LAT', 'LON', 'Vegetation_Type', 'Disturbance_Type',
    'Disturbance_Year', 'Intensity', 'Notes', 'Source'
]


def clean_val(v: str) -> str:
    v = v.strip()
    if v == '\u2014' or v == '—':
        return ''
    return re.sub(r'\s+', ' ', v)


def parse_table_rows(lines):
    in_table = False
    header = None
    rows = []

    for raw in lines:
        line = raw.rstrip('\n')
        if not line.startswith('|'):
            in_table = False
            continue

        parts = [p.strip() for p in line.strip('|').split('|')]
        if len(parts) < 2:
            continue

        # Separator rows like |-----|-----|
        if all(re.fullmatch(r':?-{3,}:?', p or '-') for p in parts):
            continue

        if not in_table:
            header = parts
            in_table = True
            continue

        if header and len(parts) >= len(header):
            row = dict(zip(header, parts[:len(header)]))
            rows.append(row)

    return rows


all_rows = []
for f in FILES:
    txt = f.read_text(encoding='utf-8', errors='ignore').splitlines()
    rows = parse_table_rows(txt)
    for r in rows:
        if 'Site_ID' not in r:
            continue
        # Keep only expected columns if available
        out = {k: clean_val(r.get(k, '')) for k in EXPECTED}
        out['Batch_File'] = f.name
        all_rows.append(out)

# Deduplicate by Site_ID, preferring first appearance
seen = set()
dedup = []
for r in all_rows:
    sid = r.get('Site_ID', '').strip()
    if not sid or sid in seen:
        continue
    seen.add(sid)
    dedup.append(r)

# Derive flags and categories
for r in dedup:
    dt = r['Disturbance_Type'].lower()
    dy = r['Disturbance_Year']
    has_dist = not (
        dt in ('none documented', 'none')
        or (not dt)
    )
    r['Has_Disturbance'] = 'Yes' if has_dist else 'No'

    # Coarse disturbance class
    if not has_dist:
        cls = 'None documented'
    elif 'fire' in dt or 'wildfire' in dt or 'burn' in dt:
        cls = 'Fire'
    elif 'drought' in dt:
        cls = 'Drought/Climate'
    elif 'bark beetle' in dt or 'beetle' in dt:
        cls = 'Biotic outbreak'
    elif 'graz' in dt:
        cls = 'Grazing'
    elif 'thinning' in dt or 'harvest' in dt or 'logging' in dt or 'clear-cut' in dt or 'clearcut' in dt or 'coppice' in dt:
        cls = 'Forest management/Harvest'
    elif 'drainage' in dt or 'rewetting' in dt or 'hydrolog' in dt or 'tidal restoration' in dt or 'flood' in dt:
        cls = 'Hydrology/Restoration'
    elif 'land use' in dt or 'afforestation' in dt or 'plantation' in dt or 'conversion' in dt:
        cls = 'Land-use change'
    elif 'permafrost' in dt or 'thermokarst' in dt:
        cls = 'Permafrost/Geomorphic'
    else:
        cls = 'Other/Unknown'
    r['Disturbance_Class'] = cls

    # Normalize free-text intensity into a compact comparison class.
    i_txt = (r['Intensity'] or '').lower()
    if not i_txt or i_txt == 'unknown':
      i_cls = 'Unknown'
    elif 'stand-replacing' in i_txt:
      i_cls = 'Stand-replacing'
    elif 'partial' in i_txt:
      i_cls = 'Partial'
    elif 'low' in i_txt:
      i_cls = 'Low'
    elif 'moderate' in i_txt:
      i_cls = 'Moderate'
    elif 'high' in i_txt or 'severe' in i_txt:
      i_cls = 'High/Severe'
    elif 'historical' in i_txt:
      i_cls = 'Historical/Legacy'
    else:
      i_cls = 'Other/Unclassified'
    r['Intensity_Class'] = i_cls

    # parse first 4-digit year if present
    m = re.search(r'(19\d{2}|20\d{2})', dy)
    r['Year_First'] = int(m.group(1)) if m else ''

# Write combined CSV
csv_path = BASE / 'disturbance_history_combined.csv'
with csv_path.open('w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            'Site_ID','IGBP','LAT','LON','Vegetation_Type','Disturbance_Type','Disturbance_Year','Intensity','Notes','Source','Batch_File',
          'Has_Disturbance','Disturbance_Class','Intensity_Class','Year_First'
        ]
    )
    writer.writeheader()
    writer.writerows(dedup)

json_path = BASE / 'disturbance_history_combined.json'
json_path.write_text(json.dumps(dedup, ensure_ascii=False, indent=2), encoding='utf-8')

# Build compact summary stats
n_total = len(dedup)
n_yes = sum(1 for r in dedup if r['Has_Disturbance'] == 'Yes')
n_no = n_total - n_yes

from collections import Counter

by_class = Counter(r['Disturbance_Class'] for r in dedup)
by_intensity = Counter((r['Intensity'] or 'Unknown') for r in dedup)
by_intensity_class = Counter(r['Intensity_Class'] for r in dedup)
by_igbp = Counter(r['IGBP'] for r in dedup)

summary = {
    'total_sites': n_total,
    'with_disturbance': n_yes,
    'without_disturbance': n_no,
    'share_with_disturbance': round((n_yes / n_total) * 100, 1) if n_total else 0,
    'by_disturbance_class': dict(by_class),
    'by_intensity': dict(by_intensity),
    'by_intensity_class': dict(by_intensity_class),
    'by_igbp': dict(by_igbp),
}

(BASE / 'disturbance_summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')

# Generate interactive HTML dashboard (Plotly + vanilla JS)
html = '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Flux Site Disturbance Dashboard</title>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  <style>
    :root {{
      --bg: #f4f1ea;
      --panel: #fffdf8;
      --ink: #1d1a16;
      --muted: #6a655c;
      --accent: #005f73;
      --accent2: #ca6702;
      --line: #ddd4c4;
    }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; font-family: "Source Sans 3", "Segoe UI", sans-serif; color: var(--ink); background: radial-gradient(circle at 20% 10%, #fff6e6 0%, var(--bg) 45%, #efe8dc 100%); }}
    .wrap {{ max-width: 1300px; margin: 0 auto; padding: 20px; }}
    .hero {{ background: linear-gradient(135deg, #005f73 0%, #0a9396 40%, #94d2bd 100%); color: white; border-radius: 16px; padding: 22px 24px; box-shadow: 0 8px 24px rgba(0,0,0,.12); }}
    h1 {{ margin: 0 0 8px; font-size: 1.6rem; }}
    .sub {{ margin: 0; opacity: .95; }}
    .grid {{ display: grid; gap: 14px; margin-top: 16px; }}
    .kpis {{ grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); }}
    .kpi {{ background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 12px; }}
    .kpi .v {{ font-size: 1.5rem; font-weight: 700; color: var(--accent); }}
    .kpi .l {{ color: var(--muted); font-size: .9rem; }}
    .filters {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 10px; background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 12px; }}
    label {{ font-size: .85rem; color: var(--muted); display: block; margin-bottom: 4px; }}
    select, input {{ width: 100%; border: 1px solid var(--line); border-radius: 8px; padding: 8px; background: white; }}
    .charts {{ grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); }}
    .card {{ background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 10px; min-height: 330px; }}
    .table-wrap {{ background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 10px; overflow: auto; }}
    table {{ width: 100%; border-collapse: collapse; font-size: .9rem; }}
    th, td {{ text-align: left; border-bottom: 1px solid #eee4d1; padding: 6px; vertical-align: top; }}
    th {{ position: sticky; top: 0; background: #fff7ec; }}
    .actions {{ display: flex; gap: 8px; flex-wrap: wrap; }}
    button {{ border: 0; border-radius: 8px; padding: 8px 12px; background: var(--accent2); color: white; cursor: pointer; }}
    .note {{ color: var(--muted); font-size: .85rem; margin-top: 8px; }}
  </style>
</head>
<body>
  <div class="wrap">
    <section class="hero">
      <h1>Flux Site Disturbance Dashboard</h1>
      <p class="sub">Interactive overview from the five disturbance-history batches. Filter by disturbance, intensity, year, site, IGBP, and batch.</p>
    </section>

    <section class="grid kpis" id="kpis"></section>

    <section class="filters" id="filters">
      <div><label>Disturbance class</label><select id="fClass"></select></div>
      <div><label>Has disturbance</label><select id="fHas"></select></div>
      <div><label>Intensity class</label><select id="fIntensity"></select></div>
      <div><label>IGBP</label><select id="fIGBP"></select></div>
      <div><label>Batch file</label><select id="fBatch"></select></div>
      <div><label>Year (first, min)</label><input id="fYearMin" type="number" placeholder="e.g. 2000" /></div>
      <div><label>Year (first, max)</label><input id="fYearMax" type="number" placeholder="e.g. 2024" /></div>
      <div><label>Site contains</label><input id="fSite" type="text" placeholder="e.g. US- or DE-" /></div>
      <div class="actions" style="align-items:end;"><button id="resetBtn">Reset filters</button></div>
    </section>

    <section class="grid charts">
      <div class="card"><div id="cHas" style="height:300px;"></div></div>
      <div class="card"><div id="cType" style="height:300px;"></div></div>
      <div class="card"><div id="cTypeRaw" style="height:300px;"></div></div>
      <div class="card"><div id="cIntensity" style="height:300px;"></div></div>
      <div class="card"><div id="cIGBP" style="height:300px;"></div></div>
      <div class="card"><div id="cYear" style="height:300px;"></div></div>
    </section>

    <section class="table-wrap">
      <table id="tbl">
        <thead><tr>
          <th>Site_ID</th><th>IGBP</th><th>Has_Disturbance</th><th>Disturbance_Class</th><th>Disturbance_Type</th><th>Year</th><th>Intensity</th><th>Batch</th>
        </tr></thead>
        <tbody></tbody>
      </table>
      <div class="note">Tip: use browser find (Ctrl/Cmd+F) for notes or specific source terms after filtering.</div>
    </section>
  </div>

  <script>
    const DATA = __DATA__;

    const $ = (id) => document.getElementById(id);
    const fields = ['fClass','fHas','fIntensity','fIGBP','fBatch'];

    function unique(arr) {{ return [...new Set(arr)].filter(x => x !== '').sort(); }}

    function fillSelect(id, values) {{
      const sel = $(id);
      sel.innerHTML = '';
      const all = document.createElement('option');
      all.value = '';
      all.textContent = 'All';
      sel.appendChild(all);
      values.forEach(v => {{
        const o = document.createElement('option');
        o.value = v;
        o.textContent = v;
        sel.appendChild(o);
      }});
    }}

    function countBy(rows, key) {{
      const m = new Map();
      rows.forEach(r => m.set(r[key] || 'Unknown', (m.get(r[key] || 'Unknown') || 0) + 1));
      return [...m.entries()].sort((a,b) => b[1]-a[1]);
    }}

    function filtered() {{
      const classV = $('fClass').value;
      const hasV = $('fHas').value;
      const intensityV = $('fIntensity').value;
      const igbpV = $('fIGBP').value;
      const batchV = $('fBatch').value;
      const siteQ = $('fSite').value.trim().toLowerCase();
      const yMin = $('fYearMin').value ? Number($('fYearMin').value) : null;
      const yMax = $('fYearMax').value ? Number($('fYearMax').value) : null;

      return DATA.filter(r => {{
        if (classV && r.Disturbance_Class !== classV) return false;
        if (hasV && r.Has_Disturbance !== hasV) return false;
        if (intensityV && (r.Intensity_Class || 'Unknown') !== intensityV) return false;
        if (igbpV && r.IGBP !== igbpV) return false;
        if (batchV && r.Batch_File !== batchV) return false;
        if (siteQ && !r.Site_ID.toLowerCase().includes(siteQ)) return false;
        const y = Number(r.Year_First);
        if (yMin !== null && (!y || y < yMin)) return false;
        if (yMax !== null && (!y || y > yMax)) return false;
        return true;
      }});
    }}

    function renderKPIs(rows) {{
      const total = rows.length;
      const withD = rows.filter(r => r.Has_Disturbance === 'Yes').length;
      const withoutD = total - withD;
      const share = total ? ((withD/total)*100).toFixed(1) : '0.0';
      const topClass = countBy(rows, 'Disturbance_Class')[0]?.[0] || 'n/a';
      const topIGBP = countBy(rows, 'IGBP')[0]?.[0] || 'n/a';

      $('kpis').innerHTML = [
        ['Sites (filtered)', total],
        ['With disturbance', withD],
        ['Without disturbance', withoutD],
        ['Share with disturbance (%)', share],
        ['Top disturbance class', topClass],
        ['Top IGBP', topIGBP],
      ].map(([l,v]) => `<div class="kpi"><div class="v">${{v}}</div><div class="l">${{l}}</div></div>`).join('');
    }}

    function bar(divId, rows, key, title, color, limit=null) {{
      let c = countBy(rows, key);
      if (limit) c = c.slice(0, limit);
      Plotly.react(divId, [{
        type: 'bar',
        x: c.map(d=>d[0]),
        y: c.map(d=>d[1]),
        marker: {{color}}
      }}], {{
        title, margin: {{l:40,r:10,t:45,b:80}},
        xaxis: {{tickangle: -35, automargin: true}},
        yaxis: {{title: 'Count'}}
      }}, {{displayModeBar:false, responsive:true}});
    }}

    function yearHist(rows) {{
      const years = rows.map(r => Number(r.Year_First)).filter(y => Number.isFinite(y) && y > 0);
      Plotly.react('cYear', [{
        type: 'histogram', x: years, nbinsx: 20, marker: {{color:'#94d2bd'}}
      }], {{title:'Disturbance year distribution (first parsed year)', margin: {{l:40,r:10,t:45,b:45}}, xaxis: {{title:'Year'}}, yaxis: {{title:'Count'}}}}, {{displayModeBar:false, responsive:true}});
    }}

    function renderTable(rows) {{
      const tbody = $('tbl').querySelector('tbody');
      tbody.innerHTML = rows
        .sort((a,b) => a.Site_ID.localeCompare(b.Site_ID))
        .map(r => `<tr>
          <td>${{r.Site_ID}}</td>
          <td>${{r.IGBP}}</td>
          <td>${{r.Has_Disturbance}}</td>
          <td>${{r.Disturbance_Class}}</td>
          <td>${{r.Disturbance_Type}}</td>
          <td>${{r.Disturbance_Year}}</td>
          <td>${{r.Intensity || 'Unknown'}}</td>
          <td>${{r.Batch_File}}</td>
        </tr>`).join('');
    }}

    function render() {{
      const rows = filtered();
      renderKPIs(rows);
      bar('cHas', rows, 'Has_Disturbance', 'Sites with vs without disturbance', '#ee9b00');
      bar('cType', rows, 'Disturbance_Class', 'Disturbance class', '#0a9396');
      bar('cTypeRaw', rows, 'Disturbance_Type', 'Disturbance type (top 15)', '#bb3e03', 15);
      bar('cIntensity', rows, 'Intensity_Class', 'Intensity class', '#ca6702');
      bar('cIGBP', rows, 'IGBP', 'IGBP classes', '#005f73');
      yearHist(rows);
      renderTable(rows);
    }}

    function init() {{
      fillSelect('fClass', unique(DATA.map(d => d.Disturbance_Class)));
      fillSelect('fHas', unique(DATA.map(d => d.Has_Disturbance)));
      fillSelect('fIntensity', unique(DATA.map(d => d.Intensity_Class || 'Unknown')));
      fillSelect('fIGBP', unique(DATA.map(d => d.IGBP)));
      fillSelect('fBatch', unique(DATA.map(d => d.Batch_File)));

      [...fields, 'fYearMin', 'fYearMax', 'fSite'].forEach(id => $(id).addEventListener('input', render));
      [...fields].forEach(id => $(id).addEventListener('change', render));

      $('resetBtn').addEventListener('click', () => {{
        [...fields].forEach(id => $(id).value = '');
        $('fYearMin').value = '';
        $('fYearMax').value = '';
        $('fSite').value = '';
        render();
      }});

      render();
    }}

    init();
  </script>
</body>
</html>
'''

html = html.replace('{{', '{').replace('}}', '}')
html = html.replace('__DATA__', json.dumps(dedup, ensure_ascii=False))

(BASE / 'disturbance_dashboard.html').write_text(html, encoding='utf-8')

print(f"Wrote {csv_path}")
print(f"Wrote {json_path}")
print(f"Wrote disturbance_summary.json")
print(f"Wrote disturbance_dashboard.html")
print(json.dumps(summary, indent=2))

#!/usr/bin/env python3
"""
Build LaTeX metric tables from v2 RF outputs.

1. table_RF_LOSO_results_v2.tex  — R² (RMSE) for all 5 EFPs, M01-M08,
   panels A-D (12m anomaly / 24m anomaly / 12m rawmem / 24m rawmem)

2. table_RMSE_ratio_v2.tex — RMSE(with D)/RMSE(without D) per IGBP × EFP
   for the 4 comparison pairs (now including WUE)
"""
import csv, math
from collections import defaultdict

BASE   = "derived_tables/outputs_afterEGU_results"
TABLE  = "manuscript/tables"

ANOM_M = f"{BASE}/RF_outputs_anomaly_24mbench_v2/RF_metrics_LOSO.csv"
RAWM_M = f"{BASE}/RF_outputs_rawmem_24mbench_v2/RF_metrics_LOSO.csv"
ANOM_P = f"{BASE}/RF_outputs_anomaly_24mbench_v2/RF_predictions_LOSO.csv"
RAWM_P = f"{BASE}/RF_outputs_rawmem_24mbench_v2/RF_predictions_LOSO.csv"
MODEL_CSV = f"{BASE}/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"

EFP_ORDER  = ["GPPsat","NEPmax","ETmax","uWUE","WUE"]
EFP_LABELS = {
    "GPPsat": r"GPP$_\mathrm{sat}$",
    "NEPmax": r"NEP$_\mathrm{max}$",
    "ETmax":  r"ET$_\mathrm{max}$",
    "uWUE":   r"uWUE",
    "WUE":    r"WUE",
}
EFP_UNITS = {
    "GPPsat": r"($\mu$mol m$^{-2}$ s$^{-1}$)",
    "NEPmax": r"($\mu$mol m$^{-2}$ s$^{-1}$)",
    "ETmax":  r"(mm d$^{-1}$)",
    "uWUE":   r"(g C mm$^{-1}$)",
    "WUE":    r"(g C mm$^{-1}$)",
}
MODEL_LABELS = {
    "M01":"C","M02":"C + D","M03":"C + T","M04":"C + T + D",
    "M05":"C + M","M06":"C + D + M","M07":"C + T + M","M08":"C + T + D + M",
}

def load_metrics(path):
    """Return dict: (model_key, window, response) → {RMSE, R2, n_rows, n_sites}"""
    d = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            m = row["model"]                 # e.g. M01_12m_GPPsat
            parts = m.split("_")
            mkey  = parts[0]                 # M01
            win   = parts[1]                 # 12m
            resp  = "_".join(parts[2:])      # GPPsat (or uWUE etc.)
            d[(mkey, win, resp)] = {
                "RMSE":    float(row["RMSE"]),
                "R2":      float(row["R2"]),
                "n_rows":  row["n_rows"],
                "n_sites": row["n_sites"],
            }
    return d

anom = load_metrics(ANOM_M)
rawm = load_metrics(RAWM_M)

# ── Table 1: R² (RMSE) per model × EFP ──────────────────────────────────────
PANELS = [
    ("A", "12m", "anomaly", anom, "Anomaly z-score EFP memory"),
    ("B", "24m", "anomaly", anom, "Anomaly z-score EFP memory"),
    ("C", "12m", "rawmem",  rawm, "Raw-lag EFP memory"),
    ("D", "24m", "rawmem",  rawm, "Raw-lag EFP memory"),
]
MODELS = ["M01","M02","M03","M04","M05","M06","M07","M08"]

def fmt_cell(r2, rmse, bold=False):
    r2s   = f"{r2:.3f}"
    rmsed = f"{rmse:.3f}" if rmse < 1 else f"{rmse:.2f}"
    core  = f"{r2s} ({rmsed})"
    return rf"\textbf{{{core}}}" if bold else core

# n_cols = 3 (Model, Predictors, n) + 5 EFPs
n_efp = len(EFP_ORDER)
col_spec = "ll" + "r" * (1 + n_efp)   # Model Predictors n EFP*5

efp_header1 = " & ".join(EFP_LABELS[e] for e in EFP_ORDER)
efp_header2 = " & ".join(EFP_UNITS[e]  for e in EFP_ORDER)

lines = []
lines.append(r"\begin{table}[htbp]")
lines.append(r"\centering")
lines.append(r"""\caption{Leave-one-site-out random forest performance for five ecosystem
functional properties (EFPs), evaluated on a unified benchmark --- the set of
site-years with complete 24-month predictor data (v2: fixed data quality).
Each cell shows $R^2$ (RMSE in native units). \textbf{Bold} = best $R^2$
per EFP within each panel. Panels A--B: anomaly z-score EFP memory;
Panels C--D: raw-lag EFP memory.}""")
lines.append(r"\label{tab:RF_LOSO_v2}")
lines.append(r"\footnotesize")
lines.append(rf"\begin{{tabular}}{{ll{'c' * (1 + n_efp)}}}")
lines.append(r"\toprule")
lines.append(
    r"Model & Predictors & $n$ & " + efp_header1 + r" \\"
)
lines.append(r"  &  &  & " + efp_header2 + r" \\")
lines.append(r"\midrule")

for panel_lbl, win, mem_key, metrics, mem_desc in PANELS:
    # find n_rows and n_sites (same for all models in this panel)
    sample = metrics.get(("M01", win, "GPPsat"), {})
    n_rows  = sample.get("n_rows",  "?")
    n_sites = sample.get("n_sites", "?")

    lines.append(
        rf"\multicolumn{{{2 + n_efp + 1}}}{{l}}{{\textit{{Panel {panel_lbl}: "
        rf"{win} window --- {mem_desc} --- {n_rows} site-years, {n_sites} sites}}}} \\"
    )
    lines.append(r"\midrule")

    # best R² per EFP in this panel
    best_r2 = {}
    for efp in EFP_ORDER:
        vals = [metrics[(mk, win, efp)]["R2"]
                for mk in MODELS if (mk, win, efp) in metrics]
        best_r2[efp] = max(vals) if vals else None

    for i, mk in enumerate(MODELS):
        cells = [mk, MODEL_LABELS[mk]]
        cells.append(r"\multirow{8}{*}{" + str(n_rows) + "}" if i == 0 else "")
        for efp in EFP_ORDER:
            key = (mk, win, efp)
            if key in metrics:
                m  = metrics[key]
                is_best = best_r2[efp] is not None and abs(m["R2"] - best_r2[efp]) < 1e-6
                cells.append(fmt_cell(m["R2"], m["RMSE"], bold=is_best))
            else:
                cells.append("---")
        lines.append(" & ".join(cells) + r" \\")

    lines.append(r"\midrule")

lines.append(r"\bottomrule")
lines.append(r"\end{tabular}")
lines.append(r"\vspace{2pt}")
lines.append(r"\begin{minipage}{\linewidth}")
lines.append(r"\footnotesize")
lines.append(
    r"""\textit{Note:} C = Climate (monthly TA, VPD, SW$_\mathrm{IN}$ mean/p05/p95;
P mean, sum, $P_\mathrm{p05}$, $P_\mathrm{p95}$); T = Plant traits (hydraulic, leaf, root);
D = Disturbance (mortality intensity, deadwood, forest loss at 100--500\,m);
M = EFP memory (anomaly z-score in Panels A--B; raw lag-1/lag-2 values in Panels C--D).
RMSE in native units in parentheses. Data quality v2: negative uWUE/WUE set to NA;
CN-Sb1/CN-Sb2 extreme outliers removed; US-HB4 anomalous precipitation months set to NA."""
)
lines.append(r"\end{minipage}")
lines.append(r"\end{table}")

out1 = f"{TABLE}/table_RF_LOSO_results_v2.tex"
with open(out1, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"✓ Wrote {out1}")

# ── Table 2: RMSE ratio per IGBP × EFP (now includes WUE) ───────────────────
# Load predictions and site IGBP
igbp_map = {}
with open(MODEL_CSV) as f:
    for row in csv.DictReader(f):
        igbp_map[row["SITE_ID"]] = row.get("IGBP","?")

IGBP_ORDER = ["ENF","EBF","DNF","DBF","MF","CSH","OSH","WSA","SAV","WET"]
PAIRS = [
    ("M01","M02","C vs C$+$D"),
    ("M03","M04","C$+$T vs C$+$T$+$D"),
    ("M05","M06","C$+$M vs C$+$D$+$M"),
    ("M07","M08","C$+$T$+$M vs C$+$T$+$D$+$M"),
]

def load_rmse_by_igbp(pred_path, win="24m"):
    """Per-site RMSE for every model × EFP combo at given window."""
    site_sq = defaultdict(lambda: defaultdict(list))  # (model,efp) → site → [sq_err]
    with open(pred_path) as f:
        for row in csv.DictReader(f):
            m = row["model"]
            if f"_{win}_" not in m:
                continue
            parts = m.split("_")
            mk   = parts[0]
            efp  = "_".join(parts[2:])
            site = row["SITE_ID"]
            try:
                obs  = float(row["observed"])
                pred = float(row["predicted"])
                site_sq[(mk,efp)][site].append((obs-pred)**2)
            except:
                pass
    # Collapse to per-site RMSE
    site_rmse = defaultdict(dict)
    for (mk,efp), sites in site_sq.items():
        for site, sq in sites.items():
            site_rmse[(mk,efp)][site] = math.sqrt(sum(sq)/len(sq))
    return site_rmse

anom_rmse = load_rmse_by_igbp(ANOM_P, "24m")

def igbp_ratio(base_mk, dist_mk, efp, igbp_filter=None):
    base_r = anom_rmse.get((base_mk, efp), {})
    dist_r = anom_rmse.get((dist_mk, efp), {})
    common = set(base_r) & set(dist_r)
    if igbp_filter:
        common = {s for s in common if igbp_map.get(s,"?") == igbp_filter}
    if not common:
        return None
    b = math.sqrt(sum(base_r[s]**2 for s in common)/len(common))
    d = math.sqrt(sum(dist_r[s]**2 for s in common)/len(common))
    return d/b if b > 0 else None

def fmt_ratio(r):
    if r is None: return "---"
    s = f"{r:.3f}"
    if r < 1.0 - 1e-4:
        return rf"\textbf{{{s}}}"
    elif r > 1.0 + 1e-4:
        return rf"\textit{{{s}}}"
    return s

# 2×2 layout: Panels A/B on top row, C/D on bottom row, each in a minipage
efp_header = " & ".join(EFP_LABELS[e] for e in EFP_ORDER)
col_str = "l" + "c" * n_efp

def make_panel(base_mk, dist_mk, pair_lbl, panel_letter):
    lines = []
    lines.append(r"\footnotesize")
    lines.append(r"\setlength{\tabcolsep}{3.5pt}")
    lines.append(r"\renewcommand{\arraystretch}{1.06}")
    lines.append(rf"\begin{{tabular}}{{{col_str}}}")
    lines.append(r"\toprule")
    lines.append(
        rf"\multicolumn{{{n_efp + 1}}}{{l}}{{\textit{{Panel {panel_letter}: {pair_lbl}}}}} \\"
    )
    lines.append(r"\midrule")
    lines.append(r"Biome & " + efp_header + r" \\")
    lines.append(r"\midrule")
    for igbp in IGBP_ORDER:
        row_cells = [igbp]
        for efp in EFP_ORDER:
            row_cells.append(fmt_ratio(igbp_ratio(base_mk, dist_mk, efp, igbp)))
        lines.append(" & ".join(row_cells) + r" \\")
    lines.append(r"\midrule")
    all_cells = [r"\textit{All}"]
    for efp in EFP_ORDER:
        all_cells.append(fmt_ratio(igbp_ratio(base_mk, dist_mk, efp, None)))
    lines.append(" & ".join(all_cells) + r" \\")
    lines.append(r"\bottomrule")
    lines.append(r"\end{tabular}")
    return "\n".join(lines)

ratio_lines = []
ratio_lines.append(r"\begin{table}[htbp]")
ratio_lines.append(r"\centering")
ratio_lines.append(r"""\caption{RMSE ratio (RMSE with D / RMSE without D) per biome and EFP
(v2 data, anomaly memory, 24-month window). \textbf{Bold} $<1$: D improved;
\textit{italic} $>1$: D worsened. `---' = no data after quality control.}""")
ratio_lines.append(r"\label{tab:rmse_ratio_v2}")
# Outer 2-column tabular guarantees side-by-side layout
ratio_lines.append(r"\begin{tabular}{@{}p{0.48\linewidth}@{\hspace{0.04\linewidth}}p{0.48\linewidth}@{}}")
# Row 1: Panel A (left), Panel B (right)
ratio_lines.append(make_panel(*PAIRS[0], "A") + " &")
ratio_lines.append(make_panel(*PAIRS[1], "B") + r" \\[1.4em]")
# Row 2: Panel C (left), Panel D (right)
ratio_lines.append(make_panel(*PAIRS[2], "C") + " &")
ratio_lines.append(make_panel(*PAIRS[3], "D") + r" \\")
ratio_lines.append(r"\end{tabular}")
ratio_lines.append(r"\end{table}")

out2 = f"{TABLE}/table_RMSE_ratio_v2.tex"
with open(out2, "w") as f:
    f.write("\n".join(ratio_lines) + "\n")
print(f"✓ Wrote {out2}")

# ── Print preview ─────────────────────────────────────────────────────────────
print("\nPreview — Panel B (24m anomaly, v2):")
hdr = f"{'Model':<6} {'Pred':<18}" + "".join(f" {e:>12}" for e in EFP_ORDER)
print(hdr)
for mk in MODELS:
    cells = f"{mk:<6} {MODEL_LABELS[mk]:<18}"
    for efp in EFP_ORDER:
        key = (mk,"24m",efp)
        if key in anom:
            m = anom[key]
            cells += f"  {m['R2']:.3f}({m['RMSE']:.3f})"
        else:
            cells += f"  {'---':>12}"
    print(cells)

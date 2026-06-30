#!/usr/bin/env python3
"""
Fix data quality issues identified in the 2026-06-29 quality check.

Fixes applied:
  1. Negative uWUE / WUE values (numerical artifacts) → NA
     Sites: CA-PB1, US-EML, US-xMB, US-xML, US-xNW, US-xYE
  2. US-HB4 precipitation anomalies > 2000 mm/month → NA
     Both P_sum and P_mean for affected months
  3. CN-Sb1 / CN-Sb2 uWUE / WUE extreme outliers (z > 5) → NA
     IGBP=DNF but values 5–14× global median; likely biased by
     surrounding paddy/agricultural land cover

Files modified (originals backed up with .bak_20260629 suffix):
  - ALL_SITES_YEARLY_EFP_min4continuousYears.csv
  - ALL_SITES_MONTHLY_METEO_corrected.csv
  - EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv
"""

import csv, os, shutil
from datetime import date

BASE     = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
EFP_CSV  = f"{BASE}/fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_YEARLY_EFP_min4continuousYears.csv"
METEO_CSV= f"{BASE}/fluxnet_2017_2025_V02/EFP_outputs_corrected/ALL_SITES_MONTHLY_METEO_corrected.csv"
MODEL_CSV= f"{BASE}/derived_tables/outputs_afterEGU_results/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv"
BAK      = ".bak_20260629"

P_THRESHOLD = 2000  # mm/month — above this is anomalous for US-HB4

# Sites and what to null
NEGATIVE_WUE_FIXES = {
    # site: {year: [vars]}
    "CA-PB1": {"2023": ["uWUE","WUE"]},
    "US-EML":  {"2023": ["uWUE","WUE"]},
    "US-xMB":  {"2019": ["uWUE","WUE"]},
    "US-xML":  {"2021": ["uWUE","WUE"]},
    "US-xNW":  {"2020": ["uWUE","WUE"]},
    "US-xYE":  {"2020": ["uWUE","WUE"]},
}
CN_OUTLIER_SITES = {"CN-Sb1", "CN-Sb2"}  # all years, uWUE + WUE → NA

# ── helpers ──────────────────────────────────────────────────────────────────
def backup(path):
    bak = path + BAK
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
        print(f"  backed up → {os.path.basename(bak)}")
    else:
        print(f"  backup already exists, skipping")

def fix_efp_csv(path):
    """Fix EFP CSV: null negative uWUE/WUE and CN-Sb1/2 WUE/uWUE."""
    backup(path)
    with open(path) as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        fieldnames = reader.fieldnames

    n_neg = 0; n_cn = 0
    for row in rows:
        sid = row["SITE_ID"]; yr = row["YEAR"]
        # Fix 1: negative uWUE/WUE
        if sid in NEGATIVE_WUE_FIXES and yr in NEGATIVE_WUE_FIXES[sid]:
            for v in NEGATIVE_WUE_FIXES[sid][yr]:
                if row.get(v, "") not in ("", "NA"):
                    try:
                        if float(row[v]) < 0:
                            print(f"    EFP {sid} {yr} {v}={row[v]} → NA")
                            row[v] = "NA"; n_neg += 1
                    except: pass
        # Fix 3: CN-Sb1/2 WUE/uWUE
        if sid in CN_OUTLIER_SITES:
            for v in ["uWUE", "WUE"]:
                if row.get(v, "") not in ("", "NA"):
                    try:
                        val = float(row[v])
                        if val > 8:  # global mean ~3, threshold at >8 (z≈3)
                            print(f"    EFP {sid} {yr} {v}={round(val,2)} → NA")
                            row[v] = "NA"; n_cn += 1
                    except: pass

    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader(); writer.writerows(rows)
    return n_neg, n_cn

def fix_meteo_csv(path):
    """Fix monthly meteo: null US-HB4 P_sum and P_mean > threshold."""
    backup(path)
    with open(path) as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        fieldnames = reader.fieldnames

    n_p = 0
    for row in rows:
        if row["SITE_ID"] != "US-HB4": continue
        for v in ["P_sum", "P_mean"]:
            if v not in row: continue
            val = row[v]
            if val in ("", "NA"): continue
            try:
                fval = float(val)
                if fval > P_THRESHOLD:
                    print(f"    METEO US-HB4 {row.get('YEAR','?')}-{row.get('MONTH','?')} {v}={round(fval,1)} → NA")
                    row[v] = "NA"; n_p += 1
            except: pass

    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader(); writer.writerows(rows)
    return n_p

def fix_model_csv(path):
    """Fix modelling dataset: null negative WUE/uWUE, CN-Sb1/2 outliers,
    and US-HB4 anomalous monthly P columns."""
    backup(path)
    with open(path) as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        fieldnames = reader.fieldnames

    P_SUM_COLS  = [c for c in fieldnames if c.startswith("P_sum_M")]
    P_MEAN_COLS = [c for c in fieldnames if c.startswith("P_mean_M")]

    n_neg = 0; n_cn = 0; n_p = 0
    for row in rows:
        sid = row["SITE_ID"]; yr = row["YEAR"]

        # Fix 1: negative uWUE/WUE
        if sid in NEGATIVE_WUE_FIXES and yr in NEGATIVE_WUE_FIXES[sid]:
            for v in NEGATIVE_WUE_FIXES[sid][yr]:
                if row.get(v, "") not in ("", "NA"):
                    try:
                        if float(row[v]) < 0:
                            row[v] = "NA"; n_neg += 1
                    except: pass

        # Fix 3: CN-Sb1/2 WUE/uWUE
        if sid in CN_OUTLIER_SITES:
            for v in ["uWUE", "WUE"]:
                if row.get(v, "") not in ("", "NA"):
                    try:
                        if float(row[v]) > 8:
                            row[v] = "NA"; n_cn += 1
                    except: pass

        # Fix 2: US-HB4 P anomalies (each monthly P column)
        if sid == "US-HB4":
            for c in P_SUM_COLS:
                if row.get(c, "") not in ("", "NA"):
                    try:
                        if float(row[c]) > P_THRESHOLD:
                            row[c] = "NA"; n_p += 1
                    except: pass
            for c in P_MEAN_COLS:
                # P_mean mirrors P_sum month; null if the corresponding P_sum is now NA
                month = c.replace("P_mean_M", "P_sum_M")
                if row.get(month, "") == "NA":
                    row[c] = "NA"

    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader(); writer.writerows(rows)
    return n_neg, n_cn, n_p

# ── run ───────────────────────────────────────────────────────────────────────
print("=" * 60)
print("FIX 1 + 3: EFP CSV (negative WUE/uWUE + CN-Sb outliers)")
print("=" * 60)
n_neg, n_cn = fix_efp_csv(EFP_CSV)
print(f"  → {n_neg} negative values set to NA")
print(f"  → {n_cn} CN-Sb1/2 outlier values set to NA")

print()
print("=" * 60)
print("FIX 2: Monthly meteo CSV (US-HB4 P anomalies)")
print("=" * 60)
n_p = fix_meteo_csv(METEO_CSV)
print(f"  → {n_p} anomalous P values set to NA")

print()
print("=" * 60)
print("FIX 1 + 2 + 3: Main modelling dataset")
print("=" * 60)
n_neg2, n_cn2, n_p2 = fix_model_csv(MODEL_CSV)
print(f"  → {n_neg2} negative uWUE/WUE set to NA")
print(f"  → {n_cn2} CN-Sb1/2 outlier uWUE/WUE set to NA")
print(f"  → {n_p2} anomalous US-HB4 P columns set to NA")

print()
print("=" * 60)
print("SUMMARY")
print("=" * 60)
print(f"  Negative WUE/uWUE nulled : {n_neg + n_neg2} cells across 6 sites")
print(f"  CN-Sb1/2 outliers nulled  : {n_cn + n_cn2} cells")
print(f"  US-HB4 P anomalies nulled : {n_p + n_p2} cells")
print()
print("Not fixed (no data action needed):")
print("  AU-How  — EFPs look normal; DT partitioning is documented")
print("  CD-Ygb  — NOT in modelling dataset; VPD fix not required here")
print("  KR-SmM  — NOT in modelling dataset")
print()
print("Backups saved with .bak_20260629 suffix in same directory.")

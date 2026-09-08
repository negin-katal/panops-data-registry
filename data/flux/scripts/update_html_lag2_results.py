#!/usr/bin/env python3
"""
Update V10_report.html: replace the 24m rows of the three Optuna-tuned
learners (XGB/RF/LGB), for tc>=30 and tc>=50, LOSO and repeated-CV, with the
lag2-corrected results from scripts/run_v10_lag2_optuna.R.

WHY REPLACE RATHER THAN ADD A TOGGLE: the old 24m rows for these datasets
were trained on a disturbance block that was byte-identical to the 12m one
(no lag2), which does not match the documented model design. They are wrong,
not an alternative worth keeping side by side. 12m rows, all_sites (which
already had lag2 correctly), and the non-Optuna learners are untouched.

Usage: python3 scripts/update_html_lag2_results.py [--dry-run]
"""
import csv, json, re, sys, os

ROOT = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
OUT  = f"{ROOT}/derived_tables/outputs_afterEGU_results"
HTML = f"{ROOT}/plots/V10/V10_report.html"
DRY  = "--dry-run" in sys.argv

# (learner family, HTML metric-const suffix, html dataset key, our ds key, our folder suffix)
SPECS = [
    ("XGB", "XGBOPT", "sites_with_high_Tcover", "tc30", "lag2"),
    ("RF",  "RFOPT",  "sites_with_high_Tcover", "tc30", "lag2"),
    ("LGB", "LGBOPT", "sites_with_high_Tcover", "tc30", "lag2"),
    ("XGB", "XGBOPT", "sites_tc50",             "tc50", "tc50_lag2"),
    ("RF",  "RFOPT",  "sites_tc50",             "tc50", "tc50_lag2"),
    ("LGB", "LGBOPT", "sites_tc50",             "tc50", "tc50_lag2"),
]
M24 = {"M1_24m","M2_24m","M3_24m","M4_24m","M5_raw_24m","M5_anom_24m",
       "M6_raw_24m","M6_anom_24m","M7_raw_24m","M7_anom_24m","M8_raw_24m","M8_anom_24m"}

def load_new(path, with_sd):
    rows = {}
    if not os.path.exists(path):
        return None
    for r in csv.DictReader(open(path)):
        if r["model"] not in M24:
            continue
        row = {
            "model": r["model"], "response": r["response"],
            "n_predictors": int(float(r["n_predictors"])),
            "n_pairs": int(float(r["n_pairs"])),
            "RMSE": round(float(r["RMSE"]), 3),
            "MAE": round(float(r["MAE"]), 3),
            "R2": round(float(r["R2"]), 3),
        }
        if with_sd and r.get("mean_pred_sd"):
            try: row["pred_sd"] = round(float(r["mean_pred_sd"]), 4)
            except ValueError: pass
        rows[(r["model"], r["response"])] = row
    return rows

def main():
    h = open(HTML, encoding="utf-8").read()
    replaced_total = 0
    missing = []

    for fam, suf, dskey, ds, foldersuf in SPECS:
        for const_prefix, loso_dir_tmpl, with_sd in (
            ("METRICS_%s", "%s_v10_%s_optuna", False),
            ("METRICS_REP_%s", "%s_optuna_repCV_%s", True),
        ):
            const = const_prefix % suf
            folder = loso_dir_tmpl % (fam, foldersuf) if with_sd is False else (loso_dir_tmpl % (fam, foldersuf))
            csv_path = f"{OUT}/{folder}/{fam}_metrics_LOSO.csv"
            new_rows = load_new(csv_path, with_sd)
            if new_rows is None:
                missing.append(f"{const}[{dskey}] <- {folder} (FILE MISSING)")
                continue

            m = re.search(r"const %s=(\{.*?\});\n" % const, h, re.S)
            if not m:
                missing.append(f"{const} (constant not found in HTML)")
                continue
            obj = json.loads(m.group(1))
            if dskey not in obj:
                missing.append(f"{const}[{dskey}] (dataset key not found)")
                continue

            arr = obj[dskey]
            n_here = 0
            for i, row in enumerate(arr):
                key = (row["model"], row["response"])
                if key in new_rows:
                    arr[i] = new_rows[key]
                    n_here += 1
            expected = len(new_rows)
            if n_here != expected:
                missing.append(f"{const}[{dskey}]: replaced {n_here}, expected {expected} "
                                f"(some model/response pairs not found in existing array)")
            replaced_total += n_here

            obj[dskey] = arr
            h = h[:m.start(1)] + json.dumps(obj, separators=(",", ":")) + h[m.end(1):]
            print(f"  {const:20s} [{dskey:24s}] <- {folder:40s}  replaced {n_here}/{expected}")

    print(f"\nTotal rows replaced: {replaced_total} (expect {6*12*5}=360 if everything is present)")
    if missing:
        print("\nISSUES:")
        for x in missing:
            print("  -", x)

    if DRY:
        print("\n[dry-run] not writing file")
        return 0

    open(HTML, "w", encoding="utf-8").write(h)
    print(f"\nWritten: {HTML}")
    return 0

sys.exit(main())

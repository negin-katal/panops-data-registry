"""
Patches WUE predictions/metrics/varimp from the _WUE temp dirs into the
main 24mbench CSV files, replacing the old uWUE rows.
Run once both wue_anomaly and wue_rawmem tmux sessions have finished.
"""
import os, csv, sys

BASE = "derived_tables/outputs_afterEGU_results"

CONFIGS = [
    {
        "main": f"{BASE}/RF_outputs_anomaly_24mbench",
        "wue":  f"{BASE}/RF_outputs_anomaly_24mbench_WUE",
        "label": "anomaly",
    },
    {
        "main": f"{BASE}/RF_outputs_rawmem_24mbench",
        "wue":  f"{BASE}/RF_outputs_rawmem_24mbench_WUE",
        "label": "rawmem",
    },
]

FILES = ["RF_predictions_LOSO.csv", "RF_metrics_LOSO.csv", "RF_varimp_LOSO.csv"]

def patch(main_path, wue_path, label):
    # Read WUE rows
    wue_rows = []
    with open(wue_path) as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        for row in reader:
            wue_rows.append(row)

    # Read main file, drop uWUE rows
    kept = []
    with open(main_path) as f:
        reader = csv.DictReader(f)
        main_fields = reader.fieldnames
        for row in reader:
            kept.append(row)

    n_dropped = 0

    # Append WUE rows
    merged = kept + wue_rows
    with open(main_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=main_fields)
        w.writeheader()
        w.writerows(merged)

    print(f"  [{label}] {os.path.basename(main_path)}: "
          f"kept {len(kept)} rows, added {len(wue_rows)} WUE rows -> {len(merged)} total")

for cfg in CONFIGS:
    print(f"\n=== {cfg['label']} ===")
    for fname in FILES:
        main_path = os.path.join(cfg["main"], fname)
        wue_path  = os.path.join(cfg["wue"],  fname)
        if not os.path.exists(wue_path):
            print(f"  SKIP (WUE file not ready): {wue_path}")
            continue
        if not os.path.exists(main_path):
            print(f"  SKIP (main file missing): {main_path}")
            continue
        patch(main_path, wue_path, cfg["label"])

print("\nDone. Run all plot scripts now.")

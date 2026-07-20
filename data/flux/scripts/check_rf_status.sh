#!/bin/bash
# Check RF training status

LOG_FILE="/mnt/gsdata/projects/panops/panops-data-registry/data/flux/logs/rf_loso_models.log"
OUT_FILE="/mnt/gsdata/projects/panops/panops-data-registry/data/flux/derived_tables/outputs_afterEGU_results/v10/RF_LOSO_results.csv"

echo "======================================================================"
echo "RF LOSO TRAINING STATUS"
echo "======================================================================"
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: Log file not found: $LOG_FILE"
    exit 1
fi

# Count progress
lines=$(wc -l < "$LOG_FILE")
completed_models=$(grep "→ RMSE=" "$LOG_FILE" | wc -l)
summary_started=$(grep "^SUMMARY$" "$LOG_FILE" | wc -l)

echo "Log file: $LOG_FILE"
echo "Total lines: $lines"
echo "Models completed: $completed_models"
echo ""

# Show last few models
echo "Recent progress:"
tail -20 "$LOG_FILE"

echo ""
echo "------"

if [ -f "$OUT_FILE" ]; then
    echo "✅ Results file created!"
    lines=$(wc -l < "$OUT_FILE")
    echo "   Models run: $((lines - 1))"
else
    echo "⏳ Results file not yet created (still running...)"
fi

echo ""

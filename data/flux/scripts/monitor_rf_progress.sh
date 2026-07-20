#!/bin/bash
# Monitor RF progress for B1 and B2 runs

echo "=================================================================="
echo "RF MONITORING - Benchmark 1 (Lag1) & Benchmark 2 (Lag1+Lag2)"
echo "=================================================================="
echo ""

echo "📊 SESSIONS RUNNING:"
tmux list-sessions | grep -E "rf_b1|rf_b2"
echo ""

echo "⏱️  START TIME:"
stat logs/run_52_B1_lag1.log 2>/dev/null | grep -i modify || echo "B1 not started yet"
stat logs/run_53_B2_lag1and2.log 2>/dev/null | grep -i modify || echo "B2 not started yet"
echo ""

echo "📈 B1 PROGRESS (Lag1 Only):"
echo "---"
tail -15 logs/run_52_B1_lag1.log 2>/dev/null | grep -E "Memory type|sites|RMSE|✅|====" || echo "B1 still loading..."
echo ""

echo "📈 B2 PROGRESS (Lag1+Lag2):"
echo "---"
tail -15 logs/run_53_B2_lag1and2.log 2>/dev/null | grep -E "Memory type|sites|RMSE|✅|====" || echo "B2 still loading..."
echo ""

echo "📁 OUTPUT LOCATIONS:"
echo "  B1: derived_tables/outputs_afterEGU_results/RF_B1_lag1_final/"
echo "  B2: derived_tables/outputs_afterEGU_results/RF_B2_lag1and2_final/"
echo ""

echo "💾 FILES TO EXPECT:"
echo "  - RF_metrics_LOSO.csv (128 rows: 8 models × 2 memory × 4 responses)"
echo "  - RF_predictions_LOSO.csv (all LOSO predictions)"
echo ""

echo "LAST UPDATE: $(date)"
echo "=================================================================="


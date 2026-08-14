#!/usr/bin/env bash
# Base LOSO runs (RF / XGB / LGB) on the tc50 subsample (tree cover >=50%, 500 m).
set -uo pipefail
cd /mnt/gsdata/projects/panops/panops-data-registry/data/flux
RS=/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript
export OMP_NUM_THREADS=1
C=${1:-22}
run () { $RS "scripts/$1" tc50 > "logs/tc50_$2.log" 2>&1 \
         && echo "  OK      $2" || echo "  FAILED  $2"; }
export -f run; export RS
V10_XGB_CORES=$C V10_LGB_CORES=$C V10_RF_CORES=$C
{ run run_v10_RF_ranger.R RF_base & run run_v10_XGB.R XGB_base & run run_v10_LGB.R LGB_base & wait; }
echo "TC50_BASE_DONE"

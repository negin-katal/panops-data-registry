#!/usr/bin/env bash
# Sync manuscript/ → Overleaf and push.
# Usage: bash manuscript/push_to_overleaf.sh ["optional commit message"]
#
# Files NOT synced to Overleaf (local-only):
#   push_to_overleaf.sh, README_*.md, *.png, site_disturbance_history/

set -euo pipefail

OVERLEAF_DIR="/home/nk1125/overleaf_panops"
MANUSCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG="${1:-sync manuscript to Overleaf}"

# Pull any remote changes first to avoid conflicts
git -C "$OVERLEAF_DIR" pull --rebase origin main

# Sync all relevant files from manuscript/ to Overleaf clone
rsync -av \
  --exclude='.git' \
  --exclude='push_to_overleaf.sh' \
  --exclude='README_*.md' \
  --exclude='*.png' \
  --exclude='site_disturbance_history/' \
  "$MANUSCRIPT_DIR/" "$OVERLEAF_DIR/"

# Commit and push
cd "$OVERLEAF_DIR"
git add -A
git commit -m "$MSG" 2>/dev/null || echo "Nothing new to commit."
git push origin HEAD

echo ""
echo "Done — Overleaf updated."

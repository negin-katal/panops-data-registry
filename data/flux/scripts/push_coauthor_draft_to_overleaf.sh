#!/usr/bin/env bash
# ============================================================================
# Publish manuscript_coauthor_draft/ -> a SEPARATE Overleaf project.
#
# Overleaf cannot create a project from a git push, so do this once first:
#   1. overleaf.com -> New Project -> Blank Project (name it e.g. "EFP mortality - coauthor draft")
#   2. open it, copy the 24-character project id from the URL
#        https://www.overleaf.com/project/<PROJECT_ID>
#   3. run:  bash scripts/push_coauthor_draft_to_overleaf.sh <PROJECT_ID> "message"
#
# The Overleaf git token is reused from the existing manuscript clone, so it is
# never typed or stored anywhere new.
#
# Afterwards, share from Overleaf: Menu -> Share -> invite coauthors, or
# "Turn on link sharing" for a read-only or edit link.
# ============================================================================
set -euo pipefail

PROJECT_ID=${1:-}
MSG=${2:-"Update coauthor draft"}
SRC="/mnt/gsdata/projects/panops/panops-data-registry/data/flux/manuscript_coauthor_draft"
EXISTING="/home/nk1125/overleaf_panops"
STATE="$SRC/.overleaf_project_id"

# remember the id so later runs need no argument
if [ -z "$PROJECT_ID" ] && [ -f "$STATE" ]; then PROJECT_ID=$(cat "$STATE"); fi
if [ -z "$PROJECT_ID" ]; then
  echo "ERROR: no project id given and none remembered."
  echo "Usage: bash scripts/push_coauthor_draft_to_overleaf.sh <PROJECT_ID> [message]"
  exit 1
fi
if ! [[ "$PROJECT_ID" =~ ^[0-9a-f]{24}$ ]]; then
  echo "ERROR: '$PROJECT_ID' is not a 24-character Overleaf project id."
  exit 1
fi

# reuse the token already held by the main manuscript clone
TOKEN=$(git -C "$EXISTING" remote get-url origin | sed -E 's#https://([^@]*)@.*#\1#')
if [ -z "$TOKEN" ]; then echo "ERROR: could not read the Overleaf token from $EXISTING"; exit 1; fi
REMOTE="https://${TOKEN}@git.overleaf.com/${PROJECT_ID}"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "==> cloning Overleaf project $PROJECT_ID"
git clone --quiet "$REMOTE" "$TMP/proj"

echo "==> syncing draft (tex + figures only)"
rsync -a --delete --exclude='.git' --exclude='*.zip' --exclude='.overleaf_project_id' \
      --exclude='README.md' --exclude='*.csv' \
      "$SRC/" "$TMP/proj/"

cd "$TMP/proj"
if [ -z "$(git status --porcelain)" ]; then echo "==> nothing to commit"; exit 0; fi
git add -A
git commit --quiet -m "$MSG"
git push origin HEAD
echo "$PROJECT_ID" > "$STATE"

echo
echo "Done. Open:  https://www.overleaf.com/project/$PROJECT_ID"
echo "Share it:    Menu -> Share -> invite coauthors, or turn on link sharing."

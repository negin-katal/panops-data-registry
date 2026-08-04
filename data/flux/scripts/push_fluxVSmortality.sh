#!/usr/bin/env bash
# ============================================================================
# Publish data/flux/fluxVSmortality/  ->  github.com/negin-katal/fluxVSmortality
# (the repo that serves https://negin-katal.github.io/fluxVSmortality/)
#
# That folder has no .git of its own - it is tracked inside panops-data-registry -
# so it cannot be committed directly. This script clones the real repo into a
# temp dir, mirrors the local files in, commits and pushes.
#
#   bash scripts/push_fluxVSmortality.sh "commit message"
#   bash scripts/push_fluxVSmortality.sh "message" v10      # only the v10/ subtree
# ============================================================================
set -euo pipefail

MSG=${1:-"Update fluxVSmortality site"}
SUBDIR=${2:-""}                       # optional: restrict to one subfolder
SRC="/mnt/gsdata/projects/panops/panops-data-registry/data/flux/fluxVSmortality"
REMOTE="git@github-personal:negin-katal/fluxVSmortality.git"
TMP=$(mktemp -d)

# conda's OpenSSL breaks the system ssh; strip it just for git
export GIT_SSH_COMMAND='env -u LD_LIBRARY_PATH ssh'

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "==> cloning $REMOTE"
git clone --quiet "$REMOTE" "$TMP/repo"

echo "==> syncing files (PNG/HTML/MD; PDFs excluded, as the site never used them)"
if [ -n "$SUBDIR" ]; then
  rsync -a --delete --exclude='*.pdf' "$SRC/$SUBDIR/" "$TMP/repo/$SUBDIR/"
else
  rsync -a --delete --exclude='*.pdf' --exclude='.git' "$SRC/" "$TMP/repo/"
fi

cd "$TMP/repo"
if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "==> nothing to commit - remote already matches local"
  exit 0
fi

git add -A
echo "==> committing $(git diff --cached --name-only | wc -l) changed files"
git commit --quiet -m "$MSG"
echo "==> pushing"
git push origin main

echo
echo "Pushed. Live in ~1-2 min:"
echo "  https://negin-katal.github.io/fluxVSmortality/v10/index.html"

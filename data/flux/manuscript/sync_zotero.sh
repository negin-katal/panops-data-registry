#!/usr/bin/env bash
# Sync Zotero "Tree mortality" collection → sn-bibliography.bib
# Run from the project root: bash manuscript/sync_zotero.sh

set -e

ZOTERO_USER=7361769
ZOTERO_KEY=zzL8a1ZVThBagWzi80jZs6av
COLLECTION=4B2EEQ27   # "Tree mortality"
BIB=manuscript/sn-bibliography.bib
TMP=/tmp/zotero_sync_$$.bib

echo "Fetching Zotero collection..."
curl -s "https://api.zotero.org/users/${ZOTERO_USER}/collections/${COLLECTION}/items?key=${ZOTERO_KEY}&format=bibtex&limit=100" > "$TMP"
COUNT=$(grep -c "^@" "$TMP" || true)
echo "  $COUNT entries fetched."

python3 - << PYEOF
import re

existing = open("${BIB}").read()
existing_keys = set(re.findall(r'^@\w+\{(\S+?),', existing, re.MULTILINE))

zotero = open("${TMP}").read()
entries = re.split(r'\n(?=@)', zotero.strip())

added = []
for entry in entries:
    m = re.match(r'@\w+\{(\S+?),', entry)
    if not m:
        continue
    key = m.group(1)
    if key not in existing_keys:
        added.append((key, entry))

if added:
    with open("${BIB}", "a") as f:
        for key, entry in added:
            f.write("\n" + entry.strip() + "\n")
    print(f"Added {len(added)} new entries: {[k for k,_ in added]}")
else:
    print("No new entries — bibliography is up to date.")
PYEOF

rm -f "$TMP"

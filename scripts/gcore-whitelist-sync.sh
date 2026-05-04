#!/usr/bin/env bash
# gcore-whitelist-sync.sh
#
# Daily cron wrapper. Runs in CI (GitHub Actions); regenerates the canonical
# whitelist YAML from GCore's published edge IP list, sanity-checks the result,
# and opens a PR if anything changed.
#
# Safety gates:
#   1. Generator output must contain >= 100 IPs (catches empty/corrupted upstream).
#   2. Generator output must contain >= 0.9 * previous IPs (catches truncation).
#
# On gate failure: exit non-zero so the workflow fails loudly.
#
# Usage (typically called from .github/workflows/gcore-whitelist-daily.yml):
#   ./scripts/gcore-whitelist-sync.sh [--whitelist PATH]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHITELIST="${REPO_ROOT}/crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml"
if [ "${1:-}" = "--whitelist" ]; then
    WHITELIST="${2:?--whitelist requires PATH}"
fi
GENERATOR="${REPO_ROOT}/scripts/gcore-whitelist-generate.py"

if [ ! -f "$GENERATOR" ]; then
    echo "ERROR: generator missing at $GENERATOR" >&2
    exit 2
fi

PREV_COUNT=0
if [ -f "$WHITELIST" ]; then
    # `grep -c` always emits a count; `|| true` only suppresses the exit-1 noise
    # when zero matches. Avoid `|| echo 0` which would append a second "0".
    PREV_COUNT=$(grep -cE '^\s+- "[^"]+"' "$WHITELIST" || true)
fi

NEW=$(mktemp)
trap 'rm -f "$NEW"' EXIT

echo "[sync] regenerating from GCore public-ip-list..."
python3 "$GENERATOR" > "$NEW"

NEW_COUNT=$(grep -cE '^\s+- "[^"]+"' "$NEW" || true)
echo "[sync] previous=$PREV_COUNT  new=$NEW_COUNT"

# Safety gate 1: hard floor.
if [ "$NEW_COUNT" -lt 100 ]; then
    echo "ERROR: new whitelist has $NEW_COUNT entries (< 100). Refusing to sync." >&2
    echo "Likely cause: upstream API returned empty/corrupted list. Check https://api.gcore.com/cdn/public-ip-list" >&2
    exit 3
fi

# Safety gate 2: 0.9× of previous (only enforce if we had a baseline).
if [ "$PREV_COUNT" -gt 0 ]; then
    THRESHOLD=$(( PREV_COUNT * 9 / 10 ))
    if [ "$NEW_COUNT" -lt "$THRESHOLD" ]; then
        echo "ERROR: new whitelist has $NEW_COUNT entries, threshold $THRESHOLD (0.9 * $PREV_COUNT). Refusing to sync." >&2
        echo "Likely cause: upstream API returned a degraded list. Investigate before bypassing." >&2
        exit 4
    fi
fi

# Compare ignoring the snapshot timestamp (line 4 of the generated file).
if [ -f "$WHITELIST" ] && diff <(grep -v '^# Snapshot:' "$WHITELIST") <(grep -v '^# Snapshot:' "$NEW") >/dev/null; then
    echo "[sync] no substantive change (only timestamp differs); exiting"
    exit 0
fi

echo "[sync] substantive change detected; updating $WHITELIST"
mv "$NEW" "$WHITELIST"
trap - EXIT

echo "[sync] done. The CI workflow will open a PR with this diff for human review."

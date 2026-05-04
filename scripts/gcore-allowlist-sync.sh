#!/usr/bin/env bash
# gcore-allowlist-sync.sh
#
# Sync GCore IPs/CIDRs from the canonical whitelist YAML into orch's
# `cscli allowlists niteride-gcore`. Run on the LAPI host (orch).
#
# Why two layers?
#   - Parser whitelist (s02-enrich/niteride-gcore-whitelist.yaml) filters local
#     events at each agent BEFORE they reach LAPI.
#   - cscli allowlists are LAPI-level — they override decisions from ALL
#     origins (local crowdsec, CAPI/community-blocklist, manual cscli adds)
#     before delivery to the bouncer. This is the only mechanism that gates
#     CAPI-pushed bans on GCore IPs (orch had 7500+ active CAPI decisions
#     2026-05-03 P0 incident).
#
# Usage:
#   ./scripts/gcore-allowlist-sync.sh [--whitelist PATH]
#
# Idempotent — safe to re-run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHITELIST="${1:-}"
if [ "${1:-}" = "--whitelist" ]; then
    WHITELIST="${2:-}"
fi
WHITELIST="${WHITELIST:-$REPO_ROOT/crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml}"
ALLOWLIST_NAME="niteride-gcore"
ALLOWLIST_DESC="GCore CDN POPs (origin-pull). Synced from $WHITELIST. See engineering/platforms/gcore-cdn.md."

if [ ! -f "$WHITELIST" ]; then
    echo "ERROR: whitelist missing at $WHITELIST" >&2
    exit 2
fi

if ! command -v cscli >/dev/null 2>&1; then
    echo "ERROR: cscli not found — run on the LAPI host (orch)" >&2
    exit 3
fi

# Ensure the allowlist exists.
if ! cscli allowlists list -o raw 2>/dev/null | grep -q "^${ALLOWLIST_NAME}\b"; then
    echo "[allowlist] creating '${ALLOWLIST_NAME}'"
    cscli allowlists create "$ALLOWLIST_NAME" --description "$ALLOWLIST_DESC"
else
    echo "[allowlist] '${ALLOWLIST_NAME}' already present"
fi

# Extract values from YAML (use python — yq isn't always installed).
mapfile -t WANTED < <(python3 - "$WHITELIST" <<'PY'
import sys, re
path = sys.argv[1]
seen = set()
with open(path) as f:
    section = None
    for line in f:
        s = line.rstrip("\n")
        m_section = re.match(r'^  (ip|cidr):\s*$', s)
        if m_section:
            section = m_section.group(1)
            continue
        if section in ("ip", "cidr"):
            m_item = re.match(r'^    - "([^"]+)"\s*$', s)
            if m_item:
                seen.add(m_item.group(1))
            elif s.strip() and not s.startswith("    "):
                section = None
for v in sorted(seen):
    print(v)
PY
)
WANTED_COUNT=${#WANTED[@]}
echo "[allowlist] target value count: $WANTED_COUNT"

if [ "$WANTED_COUNT" -lt 100 ]; then
    echo "ERROR: target count <100 — refusing to sync (safety gate; whitelist may be corrupted)" >&2
    exit 4
fi

# Current values.
mapfile -t CURRENT < <(cscli allowlists inspect "$ALLOWLIST_NAME" -o json 2>/dev/null \
    | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    items = d.get("items") or d.get("Items") or []
    for it in items:
        v = it.get("value") if isinstance(it, dict) else it
        if v:
            print(v)
except Exception:
    pass
' | sort -u)
CURRENT_COUNT=${#CURRENT[@]}
echo "[allowlist] current value count: $CURRENT_COUNT"

# Compute add / remove diff.
TMP_WANTED=$(mktemp)
TMP_CURRENT=$(mktemp)
trap 'rm -f "$TMP_WANTED" "$TMP_CURRENT"' EXIT
printf "%s\n" "${WANTED[@]}" | sort -u > "$TMP_WANTED"
printf "%s\n" "${CURRENT[@]:-}" | sort -u > "$TMP_CURRENT"

ADD=$(comm -23 "$TMP_WANTED" "$TMP_CURRENT")
REMOVE=$(comm -13 "$TMP_WANTED" "$TMP_CURRENT")

ADD_COUNT=$(printf "%s\n" "$ADD" | grep -c . || true)
REMOVE_COUNT=$(printf "%s\n" "$REMOVE" | grep -c . || true)
echo "[allowlist] adding $ADD_COUNT, removing $REMOVE_COUNT"

if [ -n "$ADD" ]; then
    # cscli allowlists add accepts multiple -v flags
    while IFS= read -r v; do
        [ -z "$v" ] && continue
        cscli allowlists add "$ALLOWLIST_NAME" -v "$v" >/dev/null
    done <<< "$ADD"
fi

if [ -n "$REMOVE" ]; then
    while IFS= read -r v; do
        [ -z "$v" ] && continue
        cscli allowlists remove "$ALLOWLIST_NAME" -v "$v" >/dev/null
    done <<< "$REMOVE"
fi

echo "[allowlist] sync complete"
cscli allowlists inspect "$ALLOWLIST_NAME" -o human 2>&1 | head -10

#!/usr/bin/env bash
# sync-crowdsec-whitelist.sh
#
# Push the canonical GCore CDN whitelist to a CrowdSec agent host and reload.
# Run after merging changes to `crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml`.
#
# Usage:
#   sync-crowdsec-whitelist.sh <host> [--ssh-key PATH] [--remote-user root]
#
# Example:
#   ./scripts/sync-crowdsec-whitelist.sh 82.22.53.218 --ssh-key ~/repos/niteridefm/myKeys/niteride-fm-ch1
#
# Active hosts (2026-05-03): CH1 82.22.53.218, CH2 82.22.53.167, orch 139.60.162.20, web 194.247.183.37.
#
# See engineering/platforms/gcore-cdn.md for context.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHITELIST_LOCAL="$REPO_ROOT/crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml"
WHITELIST_REMOTE="/etc/crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml"
PARSER_NAME="niteride/gcore-cdn-whitelist"

if [ ! -f "$WHITELIST_LOCAL" ]; then
    echo "ERROR: canonical whitelist missing at $WHITELIST_LOCAL" >&2
    exit 2
fi

HOST="${1:-}"
if [ -z "$HOST" ]; then
    echo "Usage: $0 <host> [--ssh-key PATH] [--remote-user root]" >&2
    exit 64
fi
shift || true

SSH_KEY=""
REMOTE_USER="root"
while [ $# -gt 0 ]; do
    case "$1" in
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        --remote-user) REMOTE_USER="$2"; shift 2 ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 64 ;;
    esac
done

SSH_OPTS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
[ -n "$SSH_KEY" ] && SSH_OPTS+=(-i "$SSH_KEY")
SSH_TARGET="${REMOTE_USER}@${HOST}"

echo "[sync] pushing whitelist to ${SSH_TARGET}:${WHITELIST_REMOTE}"
scp "${SSH_OPTS[@]}" "$WHITELIST_LOCAL" "${SSH_TARGET}:${WHITELIST_REMOTE}.new"

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" bash -s <<EOF
set -euo pipefail
sudo install -o root -g root -m 0644 "${WHITELIST_REMOTE}.new" "$WHITELIST_REMOTE"
sudo rm -f "${WHITELIST_REMOTE}.new"
sudo systemctl reload crowdsec
sleep 2
sudo systemctl is-active crowdsec
sudo cscli parsers inspect "$PARSER_NAME" >/dev/null
echo "[sync] reload OK on \$(hostname); parser registered"
EOF

echo "[sync] done"

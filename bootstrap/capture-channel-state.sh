#!/usr/bin/env bash
# capture-channel-state.sh — emit a YAML snapshot of a channel server's golden state.
#
# Usage:
#   ./capture-channel-state.sh                          # capture from current host
#   ./capture-channel-state.sh --ssh root@82.22.53.218  # capture remote
#
# Output goes to stdout (YAML). Compare snapshots between CH1/CH2 to detect drift,
# or diff against the post-bootstrap state of a freshly-provisioned host.

set -euo pipefail

SSH_TARGET=""
case "${1:-}" in
    --ssh) SSH_TARGET="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
esac

run_remote() {
    # Callers pass a single shell-line string. Both branches join all args via $* for
    # consistent behavior (SSH branch already does this — bash -c needed $* not $@).
    if [[ -n "${SSH_TARGET}" ]]; then
        ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${SSH_TARGET}" "$*"
    else
        bash -c "$*"
    fi
}

# YAML helpers (no external dep — keep portable)
yaml_str() { printf '%s' "$1" | sed 's/"/\\"/g'; }

emit() {
cat <<EOF
# captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# host: $(run_remote 'hostname' 2>/dev/null || echo unknown)
# capture-channel-state.sh
---
versions:
  ubuntu_release: "$(run_remote 'grep ^VERSION_ID= /etc/os-release | cut -d= -f2 | tr -d \\"' 2>/dev/null || echo unknown)"
  node: "$(run_remote 'node -v 2>/dev/null' || echo absent)"
  ffmpeg: "$(run_remote 'ffmpeg -version 2>/dev/null | head -1 | awk "{print \$3}"' || echo absent)"
  pm2: "$(run_remote 'pm2 --version 2>/dev/null' || echo absent)"

users:
  niteride:
    exists: $(run_remote 'getent passwd niteride >/dev/null && echo true || echo false')
    uid_gid: "$(run_remote 'getent passwd niteride 2>/dev/null | cut -d: -f3,4' || echo absent)"

ownership:
  /opt/niteride:           "$(run_remote 'stat -c "%U:%G %a" /opt/niteride 2>/dev/null' || echo absent)"
  /opt/niteride/data:      "$(run_remote 'stat -c "%U:%G %a" /opt/niteride/data 2>/dev/null' || echo absent)"
  /opt/niteride/.env:      "$(run_remote 'stat -c "%U:%G %a" /opt/niteride/.env 2>/dev/null' || echo absent)"
  /var/www/hls:            "$(run_remote 'stat -c "%U:%G %a" /var/www/hls 2>/dev/null' || echo absent)"
  /var/www/hls/segments:   "$(run_remote 'stat -c "%U:%G %a" /var/www/hls/segments 2>/dev/null' || echo absent)"
  /root/.pm2:              "$(run_remote 'stat -c "%U:%G %a" /root/.pm2 2>/dev/null' || echo absent)"
  /home/niteride/.pm2:     "$(run_remote 'stat -c "%U:%G %a" /home/niteride/.pm2 2>/dev/null' || echo absent)"

systemd:
  pm2-root.service:
    enabled: $(run_remote 'systemctl is-enabled pm2-root.service 2>/dev/null || echo absent')
    active:  $(run_remote 'systemctl is-active pm2-root.service 2>/dev/null || echo absent')
  pm2-niteride.service:
    enabled: $(run_remote 'systemctl is-enabled pm2-niteride.service 2>/dev/null || echo absent')
    active:  $(run_remote 'systemctl is-active pm2-niteride.service 2>/dev/null || echo absent')

pm2_apps:
  root_daemon:
$(run_remote 'pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(\"    - \" + p[\"name\"]) for p in d]"' 2>/dev/null || echo "    - <unreadable>")
  niteride_daemon:
$(run_remote 'sudo -u niteride PM2_HOME=/home/niteride/.pm2 pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(\"    - \" + p[\"name\"]) for p in d]"' 2>/dev/null || echo "    - <unreadable>")

env_var_names:
$(run_remote 'grep -oE "^[A-Z_][A-Z0-9_]*" /opt/niteride/.env 2>/dev/null | sort -u | sed "s/^/  - /"' 2>/dev/null || echo "  - <unreadable>")

nginx_sites:
$(run_remote 'ls /etc/nginx/sites-enabled/ 2>/dev/null | sed "s/^/  - /"' 2>/dev/null || echo "  - <unreadable>")

disk:
  opt_niteride_size: "$(run_remote 'du -sh /opt/niteride 2>/dev/null | awk "{print \$1}"' || echo unknown)"
  segments_size: "$(run_remote 'du -sh /var/www/hls/segments 2>/dev/null | awk "{print \$1}"' || echo unknown)"
EOF
}

emit

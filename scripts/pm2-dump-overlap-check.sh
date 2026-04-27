#!/bin/bash
# pm2-dump-overlap-check.sh
# Verify channel-server PM2 dump.pm2 invariant:
#   "MUST NOT have OVERLAPPING dump.pm2 entries between root and niteride daemons.
#    Each app name resolves to exactly one daemon-of-record."
#
# Why this exists: Task #35 (2026-04-26) — a stale entry of `storage-service-ch{N}`
# in /root/.pm2/dump.pm2 (Apr 13) AND in /home/niteride/.pm2/dump.pm2 (Apr 26)
# made the post-reboot port-race for 9070 non-deterministic. The losing copy
# crash-looped (23,000+ restarts on CH1 over 8 days); the winning copy could
# silently open data files O_RDONLY because of inherited root ownership.
# This script catches the dump-level overlap BEFORE the system reboots into a
# split-brain state.
#
# Exit 0 = no overlap (invariant satisfied).
# Exit 1 = overlap detected (invariant violated — investigate before reboot).
# Exit 2 = SSH / parse / runtime error.
#
# Usage:
#   pm2-dump-overlap-check.sh           # check both channels
#   pm2-dump-overlap-check.sh ch1        # check CH1 only
#   pm2-dump-overlap-check.sh ch2        # check CH2 only

set -u

CH1_HOST="root@82.22.53.218"
CH1_KEY="$HOME/repos/niteridefm/myKeys/niteride-fm-ch1"
CH2_HOST="root@82.22.53.167"
CH2_KEY="$HOME/repos/niteridefm/myKeys/niteride-fm-ch2"

# Channels to check (default: both).
TARGET="${1:-both}"

case "$TARGET" in
  ch1|ch2|both) ;;
  *)
    echo "Usage: $0 [ch1|ch2|both]" >&2
    exit 2
    ;;
esac

# Per-channel check. Reads both dump files via SSH, extracts app names with python,
# computes intersection. Echoes one line per channel: "<channel> <verdict> [<details>]".
check_channel() {
  local channel="$1"
  local host="$2"
  local key="$3"

  # Pull both dump.pm2 files in one SSH round-trip. Use base64 to keep the
  # JSON intact across the shell pipe (avoids quoting hell with embedded "
  # and \n in env blocks).
  local payload
  payload=$(ssh -i "$key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$host" '
    {
      echo "===ROOT==="
      base64 -w0 /root/.pm2/dump.pm2 2>/dev/null || echo "MISSING"
      echo ""
      echo "===NITERIDE==="
      sudo -u niteride base64 -w0 /home/niteride/.pm2/dump.pm2 2>/dev/null || echo "MISSING"
      echo ""
    }
  ' 2>/dev/null)

  if [ -z "$payload" ]; then
    echo "$channel ERROR ssh-failed"
    return 2
  fi

  # Parse the two base64 blocks and compute intersection in python.
  # Use env var, not stdin pipe — `python3 - <<'PY'` and a pipe both want stdin,
  # and the heredoc wins (script reads as empty data, prints false MISSING).
  local result
  result=$(PM2_DUMP_PAYLOAD="$payload" python3 <<'PY'
import os, base64, json, re

text = os.environ['PM2_DUMP_PAYLOAD']
# Split on the markers.
parts = re.split(r'===(ROOT|NITERIDE)===\n', text)
# parts = ['', 'ROOT', '<b64>\n', 'NITERIDE', '<b64>\n']
sections = {}
for i in range(1, len(parts) - 1, 2):
    sections[parts[i]] = parts[i + 1].strip()

def names_from(b64):
    if not b64 or b64 == 'MISSING':
        return None
    try:
        raw = base64.b64decode(b64).decode('utf-8', errors='replace')
        data = json.loads(raw)
        return sorted({app.get('name') for app in data if isinstance(app, dict) and app.get('name')})
    except Exception as e:
        return f'PARSE_ERR:{type(e).__name__}'

root_names = names_from(sections.get('ROOT', ''))
nite_names = names_from(sections.get('NITERIDE', ''))

if root_names is None:
    print('ERROR root-dump-missing')
    sys.exit(0)
if nite_names is None:
    print('ERROR niteride-dump-missing')
    sys.exit(0)
if isinstance(root_names, str) and root_names.startswith('PARSE_ERR'):
    print(f'ERROR root-{root_names}')
    sys.exit(0)
if isinstance(nite_names, str) and nite_names.startswith('PARSE_ERR'):
    print(f'ERROR niteride-{nite_names}')
    sys.exit(0)

overlap = sorted(set(root_names) & set(nite_names))
if overlap:
    print(f'FAIL overlap={",".join(overlap)} root_count={len(root_names)} niteride_count={len(nite_names)}')
else:
    print(f'PASS root_count={len(root_names)} niteride_count={len(nite_names)}')
PY
  )

  echo "$channel $result"

  case "$result" in
    PASS*)  return 0 ;;
    FAIL*)  return 1 ;;
    *)      return 2 ;;
  esac
}

OVERALL=0
if [ "$TARGET" = "ch1" ] || [ "$TARGET" = "both" ]; then
  check_channel "ch1" "$CH1_HOST" "$CH1_KEY"
  rc=$?
  [ "$rc" -gt "$OVERALL" ] && OVERALL=$rc
fi
if [ "$TARGET" = "ch2" ] || [ "$TARGET" = "both" ]; then
  check_channel "ch2" "$CH2_HOST" "$CH2_KEY"
  rc=$?
  [ "$rc" -gt "$OVERALL" ] && OVERALL=$rc
fi

exit "$OVERALL"

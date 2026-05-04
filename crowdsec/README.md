# CrowdSec configuration tracked here

Source-of-truth files that ship to every NiteRide CrowdSec agent + the LAPI host (orch).

## What's in here

```
crowdsec/
└── parsers/
    └── s02-enrich/
        └── niteride-gcore-whitelist.yaml   # Whitelist GCore CDN edge + shield POPs
```

## Why this exists

**2026-05-03 P0 incident**: bot scanners hit `https://cdn.niteride.fm/.env`, `setup.cgi`, etc. → GCore proxied to origin → origin nginx logged the request as coming from the GCore shield POP IP (not the bot) → CrowdSec's `crowdsecurity/http-sensitive-files` scenario fired after 5 events → **banned the GCore shield IP** → all stream traffic dropped at the firewall → browsers saw "CORS preflight blocked" (manufactured 504s lacking CORS headers).

The whitelist tells CrowdSec to never ban a GCore IP regardless of what scenarios fire.

## Two layers (both required)

| Layer | File | Stage | What it filters |
|---|---|---|---|
| Parser whitelist | `parsers/s02-enrich/niteride-gcore-whitelist.yaml` | Each agent's parser pipeline (`s02-enrich`) | Local CrowdSec scenarios — `http-sensitive-files`, `http-bad-user-agent`, etc. before they post a decision to LAPI |
| LAPI allowlist (on orch) | `cscli allowlists niteride-gcore` | LAPI decision-delivery boundary | ALL decision sources — local + CAPI/community-blocklist + manual `cscli` + console pushes — before bouncer sees them |

The parser whitelist alone is **insufficient**: CAPI-pushed decisions from CrowdSec.net bypass the parser pipeline. The 2026-05-03 incident on orch had 7500+ active CAPI decisions; if any of them ever lists a GCore IP for unrelated abuse, the parser whitelist won't help. **Both layers must be in place.**

## Operating procedure

### Manual one-shot regeneration
```bash
python3 scripts/gcore-whitelist-generate.py > crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml
```
Generator hits `https://api.gcore.com/cdn/public-ip-list` (no auth) and produces a stable, sorted, deterministic YAML.

### Daily auto-sync
GitHub Actions workflow at `.github/workflows/gcore-whitelist-daily.yml`. Runs 06:00 UTC, runs `scripts/gcore-whitelist-sync.sh`, opens a PR if upstream diverges. Safety gate: refuses to write output if new count <100 OR <0.9× previous count. **Never auto-merges** — human reviews the diff.

### Push to live agents (after merge)
```bash
# Each agent (CH1, CH2, web) — file goes to /etc/crowdsec/parsers/s02-enrich/
./scripts/sync-crowdsec-whitelist.sh 82.22.53.218 --ssh-key ~/repos/niteridefm/myKeys/niteride-fm-ch1
./scripts/sync-crowdsec-whitelist.sh 82.22.53.167 --ssh-key ~/repos/niteridefm/myKeys/niteride-fm-ch2
./scripts/sync-crowdsec-whitelist.sh 194.247.183.37 --ssh-key ~/Documents/myKeysNoAI/niteride_web_node_noai
./scripts/sync-crowdsec-whitelist.sh 139.60.162.20 --ssh-key ~/Documents/myKeysNoAI/hostkey_iceland_noai
```

### Sync orch's LAPI allowlist (after merge)
```bash
# SSH to orch and run on the LAPI host
ssh -i ~/Documents/myKeysNoAI/hostkey_iceland_noai root@139.60.162.20 \
  'cd /tmp && bash -s' < ./scripts/gcore-allowlist-sync.sh
# OR copy the script + run remotely:
scp -i ... scripts/gcore-allowlist-sync.sh root@139.60.162.20:/tmp/
scp -i ... crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml root@139.60.162.20:/tmp/
ssh -i ... root@139.60.162.20 'bash /tmp/gcore-allowlist-sync.sh --whitelist /tmp/niteride-gcore-whitelist.yaml'
```

### New server bootstrap
`bootstrap/bootstrap-channel-server.sh` includes `phase_crowdsec` that copies the whitelist + reloads + verifies. The CrowdSec package itself is also installed in `phase_apt` from the standard CrowdSec apt repo.

## Cross-references

- `~/products/niteride/engineering/platforms/gcore-cdn.md` — full GCore architecture, API reference, IP-rotation analysis
- `~/products/niteride/engineering/runbooks/failure-modes.md` — symptom row "Browser sees CORS preflight blocked..."
- `~/products/niteride/engineering/backlog.md` P0 entry — 7-action durability plan
- `wiki/log.md` — 2026-05-03 incident entry

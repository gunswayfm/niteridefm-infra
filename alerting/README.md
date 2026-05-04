# NiteRide.FM Grafana Alerting Provisioning

Version-controlled mirror of `/etc/grafana/provisioning/alerting/` on the monitoring server (`194.247.182.159`).

## Architecture

```
app code (any niteridefm-be service)
    │
    ▼  log.alert("[ALERT] ...") → stderr
PM2  →  Promtail (job: pm2)  →  Loki  (already wired pre-2026-05-04)
                                  │
                                  ▼  data source query
                          Grafana Unified Alerting
                                  │
                                  ▼  alert rule fires
                                Notification Policy
                                  │
                                  ▼  routes by severity=critical
                       niteride-discord-alerts contact point
                                  │
                                  ▼  Discord webhook ($DISCORD_WEBHOOK_URL)
                            NiteRide Discord channel
```

Wired 2026-05-04. Pre-wiring state: Grafana had 0 alert rules + 0 contact points; alert delivery rate was 0% across the entire platform (every `IntegrityReconciler.fireAlert` and `scheduler-monitor` `[ALERT]` log line was logged-and-discarded with no signal leaving the box).

## Files

- **`niteride-contact-points.yaml`** — Discord webhook contact point. Webhook URL is parameterized via `$DISCORD_WEBHOOK_URL` env var (set in `/etc/default/grafana-server` on monitoring server, NOT in this repo).
- **`niteride-alert-rules.yaml`** — alert rule `scheduler_monitor_alert_pattern`: LogQL `sum(count_over_time({job="pm2"} |~ "\\[ALERT\\]" [5m]))`, fires on threshold > 0, eval interval 1m. Loki data source UID is `P8E80F9AEF21F6940` (orch's local Loki). Folder: `NiteRide`. Severity label: `critical`.
- **`niteride-policies.yaml`** — root notification policy routes everything to `niteride-discord-alerts`. `group_wait: 30s`, `group_interval: 5m`, `repeat_interval: 1h` — sustained outages produce ~1 Discord message per hour, not per-eval-tick spam.

## Adding a New Service to Alerting

If a new service needs alerts, just have it write `[ALERT]` log lines to stderr. PM2 captures, Promtail scrapes, Loki ingests, the existing alert rule matches the pattern. **No per-service webhook config needed.**

```js
// Pattern (any niteridefm-be service)
console.error('[MyService] [ALERT] something bad happened: ...');
```

## Deploy Procedure

These files don't auto-deploy — there's no monitoring-server CI workflow yet (see backlog item).

Manual deploy:

```bash
# 1. Edit YAML in this repo
# 2. Commit + push + PR + merge
# 3. SCP to monitoring server
scp -i ~/repos/niteridefm/myKeys/hostkey_iceland_loki \
  alerting/*.yaml \
  root@194.247.182.159:/etc/grafana/provisioning/alerting/

# 4. Restart Grafana to load (or reload via SIGHUP)
ssh -i ~/repos/niteridefm/myKeys/hostkey_iceland_loki root@194.247.182.159 \
  "systemctl restart grafana-server && systemctl is-active grafana-server"

# 5. Verify provisioning loaded without errors
ssh -i ~/repos/niteridefm/myKeys/hostkey_iceland_loki root@194.247.182.159 \
  "journalctl -u grafana-server --since '1 minute ago' | grep -iE 'provisioning|error'"
```

## Test Fire (verify the chain works end-to-end)

```bash
# Write a test [ALERT] line to a pm2 log on orch
ssh -i ~/Documents/myKeysNoAI/hostkey_iceland_noai root@139.60.162.20 \
  "echo '[TestService] [ALERT] manual wiring verification $(date -u +%FT%TZ)' >> /root/.pm2/logs/scheduler-monitor-out-5.log"

# Wait ~90s (Grafana eval interval 1m + group_wait 30s)
# Check Discord channel — alert should appear with the test message
```

## Credentials + Secrets

- **`DISCORD_WEBHOOK_URL`** lives ONLY in `/etc/default/grafana-server` on monitoring server. Not in any repo. To rotate: edit on server, `systemctl restart grafana-server`.
- **Grafana admin password**: stored in macOS Keychain (`security find-generic-password -s "Grafana Admin (NiteRide monitoring 194.247.182.159)" -w`).

## References

- `wiki/log.md` 2026-05-04 entry covering scheduler-monitor + alerting wiring
- `~/products/niteride/engineering/backlog.md` (closed P0 entry "CLM_ALERT_WEBHOOK_URL not set")
- Global `~/.claude/CLAUDE.md` MONITORING SERVER section (alerting architecture documented)

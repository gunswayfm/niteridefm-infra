# NiteRide Channel-Server Bootstrap

Reproducible provisioning for a NiteRide.FM channel server (Ubuntu 24.04 LTS bare host → fully-configured channel ready to receive a streaming-core deploy).

## When to run

- **New channel onboarding** (CH3, CH4, ...)
- **Cold rebuild** after catastrophic hardware failure on CH1/CH2
- **Scratch VM rehearsal** (validates the script + golden state without prod risk)

This script never runs on an already-bootstrapped channel server; it refuses unless `--force-rebuild` is passed.

## Pre-conditions

- Bare Ubuntu 24.04 LTS host (root access)
- Network connectivity to NodeSource + Ubuntu apt mirrors
- `.env` content available — either piped via stdin or referenced via `--env-file PATH`
- Channel ID assigned (1, 2, 3, ...)

## Quick start

```bash
# Onboarding CH3 — pull .env from CH1 and pipe in
ssh root@82.22.53.218 'cat /opt/niteride/.env' | \
    sudo bash -c 'cd /opt && git clone https://github.com/gunswayfm/niteridefm-infra.git && \
    bash niteridefm-infra/bootstrap/bootstrap-channel-server.sh 3'

# Or with an explicit env file
sudo ./bootstrap-channel-server.sh 3 --env-file /tmp/ch3.env

# Dry-run (recommended first pass)
sudo ./bootstrap-channel-server.sh 3 --env-file /tmp/ch3.env --dry-run
```

After the script completes, edit the new `.env` to set channel-specific vars (`CHANNEL_ID`, `REDIS_URL`, etc.) before triggering the deploy workflow.

## What the script does (9 phases)

1. **Pre-flight** — root check, Ubuntu 24.04 sanity, refuse-on-existing, .env source resolved
2. **apt** — Node 20.x via NodeSource + ffmpeg 6.1.1 + nginx + redis-tools + postgresql-client + jq + python3
3. **PM2 6.0.14** — npm install -g (matches CH1/CH2 prod version)
4. **niteride user** — UID 999 / GID 989 (matches CH1/CH2)
5. **Directory layout** — `/opt/niteride/{,data,services}` + `/var/www/hls/segments/`, all `niteride:niteride`
6. **Dual systemd** — `pm2-root.service` + `pm2-niteride.service` (encodes the dual-daemon invariant from Task #35)
7. **`.env` hydration** — installs file at `/opt/niteride/.env` mode 0600 niteride:niteride
8. **Nginx site** — renders `ch{N}-hls.conf` from `ch-hls.conf.template`, symlinks into sites-enabled
9. **Validation** — verifies UID/GID, ownership, systemd state, version pins, .env perms

Failure at any phase exits with a distinct code (2=pre-flight, 3=install/config, 4=post-validation).

## Post-bootstrap manual steps

The script provisions the BOX. It does NOT clone or start service code. After it succeeds:

1. **Trigger channel deploy workflow:**
   ```bash
   gh workflow run deploy-ch${CHANNEL_ID}.yml --repo gunswayfm/niteridefm-streaming-core
   ```
   This clones `niteridefm-streaming-core` into `/opt/niteride/` and `pm2 start ecosystem.config.js`s the apps onto the appropriate daemons.

2. **Persist PM2 dumps for reboot survival:**
   ```bash
   pm2 save
   sudo -u niteride PM2_HOME=/home/niteride/.pm2 pm2 save
   ```

3. **Verify dual-daemon invariant:**
   ```bash
   ~/code/niteridefm-infra/scripts/pm2-dump-overlap-check.sh
   ```
   Expected exit 0 (zero overlap between root and niteride dump.pm2).

4. **DNS / GCore origin pool update** (only for new channels — not cold rebuilds of an existing IP).

## State capture for drift detection

`capture-channel-state.sh` emits a YAML snapshot of the golden state. Run against CH1 + CH2 to detect drift:

```bash
./capture-channel-state.sh --ssh root@82.22.53.218 > /tmp/ch1-state.yaml
./capture-channel-state.sh --ssh root@82.22.53.167 > /tmp/ch2-state.yaml
diff /tmp/ch1-state.yaml /tmp/ch2-state.yaml
```

Differences in the `pm2_apps`, `versions`, `ownership`, or `systemd` sections are signal that the fleet drifted.

## Limitations / out of scope (filed in backlog)

- **`.env` encryption pattern**: today operator pipes from password manager or existing prod `.env`. Future migration to age/sops sealed file in `niteridefm-infra/secrets/` is P2 backlog.
- **`ecosystem.config.js` `user:` fields**: the dual-daemon split is encoded in systemd unit User= directives + which-user-runs-pm2-start, not in app config. Adding `user:` fields to streaming-core's ecosystem is P2 backlog.
- **CH2 nginx normalization**: CH2 currently runs `cdn.niteride.fm.conf` (legacy from pre-multi-channel era). Bootstrap deploys the clean `ch{N}-hls.conf` pattern. CH2 normalization is a separate PR.
- **Drift detection cron**: `capture-channel-state.sh` is currently manual. Wiring it into a daily cron + Loki alert is P2 backlog.
- **Data-volume restore** (`/var/www/hls/segments/episodes/` ~50-100GB): not in bootstrap scope. PrefetchAgent re-fetches on demand; cold start is slow but not blocking.

## References

- Handover: `~/products/niteride/projects/_handover-fleet-bootstrap-2026-04-27.md`
- Invariants: `~/products/niteride/engineering/invariants.md` (dual-daemon overlap rule line 43; migration ownership rule line 47)
- Failure modes: `~/products/niteride/engineering/runbooks/failure-modes.md` (PrefetchAgent stuck at cycleCount: 0 row)
- Validation script: `~/code/niteridefm-infra/scripts/pm2-dump-overlap-check.sh`

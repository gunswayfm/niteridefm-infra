# Redactions — CH2 channel server (82.22.53.167)

Captured 2026-04-23.

## Redactions performed

**None.** No hardcoded secrets.

## Values that look sensitive but are NOT secrets

| File | Line | Directive | Why it's safe |
|------|------|-----------|---------------|
| `sites-enabled/cdn.niteride.fm.conf` | 49 | `proxy_set_header Authorization $http_authorization;` | Dynamic passthrough. |
| `sites-available/cdn.niteride.fm.conf` + 3 `.bak` files | various | same | Same — backups only, not the live config. |
| `sites-available/tusd.conf` | 10-11 | TLS cert paths `/etc/letsencrypt/live/upload.niteride.fm/` | Cert paths only. File is NOT enabled on this box. |

## Drift note — sites-enabled vs sites-available

`sites-enabled/cdn.niteride.fm.conf` is a **regular file**, NOT a symlink, and is ~2256 bytes smaller than `sites-available/cdn.niteride.fm.conf`. The live config is `sites-enabled/cdn.niteride.fm.conf`.

## Expected live secrets (NOT in nginx configs)

None. Same as CH1 — application-layer signing happens in the playlist-generator / streaming-core services.

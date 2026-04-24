# Redactions — CH1 channel server (82.22.53.218)

Captured 2026-04-23.

## Redactions performed

**None.** No hardcoded secrets.

## Values that look sensitive but are NOT secrets

| File | Line | Directive | Why it's safe |
|------|------|-----------|---------------|
| `sites-enabled/ch1-hls.conf` | 24 | `proxy_set_header Authorization $http_authorization;` | Dynamic passthrough, not hardcoded. |
| `sites-available/ch1-hls.conf` | 22 | same | Same — but note this file is NOT the live config; see drift below. |

## Drift note — sites-enabled vs sites-available

`sites-enabled/ch1-hls.conf` is a **regular file**, NOT a symlink, and differs materially from `sites-available/ch1-hls.conf`. The live config is `sites-enabled/ch1-hls.conf`. That's what must be restored on a flattened server.

## Expected live secrets (NOT in nginx configs)

None. CH1 nginx does no HMAC link signing, no auth_basic, no hardcoded tokens. Secure-link logic (if any) happens at the application layer (playlist-generator on 127.0.0.1:9050).

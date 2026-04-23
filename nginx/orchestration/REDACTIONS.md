# Redactions — orchestration server (139.60.162.20)

Captured 2026-04-23.

## Redactions performed

**None.** Scan found no hardcoded secrets in this server's nginx configuration.

## Values that look sensitive but are NOT secrets

| File | Line | Directive | Why it's safe |
|------|------|-----------|---------------|
| `sites-available/cdn.niteride.fm.conf` | 59, 133, 207 | `proxy_set_header Authorization $http_authorization;` | Passes the CLIENT's Authorization header to upstream. Not a hardcoded token. |
| `sites-available/tusd.conf` | 25 | `proxy_set_header Authorization $http_authorization;` | Same — dynamic passthrough. |
| `sites-available/niteride.fm` | 5-6 | TLS cert paths `/etc/letsencrypt/live/admin.niteride.fm/` | Cert paths, not cert contents. |
| `sites-available/tusd.conf` | 10-11 | TLS cert paths `/etc/letsencrypt/live/upload.niteride.fm/` | Cert paths, not cert contents. |

## External dependencies at runtime

- **TLS certs** at `/etc/letsencrypt/live/{admin.niteride.fm,upload.niteride.fm}/` — certbot-managed.
- **tusd upstream** on 127.0.0.1:8443 — self-signed; proxy_ssl_verify off. No secret in the nginx config.

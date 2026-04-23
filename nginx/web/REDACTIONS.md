# Redactions — web server (194.247.183.37)

Captured 2026-04-23.

## Redactions performed

**None.** Scan found no hardcoded secrets in this server's nginx configuration.

## Values that look sensitive but are NOT secrets

| File | Line | Directive | Why it's safe |
|------|------|-----------|---------------|
| `sites-available/tusd-proxy.conf` | 31 | `proxy_set_header Authorization $http_authorization;` | Passes the CLIENT's Authorization header to upstream. Not a hardcoded token. |
| `sites-available/cdn.niteride.fm.conf` | 57 | `proxy_set_header Authorization $http_authorization;` | Same — dynamic passthrough. |
| `sites-available/niteride.fm.conf` | many | TLS cert paths under `/etc/letsencrypt/live/niteride.fm/`, `/etc/letsencrypt/live/api.niteride.fm/` | Cert paths, not cert contents. Certbot-managed; not committed. |

## External dependencies at runtime

- **TLS certs** at `/etc/letsencrypt/live/{niteride.fm,api.niteride.fm}/` — managed by system `certbot.timer`. Bootstrap must run `certbot --nginx` after placing configs.
- **CORS origin map** — defined in `sites-available/cors-map.conf`; symlinked into `sites-enabled/`. No secret content.

# Redactions — Grid server (82.22.53.68)

Captured 2026-04-23.

## Redactions performed

| File | Line | Original value | Redacted to | Where the real value lives |
|------|------|----------------|-------------|----------------------------|
| `docker-nginx/docker-compose.yml` | 89 | `PICTRS__API_KEY=API_KEY` | `PICTRS__API_KEY=__REDACTED__` | Default Lemmy/Pictrs inter-service API key. Lives in committed compose by design in the upstream Lemmy project, but treated here as a secret. Restore from `/opt/niteridefm-grid/docker/.env` / ops secrets store. Value is the literal string `API_KEY`. |

## Values that look sensitive but are NOT secrets

| File | Line | Directive | Why it's safe |
|------|------|-----------|---------------|
| `docker-nginx/docker-compose.yml` | 39 | `SUPABASE_JWT_SECRET=${SUPABASE_JWT_SECRET}` | Env-var reference. Value lives in `/opt/niteridefm-grid/docker/.env`. |
| `docker-nginx/docker-compose.yml` | 117 | `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}` | Same — env-var reference only. |
| `sites-available/grid` | 13-14 | TLS cert paths `/etc/letsencrypt/live/grid.niteride.fm/` | Cert paths only. |
| `docker-nginx/nginx.conf` | various | `proxy_pass http://lemmy-alpha;` etc. | Docker-compose internal service hostnames — `lemmy-alpha`/`-beta`/`-delta`/`-epsilon`/`-gamma` appear in the config (FEDERATION NGINX stub). Not in use in this deployment (we don't federate). |

## External dependencies at runtime

- `/opt/niteridefm-grid/docker/.env` — contains `SUPABASE_JWT_SECRET`, `POSTGRES_PASSWORD`, and other env vars referenced by compose
- `/etc/letsencrypt/live/grid.niteride.fm/` — Certbot-managed TLS certs
- Host nginx is the TLS terminator; the docker-proxy-1 container is plain HTTP inside the docker network

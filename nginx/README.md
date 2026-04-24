# `nginx/` — Captured production nginx configurations

**Purpose**: if any production box is flattened, the configs here are ground truth for rebuilding nginx on that server. Bootstrap automation (see [`~/products/niteride/projects/server-bootstrap-dr/`](~/products/niteride/projects/server-bootstrap-dr/)) will consume these as its nginx seed.

**Captured**: 2026-04-23 (Q6 Part A of the engineering-mapping Phase 3 decisions).

**Capture method**: `scp` pulls of `/etc/nginx/{nginx.conf, sites-available/*, sites-enabled/*, conf.d/*, snippets/*}` on each live production box via SSH.

**Source of truth for live state**: `sites-enabled/` wins over `sites-available/` when the two disagree (see drift notes in `ch1/sites-enabled.txt` and `ch2/sites-enabled.txt`). For servers where `sites-enabled/` is symlinked into `sites-available/` (web, orchestration, grid), the two are identical and the symlink target is authoritative.

## Layout

| Subdir | Server | IP | Role |
|--------|--------|----|------|
| `web/` | Web / Gateway | 194.247.183.37 | Public ingress: SPA + microservice routing + CORS/TLS |
| `orchestration/` | Orchestration / CDN origin | 139.60.162.20 | GCore origin, admin vhost, tusd proxy |
| `ch1/` | Channel 1 | 82.22.53.218 | HLS playlists + segments |
| `ch2/` | Channel 2 | 82.22.53.167 | HLS playlists + segments |
| `grid/` | Grid (social) | 82.22.53.68 | Host nginx TLS terminator + docker-compose `docker-proxy-1` container nginx |

Each subdir contains:

- `nginx.conf` — top-level config from `/etc/nginx/nginx.conf`
- `sites-available/` — every file from `/etc/nginx/sites-available/` (including `.bak` files for traceability)
- `sites-enabled/` — **only present when the enabled file is a regular file, not a symlink** (CH1 and CH2). For the other three boxes, `sites-enabled.txt` captures the symlink manifest.
- `sites-enabled.txt` — manifest of which vhosts are active and whether they are symlinks or regular files
- `conf.d/` — every file from `/etc/nginx/conf.d/` (omitted if empty on the server)
- `includes/snippets/` — every file from `/etc/nginx/snippets/`
- `VERSION.txt` — output of `nginx -v` and `nginx -t` captured at the moment of snapshot
- `REDACTIONS.md` — per-file catalog of redactions performed (or "none" with rationale)

### Grid extra: `grid/docker-nginx/`

The Grid server runs a secondary nginx inside the `docker-proxy-1` container (`nginx:1-alpine`). The host nginx only terminates TLS and forwards to `localhost:8536` — all the real routing (Lemmy UI on 1235, Lemmy backend on 8536, Pictrs) happens inside the container. That container mounts `/opt/niteridefm-grid/docker/nginx.conf` at `/etc/nginx/nginx.conf`. Captured under `grid/docker-nginx/nginx.conf`, with the full `docker-compose.yml` for context (secrets redacted per `REDACTIONS.md`).

## How to rebuild a server's nginx from here

1. Install nginx 1.24.0 (Ubuntu): `apt-get install nginx=1.24.0-*ubuntu* -y`
2. Ensure `/etc/nginx/nginx.conf` matches the repo copy for that server:
   ```
   rsync -av nginx/<server>/nginx.conf root@<ip>:/etc/nginx/nginx.conf
   ```
3. Sync sites-available, conf.d, snippets:
   ```
   rsync -av --delete \
     nginx/<server>/sites-available/ root@<ip>:/etc/nginx/sites-available/
   rsync -av --delete \
     nginx/<server>/includes/snippets/ root@<ip>:/etc/nginx/snippets/
   [ -d nginx/<server>/conf.d ] && rsync -av --delete \
     nginx/<server>/conf.d/ root@<ip>:/etc/nginx/conf.d/
   ```
4. Recreate sites-enabled. For boxes using symlinks (web / orchestration / grid), follow `sites-enabled.txt`:
   ```
   ln -sf /etc/nginx/sites-available/<file> /etc/nginx/sites-enabled/<file>
   ```
   For CH1 and CH2, copy the regular file from this repo directly:
   ```
   rsync -av nginx/<server>/sites-enabled/ root@<ip>:/etc/nginx/sites-enabled/
   ```
5. Obtain / restore TLS certs with `certbot --nginx -d <domain>` (see each REDACTIONS.md for the list of cert paths).
6. Replace any `__REDACTED__` tokens with live values from the appropriate source:
   - `/opt/niteride/.env` on web + orchestration (`SEGMENT_SIGNING_SECRET`, etc. — none currently present in nginx, but check before every restore)
   - `ch1.env.enc` / `ch2.env.enc` for channel-specific keys (none currently in nginx configs)
   - `/opt/niteridefm-grid/docker/.env` for Grid (`PICTRS__API_KEY`, `SUPABASE_JWT_SECRET`, `POSTGRES_PASSWORD`)
7. Validate and reload:
   ```
   nginx -t && systemctl reload nginx
   ```

## Currently-redacted values to restore

| Server | File | Placeholder | Source of truth |
|--------|------|-------------|-----------------|
| grid   | `docker-nginx/docker-compose.yml` line 89 | `PICTRS__API_KEY=__REDACTED__` | `/opt/niteridefm-grid/docker/.env` → literal string `API_KEY` (Lemmy default) |

No other server requires post-paste secret substitution at this snapshot.

## Related

- [`~/products/niteride/projects/server-bootstrap-dr/CLAUDE.md`](~/products/niteride/projects/server-bootstrap-dr/CLAUDE.md) — full DR automation; this directory is the nginx slice.
- [`~/products/niteride/engineering/platforms/nginx-gateway.md`](~/products/niteride/engineering/platforms/nginx-gateway.md) — web server architecture doc.
- [`~/products/niteride/engineering/platforms/nginx-cdn-origin.md`](~/products/niteride/engineering/platforms/nginx-cdn-origin.md) — orchestration CDN origin doc.
- [`~/products/niteride/engineering/platforms/nginx-ppe.md`](~/products/niteride/engineering/platforms/nginx-ppe.md) — PPE / staging nginx doc.
- [`~/products/niteride/projects/server-bootstrap-dr/nginx-capture-report.md`](~/products/niteride/projects/server-bootstrap-dr/nginx-capture-report.md) — this capture's report, including surprises vs docs.

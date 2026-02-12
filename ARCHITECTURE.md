# NiteRide.FM Infrastructure Architecture

*Auto-generated on 2026-02-12 06:33 UTC*

![Architecture Diagram](diagrams/architecture.png)

---

## Web Server

**IP:** `194.247.183.37`  
**Purpose:** Orchestration, Auth, V9 Microservices (Identity, Public, Guide), Nginx proxy

### System

| Property | Value |
|----------|-------|
| Hostname | `is-vmv3-medium` |
| OS | Ubuntu 24.04.1 LTS |
| Kernel | 6.8.0-94-generic |
| Load Average | 0.01, 0.02, 0.00 |

**Memory:** 975.7 MB / 15.6 GB (6.1% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 156.4 GB | 14.7 GB | 135.2 GB | 10% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| niteride-backend | 3000 | online | 91 MB | 0% | 0 |
| guide-service | 3105 | online | 84 MB | 0% | 0 |
| identity-service | 3001 | online | 100 MB | 0% | 0 |
| chat-service | 4000 | online | 97 MB | 0% | 0 |

### Listening Ports

| Port | Process | PM2 App | Address |
|------|---------|---------|----------|
| 22 | sshd | - | all interfaces |
| 53 | systemd-resolve | - | 127.0.0.53%lo |
| 53 | systemd-resolve | - | 127.0.0.54 |
| 80 | nginx | - | all interfaces |
| 80 | nginx | - | [::] |
| 443 | nginx | - | all interfaces |
| 443 | nginx | - | [::] |
| 3000 | unknown | - | all interfaces |
| 3001 | unknown | - | all interfaces |
| 3105 | unknown | - | all interfaces |
| 4000 | unknown | - | all interfaces |
| 5432 | postgres | - | all interfaces |
| 5432 | postgres | - | [::] |

### Key Systemd Services

| Service | Status |
|---------|--------|
| docker.service | active/running |
| nginx.service | active/running |
| pm2-root.service | active/running |
| postgresql@16-main.service | active/running |

### Nginx

**Version:** 1.24.0 (Ubuntu)

**Proxy Routes:**
- `http://127.0.0.1:3105`
- `http://82.22.53.68:8536`
- `https://194.247.182.249`
- `http://127.0.0.1:4000`
- `http://194.247.182.249:3002`
- `http://127.0.0.1:3000`
- `http://localhost:9050/`
- `http://127.0.0.1:4000/socket.io/`
- `http://localhost:3000/socket.io/`
- `http://82.22.53.68:1236/socket.io/`
- *...and 4 more*

### Service Connections

| From | To | Port | Type |
|------|-----|------|------|
| niteride-backend | postgres | 5432 | data |
| guide-service | postgres | 5432 | data |
| identity-service | postgres | 5432 | data |
| chat-service | postgres | 5432 | data |
| niteride-backend | postgres | 5432 | data |
| guide-service | postgres | 5432 | data |
| identity-service | postgres | 5432 | data |
| chat-service | postgres | 5432 | data |
| nginx | http://127.0.0.1:3105 | 3105 | proxy |
| nginx | http://82.22.53.68:8536 | 8536 | proxy |
| nginx | https://194.247.182.249 | 80 | proxy |
| nginx | http://127.0.0.1:4000 | 4000 | proxy |
| nginx | http://194.247.182.249:3002 | 3002 | proxy |
| nginx | http://127.0.0.1:3000 | 3000 | proxy |
| nginx | http://localhost:9050/ | 9050 | proxy |
| nginx | http://127.0.0.1:4000/socket.io/ | 4000 | proxy |
| nginx | http://localhost:3000/socket.io/ | 3000 | proxy |
| nginx | http://82.22.53.68:1236/socket.io/ | 1236 | proxy |
| nginx | http://82.22.53.68:1236/ | 1236 | proxy |
| nginx | http://127.0.0.1:3001 | 3001 | proxy |
| nginx | http://127.0.0.1:3105/$1 | 3105 | proxy |
| nginx | http://194.247.182.159:3000 | 3000 | proxy |

### External Services

| Service | Type | Detected In |
|---------|------|-------------|
| Supabase | auth/database | .env |
| Stripe | payments | .env |

---

## Stream Server

**IP:** `194.247.182.249`  
**Purpose:** HLS streaming, Redis state, Admin backend (Library, Scheduling, Commercials)

### System

| Property | Value |
|----------|-------|
| Hostname | `is-vmv3-medium` |
| OS | Ubuntu 24.04.3 LTS |
| Kernel | 6.8.0-90-generic |
| Load Average | 0.31, 0.50, 0.59 |

**Memory:** 2.5 GB / 15.6 GB (15.8% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 156.4 GB | 32.8 GB | 117.1 GB | 22% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| playlist-generator-ch1 | 9050 | online | 79 MB | 0% | 6 |
| stream-guard | - | online | 79 MB | 0% | 5 |
| cdn-prewarmer | - | online | 83 MB | 0% | 5 |
| content-segmenter | - | online | 76 MB | 0% | 5 |
| streaming-core | - | online | 103 MB | 0% | 12 |
| admin-service | 3002 | online | 101 MB | 0% | 11 |
| storage-service | - | online | 115 MB | 0% | 10 |
| stream-monitor | - | online | 77 MB | 0% | 6 |
| rtmp-receiver | - | online | 79 MB | 0% | 4 |
| live-controller | - | online | 69 MB | 0% | 4 |

### Docker Containers

| Name | Image | Ports | Status |
|------|-------|-------|--------|
| niteride-redis | `redis:alpine` | 6379:6379 | Up 5 days |
| niteridefm-postgres | `postgres:15-alpine` | 5432:5432 | Up 12 days (healthy) |
| niteridefm-pgadmin | `dpage/pgadmin4:latest` | 5050:80 | Up 5 weeks |

### Listening Ports

| Port | Process | PM2 App | Address |
|------|---------|---------|----------|
| 22 | sshd | - | all interfaces |
| 22 | sshd | - | [::] |
| 53 | systemd-resolve | - | 127.0.0.53%lo |
| 53 | systemd-resolve | - | 127.0.0.54 |
| 80 | nginx | - | all interfaces |
| 443 | nginx | - | all interfaces |
| 1935 | nginx | - | all interfaces |
| 1936 | unknown | - | all interfaces |
| 3002 | unknown | - | all interfaces |
| 3005 | unknown | - | all interfaces |
| 5050 | docker-proxy | - | 127.0.0.1 |
| 5432 | docker-proxy | - | all interfaces |
| 6379 | docker-proxy | - | all interfaces |
| 8443 | nginx | - | all interfaces |
| 8444 | tusd | - | 127.0.0.1 |
| 9003 | unknown | - | all interfaces |
| 9004 | unknown | - | all interfaces |
| 9050 | unknown | - | all interfaces |
| 9065 | unknown | - | all interfaces |
| 9070 | unknown | - | all interfaces |
| 9080 | promtail | - | all interfaces |
| 9100 | unknown | - | all interfaces |
| 33101 | promtail | - | all interfaces |
| 35517 | chrome | stream-monitor | 127.0.0.1 |

### Key Systemd Services

| Service | Status |
|---------|--------|
| docker.service | active/running |
| nginx.service | active/running |

### Nginx

**Version:** 1.24.0 (Ubuntu)

**Proxy Routes:**
- `http://194.247.182.159:3000/`
- `http://localhost:3000/socket.io/`
- `http://localhost:9070`
- `http://localhost:3000`
- `http://localhost:9050/`
- `http://localhost:3002`
- `http://127.0.0.1:8444`

### Service Connections

| From | To | Port | Type |
|------|-----|------|------|
| stream-guard | redis | 6379 | data |
| streaming-core | redis | 6379 | data |
| stream-monitor | redis | 6379 | data |
| admin-service | postgres | 5432 | data |
| storage-service | postgres | 5432 | data |
| nginx | http://194.247.182.159:3000/ | 3000 | proxy |
| nginx | http://localhost:3000/socket.io/ | 3000 | proxy |
| nginx | http://localhost:9070 | 9070 | proxy |
| nginx | http://localhost:3000 | 3000 | proxy |
| nginx | http://localhost:9050/ | 9050 | proxy |
| nginx | http://localhost:3002 | 3002 | proxy |
| nginx | http://127.0.0.1:8444 | 8444 | proxy |

### External Services

| Service | Type | Detected In |
|---------|------|-------------|
| Supabase | auth/database | .env |

---

## Grid Server

**IP:** `82.22.53.68`  
**Purpose:** Lemmy fork with Supabase auth, PostgreSQL 16, Pictrs image hosting

### System

| Property | Value |
|----------|-------|
| Hostname | `11471.example.is` |
| OS | Ubuntu 24.04.3 LTS |
| Kernel | 6.8.0-90-generic |
| Load Average | 0.07, 0.03, 0.00 |

**Memory:** 1.0 GB / 3.8 GB (27.5% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 52.8 GB | 27.2 GB | 22.9 GB | 55% |

### Docker Containers

| Name | Image | Ports | Status |
|------|-------|-------|--------|
| docker-proxy-1 | `nginx:1-alpine` | 1236:1236, 1236:1236, 8536:8536, 8536:8536 | Up 4 weeks |
| docker-lemmy-ui-1 | `dessalines/lemmy-ui:0.19.14` | 1234/tcp | Up 4 weeks (healthy) |
| docker-lemmy-1 | `docker-lemmy` | 10002:10002, 10002:10002 | Up 4 weeks |
| docker-postgres-1 | `pgautoupgrade/pgautoupgrade:16-alpine` | 5433:5432, 5433:5432 | Up 4 weeks (healthy) |
| docker-pictrs-1 | `asonix/pictrs:0.5.16` | 6669/tcp, 8080/tcp | Up 4 weeks |

### Listening Ports

| Port | Process | PM2 App | Address |
|------|---------|---------|----------|
| 22 | sshd | - | all interfaces |
| 22 | sshd | - | [::] |
| 53 | systemd-resolve | - | 127.0.0.54 |
| 53 | systemd-resolve | - | 127.0.0.53%lo |
| 80 | nginx | - | all interfaces |
| 443 | nginx | - | all interfaces |
| 1236 | docker-proxy | - | all interfaces |
| 1236 | docker-proxy | - | [::] |
| 5433 | docker-proxy | - | all interfaces |
| 5433 | docker-proxy | - | [::] |
| 8536 | docker-proxy | - | all interfaces |
| 8536 | docker-proxy | - | [::] |
| 10002 | docker-proxy | - | all interfaces |
| 10002 | docker-proxy | - | [::] |

### Key Systemd Services

| Service | Status |
|---------|--------|
| docker.service | active/running |
| nginx.service | active/running |

### Nginx

**Version:** 1.24.0 (Ubuntu)

**Proxy Routes:**
- `http://127.0.0.1:8536`

### Service Connections

| From | To | Port | Type |
|------|-----|------|------|
| nginx | http://127.0.0.1:8536 | 8536 | proxy |

---

## Monitoring Server

**IP:** `194.247.182.159`  
**Purpose:** Grafana dashboards, Loki log aggregation

### System

| Property | Value |
|----------|-------|
| Hostname | `is-vmmini` |
| OS | Ubuntu 24.04.1 LTS |
| Kernel | 6.8.0-39-generic |
| Load Average | 0.07, 0.03, 0.00 |

**Memory:** 3.1 GB / 5.8 GB (54.3% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 117.0 GB | 13.5 GB | 98.6 GB | 13% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| stream-probe | 9100 | online | 60 MB | 0% | 39 |

### Listening Ports

| Port | Process | PM2 App | Address |
|------|---------|---------|----------|
| 22 | sshd | - | all interfaces |
| 53 | systemd-resolve | - | 127.0.0.54 |
| 53 | systemd-resolve | - | 127.0.0.53%lo |
| 3000 | grafana | - | all interfaces |
| 3100 | loki | - | all interfaces |
| 9080 | promtail | - | all interfaces |
| 9095 | loki | - | all interfaces |
| 9100 | unknown | - | all interfaces |
| 33361 | chrome | stream-probe | 127.0.0.1 |
| 33603 | promtail | - | all interfaces |

### Key Systemd Services

| Service | Status |
|---------|--------|
| docker.service | active/running |
| grafana-server.service | active/running |
| loki.service | active/running |

### Nginx

**Version:** bin

---

## Data Sources

This documentation is automatically generated from live infrastructure discovery.
Discovery runs daily at 6 AM UTC via GitHub Actions.

See `discovery/` for raw JSON data and `history/` for historical snapshots.

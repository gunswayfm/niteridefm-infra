# NiteRide.FM Infrastructure Architecture

*Auto-generated on 2026-02-08 19:16 UTC*

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
| Kernel | 6.8.0-90-generic |
| Load Average | 0.00, 0.01, 0.00 |

**Memory:** 1.2 GB / 15.6 GB (7.6% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 156.4 GB | 14.3 GB | 135.6 GB | 10% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| niteride-backend | 3000 | online | 83 MB | 0% | 1 |
| guide-service | 3105 | online | 80 MB | 0% | 1 |
| identity-service | 3001 | online | 95 MB | 0% | 3 |
| chat-service | 4000 | online | 91 MB | 0% | 0 |

### Listening Ports

| Port | Process | PM2 App | Address |
|------|---------|---------|----------|
| 22 | sshd | - | all interfaces |
| 53 | systemd-resolve | - | 127.0.0.54 |
| 53 | systemd-resolve | - | 127.0.0.53%lo |
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
- `http://82.22.53.68:1236/`
- `http://127.0.0.1:3105`
- `http://82.22.53.68:1236/socket.io/`
- `http://194.247.182.249:3002`
- `http://194.247.182.159:3000`
- `http://127.0.0.1:3105/$1`
- `http://127.0.0.1:4000/socket.io/`
- `http://127.0.0.1:4000`
- `https://194.247.182.249`
- `http://127.0.0.1:3000`
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
| nginx | http://82.22.53.68:1236/ | 1236 | proxy |
| nginx | http://127.0.0.1:3105 | 3105 | proxy |
| nginx | http://82.22.53.68:1236/socket.io/ | 1236 | proxy |
| nginx | http://194.247.182.249:3002 | 3002 | proxy |
| nginx | http://194.247.182.159:3000 | 3000 | proxy |
| nginx | http://127.0.0.1:3105/$1 | 3105 | proxy |
| nginx | http://127.0.0.1:4000/socket.io/ | 4000 | proxy |
| nginx | http://127.0.0.1:4000 | 4000 | proxy |
| nginx | https://194.247.182.249 | 80 | proxy |
| nginx | http://127.0.0.1:3000 | 3000 | proxy |
| nginx | http://82.22.53.68:8536 | 8536 | proxy |
| nginx | http://localhost:3000/socket.io/ | 3000 | proxy |
| nginx | http://localhost:9050/ | 9050 | proxy |
| nginx | http://127.0.0.1:3001 | 3001 | proxy |

### External Services

| Service | Type | Detected In |
|---------|------|-------------|
| Supabase | auth/database | .env |
| Stripe | payments | .env |

---

## Stream Server

**IP:** `194.247.182.249`  
**Purpose:** HLS streaming, Redis state, Admin backend (Library, Scheduling, Commercials)

*No discovery data available*

## Grid Server

**IP:** `82.22.53.68`  
**Purpose:** Lemmy fork with Supabase auth, PostgreSQL 16, Pictrs image hosting

### System

| Property | Value |
|----------|-------|
| Hostname | `11471.example.is` |
| OS | Ubuntu 24.04.3 LTS |
| Kernel | 6.8.0-90-generic |
| Load Average | 0.24, 0.11, 0.03 |

**Memory:** 1.1 GB / 3.8 GB (27.7% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 52.8 GB | 27.2 GB | 23.0 GB | 55% |

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
| Load Average | 0.05, 0.01, 0.00 |

**Memory:** 3.0 GB / 5.8 GB (51.5% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 117.0 GB | 13.5 GB | 98.6 GB | 13% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| stream-probe | 9100 | online | 62 MB | 2.9% | 39 |

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

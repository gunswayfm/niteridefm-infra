# NiteRide.FM Infrastructure Architecture

*Auto-generated on 2026-02-17 06:30 UTC*

![Architecture Diagram](diagrams/architecture.png)

---

## Web Server

**IP:** `194.247.183.37`  
**Purpose:** Orchestration, Auth, V9 Microservices (Identity, Public, Guide), Nginx proxy

*No discovery data available*

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
| Load Average | 0.00, 0.04, 0.01 |

**Memory:** 904.2 MB / 3.8 GB (23.2% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 52.8 GB | 28.8 GB | 21.3 GB | 58% |

### Docker Containers

| Name | Image | Ports | Status |
|------|-------|-------|--------|
| docker-lemmy-1 | `ghcr.io/gunswayfm/niteridefm_grid:latest` | 10002:10002, 10002:10002 | Up 34 hours |
| docker-proxy-1 | `nginx:1-alpine` | 1236:1236, 1236:1236, 8536:8536, 8536:8536 | Up 2 days |
| docker-lemmy-ui-1 | `dessalines/lemmy-ui:0.19.14` | 1234/tcp | Up 2 days (healthy) |
| docker-pictrs-1 | `asonix/pictrs:0.5.16` | 6669/tcp, 8080/tcp | Up 2 days |
| docker-postgres-1 | `pgautoupgrade/pgautoupgrade:16-alpine` | 5433:5432, 5433:5432 | Up 2 days (healthy) |

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
| Load Average | 0.00, 0.01, 0.00 |

**Memory:** 3.3 GB / 5.8 GB (57.7% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 117.0 GB | 13.7 GB | 98.5 GB | 13% |

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

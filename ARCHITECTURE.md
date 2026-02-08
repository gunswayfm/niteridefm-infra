# NiteRide.FM Infrastructure Architecture

*Auto-generated on 2026-02-08 19:10 UTC*

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
| Load Average | 0.01, 0.02, 0.00 |

**Memory:** 1.1 GB / 15.6 GB (7.4% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 156.4 GB | 14.3 GB | 135.6 GB | 10% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| niteride-backend | - | unknown | 0 MB | 0% | 0 |
| guide-service | - | unknown | 0 MB | 0% | 0 |
| identity-service | - | unknown | 0 MB | 0% | 0 |
| chat-service | - | unknown | 0 MB | 0% | 0 |

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
| Load Average | 1.39, 0.99, 0.92 |

**Memory:** 2.4 GB / 15.6 GB (15.2% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 156.4 GB | 40.2 GB | 109.7 GB | 27% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| playlist-generator-ch1 | - | unknown | 0 MB | 0% | 0 |
| stream-guard | - | unknown | 0 MB | 0% | 0 |
| cdn-prewarmer | - | unknown | 0 MB | 0% | 0 |
| content-segmenter | - | unknown | 0 MB | 0% | 0 |
| streaming-core | - | unknown | 0 MB | 0% | 0 |
| admin-service | - | unknown | 0 MB | 0% | 0 |
| storage-service | - | unknown | 0 MB | 0% | 0 |
| stream-monitor | - | unknown | 0 MB | 0% | 0 |
| rtmp-receiver | - | unknown | 0 MB | 0% | 0 |
| live-controller | - | unknown | 0 MB | 0% | 0 |

### Docker Containers

| Name | Image | Ports | Status |
|------|-------|-------|--------|
| niteride-redis | `redis:alpine` | - | Up 38 hours |
| niteridefm-postgres | `postgres:15-alpine` | - | Up 8 days (healthy) |
| niteridefm-pgadmin | `dpage/pgadmin4:latest` | - | Up 4 weeks |

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
| 44519 | chrome | - | 127.0.0.1 |

### Key Systemd Services

| Service | Status |
|---------|--------|
| docker.service | active/running |
| nginx.service | active/running |

### Nginx

**Version:** 1.24.0 (Ubuntu)

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
| Load Average | 0.00, 0.02, 0.00 |

**Memory:** 1.1 GB / 3.8 GB (27.8% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 52.8 GB | 27.2 GB | 23.0 GB | 55% |

### Docker Containers

| Name | Image | Ports | Status |
|------|-------|-------|--------|
| docker-proxy-1 | `nginx:1-alpine` | - | Up 4 weeks |
| docker-lemmy-ui-1 | `dessalines/lemmy-ui:0.19.14` | - | Up 4 weeks (healthy) |
| docker-lemmy-1 | `docker-lemmy` | - | Up 4 weeks |
| docker-postgres-1 | `pgautoupgrade/pgautoupgrade:16-alpine` | - | Up 4 weeks (healthy) |
| docker-pictrs-1 | `asonix/pictrs:0.5.16` | - | Up 4 weeks |

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
| Load Average | 0.04, 0.04, 0.00 |

**Memory:** 3.0 GB / 5.8 GB (51.7% used)

### Disk Usage

| Mount | Size | Used | Available | % |
|-------|------|------|-----------|---|
| `/` | 117.0 GB | 13.5 GB | 98.6 GB | 13% |

### PM2 Services

| Name | Port | Status | Memory | CPU | Restarts |
|------|------|--------|--------|-----|----------|
| stream-probe | - | unknown | 0 MB | 0% | 0 |

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
| 33361 | chrome | - | 127.0.0.1 |
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

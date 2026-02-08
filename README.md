# NiteRide.FM Infrastructure

Automated infrastructure discovery and documentation for NiteRide.FM.

## Overview

This repository contains:
- **Daily discovery snapshots** of all NiteRide servers
- **Auto-generated architecture diagrams**
- **Infrastructure documentation** that stays current
- **Historical data** for tracking drift over time

## Servers

| Server | IP | Purpose |
|--------|-----|---------|
| Web | 194.247.183.37 | Orchestration, Auth, V9 Microservices, Nginx |
| Stream | 194.247.182.249 | HLS streaming, Redis, Admin backend |
| Grid | 82.22.53.68 | Lemmy fork, PostgreSQL, Pictrs |
| Monitoring | 194.247.182.159 | Grafana, Loki |

## Structure

```
niteridefm-infra/
├── discovery/           # Latest discovery snapshots (JSON)
├── history/             # Daily historical snapshots
│   └── YYYY-MM-DD/
├── diagrams/            # Auto-generated architecture diagrams
├── scripts/             # Discovery and generation scripts
└── ARCHITECTURE.md      # Human-readable infrastructure docs
```

## How It Works

1. **Daily at 6 AM UTC**, GitHub Actions runs the discovery workflow
2. SSHes into each server and collects:
   - Running processes (PM2, Docker, systemd)
   - Listening ports
   - Nginx configuration
   - System metrics (disk, memory, uptime)
3. Stores JSON snapshots in `discovery/` and `history/`
4. Regenerates architecture diagram and documentation
5. Commits changes (if any) - git history shows infrastructure drift

## Manual Trigger

Go to Actions > Daily Infrastructure Discovery > Run workflow

## Local Development

```bash
# Test discovery on a single server
./scripts/discover.sh web

# Generate diagrams locally
pip install diagrams
python scripts/generate-diagram.py
```

## Adding a New Server

1. Add entry to `servers.yaml`
2. Add SSH key as GitHub secret
3. Update `scripts/discover.sh` with new server

#!/usr/bin/env python3
"""
generate-docs.py
Generates ARCHITECTURE.md from discovery data
"""

import json
from datetime import datetime
from pathlib import Path

REPO_DIR = Path(__file__).parent.parent
DISCOVERY_DIR = REPO_DIR / "discovery"


def load_discovery(server_name: str) -> dict | None:
    """Load discovery JSON for a server"""
    path = DISCOVERY_DIR / f"{server_name}-server.json"
    if path.exists():
        try:
            with open(path) as f:
                return json.load(f)
        except json.JSONDecodeError:
            print(f"Warning: Invalid JSON in {path}")
    return None


def format_bytes(b: int) -> str:
    """Format bytes as human-readable"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if abs(b) < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"


def generate_server_section(name: str, display_name: str, ip: str, purpose: str) -> str:
    """Generate markdown section for a server"""
    data = load_discovery(name)

    md = f"## {display_name}\n\n"
    md += f"**IP:** `{ip}`  \n"
    md += f"**Purpose:** {purpose}\n\n"

    if not data:
        md += "*No discovery data available*\n\n"
        return md

    # System info
    system = data.get("system", {})
    md += "### System\n\n"
    md += f"| Property | Value |\n"
    md += f"|----------|-------|\n"
    md += f"| Hostname | `{system.get('hostname', 'N/A')}` |\n"
    md += f"| OS | {system.get('os', 'N/A')} |\n"
    md += f"| Kernel | {system.get('kernel', 'N/A')} |\n"
    md += f"| Load Average | {system.get('load_average', 'N/A')} |\n"
    md += "\n"

    # Memory
    memory = data.get("memory", {})
    if memory:
        total = memory.get("total_bytes", 0)
        used = memory.get("used_bytes", 0)
        pct = (used / total * 100) if total > 0 else 0
        md += f"**Memory:** {format_bytes(used)} / {format_bytes(total)} ({pct:.1f}% used)\n\n"

    # Disk
    disks = data.get("disk", [])
    if disks:
        md += "### Disk Usage\n\n"
        md += "| Mount | Size | Used | Available | % |\n"
        md += "|-------|------|------|-----------|---|\n"
        for disk in disks:
            if disk.get("mount_point") in ["/", "/opt", "/var", "/home"]:
                md += f"| `{disk.get('mount_point')}` | {format_bytes(disk.get('size_bytes', 0))} | {format_bytes(disk.get('used_bytes', 0))} | {format_bytes(disk.get('available_bytes', 0))} | {disk.get('percent_used', 0)}% |\n"
        md += "\n"

    # PM2 Services (with port info)
    pm2 = data.get("pm2", [])
    if pm2 and isinstance(pm2, list) and len(pm2) > 0:
        md += "### PM2 Services\n\n"
        md += "| Name | Port | Status | Memory | CPU | Restarts |\n"
        md += "|------|------|--------|--------|-----|----------|\n"
        for svc in pm2:
            if isinstance(svc, dict):
                name_val = svc.get("name", "unknown")
                port = svc.get("port", "-")
                status = svc.get("status", "unknown")
                memory_mb = svc.get("memory", 0) / 1024 / 1024 if svc.get("memory") else 0
                cpu = svc.get("cpu", 0)
                restarts = svc.get("restarts", 0)
                md += f"| {name_val} | {port} | {status} | {memory_mb:.0f} MB | {cpu}% | {restarts} |\n"
        md += "\n"

    # Docker Containers
    containers = data.get("docker_containers", [])
    if containers and isinstance(containers, list) and len(containers) > 0:
        md += "### Docker Containers\n\n"
        md += "| Name | Image | Ports | Status |\n"
        md += "|------|-------|-------|--------|\n"
        for c in containers:
            if isinstance(c, dict):
                # Format port mappings
                port_mappings = c.get("port_mappings", [])
                if port_mappings:
                    ports_str = ", ".join([f"{p.get('host')}:{p.get('container')}" for p in port_mappings])
                else:
                    ports_str = c.get("ports_raw", "-") or "-"
                md += f"| {c.get('name', 'unknown')} | `{c.get('image', 'unknown')}` | {ports_str} | {c.get('status', 'unknown')} |\n"
        md += "\n"

    # Listening Ports
    ports = data.get("ports", [])
    if ports and isinstance(ports, list):
        md += "### Listening Ports\n\n"
        md += "| Port | Process | PM2 App | Address |\n"
        md += "|------|---------|---------|----------|\n"
        for p in sorted(ports, key=lambda x: x.get("port", 0)):
            if isinstance(p, dict):
                port = p.get("port", "?")
                proc = p.get("process", "unknown")
                pm2_app = p.get("pm2_app", "-")
                addr = p.get("address", "*")
                if addr in ["*", "0.0.0.0", "::"]:
                    addr = "all interfaces"
                md += f"| {port} | {proc} | {pm2_app} | {addr} |\n"
        md += "\n"

    # Systemd Services (top 10)
    systemd = data.get("systemd", [])
    if systemd and isinstance(systemd, list) and len(systemd) > 0:
        md += "### Key Systemd Services\n\n"
        important_services = [s for s in systemd if isinstance(s, dict) and any(
            kw in s.get("unit", "").lower()
            for kw in ["nginx", "docker", "redis", "postgres", "grafana", "loki", "node", "pm2"]
        )]
        if important_services:
            md += "| Service | Status |\n"
            md += "|---------|--------|\n"
            for svc in important_services[:10]:
                md += f"| {svc.get('unit', 'unknown')} | {svc.get('active', '?')}/{svc.get('sub', '?')} |\n"
            md += "\n"

    # Nginx
    nginx = data.get("nginx", {})
    if nginx.get("installed"):
        md += f"### Nginx\n\n"
        md += f"**Version:** {nginx.get('version', 'unknown')}\n\n"

        # Nginx routes (proxy_pass)
        proxy_dests = nginx.get("proxy_destinations", [])
        if proxy_dests:
            md += "**Proxy Routes:**\n"
            for dest in proxy_dests[:10]:
                md += f"- `{dest}`\n"
            if len(proxy_dests) > 10:
                md += f"- *...and {len(proxy_dests) - 10} more*\n"
            md += "\n"

    # Connections (service relationships)
    connections = data.get("connections", [])
    if connections and isinstance(connections, list) and len(connections) > 0:
        md += "### Service Connections\n\n"
        md += "| From | To | Port | Type |\n"
        md += "|------|-----|------|------|\n"
        for conn in connections:
            if isinstance(conn, dict):
                md += f"| {conn.get('from', '?')} | {conn.get('to', '?')} | {conn.get('port', '?')} | {conn.get('type', '?')} |\n"
        md += "\n"

    # External Services
    external = data.get("external_services", [])
    if external and isinstance(external, list) and len(external) > 0:
        md += "### External Services\n\n"
        md += "| Service | Type | Detected In |\n"
        md += "|---------|------|-------------|\n"
        for svc in external:
            if isinstance(svc, dict):
                md += f"| {svc.get('name', '?')} | {svc.get('type', '?')} | {svc.get('detected_in', '?')} |\n"
        md += "\n"

    md += "---\n\n"
    return md


def generate_architecture_md():
    """Generate the full ARCHITECTURE.md file"""
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    md = "# NiteRide.FM Infrastructure Architecture\n\n"
    md += f"*Auto-generated on {now}*\n\n"
    md += "![Architecture Diagram](diagrams/architecture.png)\n\n"
    md += "---\n\n"

    # Server sections
    servers = [
        ("web", "Web Server", "194.247.183.37",
         "Orchestration, Auth, V9 Microservices (Identity, Public, Guide), Nginx proxy"),
        ("stream", "Stream Server", "194.247.182.249",
         "HLS streaming, Redis state, Admin backend (Library, Scheduling, Commercials)"),
        ("grid", "Grid Server", "82.22.53.68",
         "Lemmy fork with Supabase auth, PostgreSQL 16, Pictrs image hosting"),
        ("monitoring", "Monitoring Server", "194.247.182.159",
         "Grafana dashboards, Loki log aggregation"),
        ("fe-ppe", "FE PPE Server", "82.22.53.147",
         "Pre-production frontend environment (staging branch)"),
        ("be-ppe", "BE PPE Server", "82.22.53.161",
         "Pre-production backend environment (staging branch)"),
        ("fe-ch2", "FE CH2 Server", "82.22.53.167",
         "Channel 2 frontend environment"),
    ]

    for name, display, ip, purpose in servers:
        md += generate_server_section(name, display, ip, purpose)

    # Footer
    md += "## Data Sources\n\n"
    md += "This documentation is automatically generated from live infrastructure discovery.\n"
    md += "Discovery runs daily at 6 AM UTC via GitHub Actions.\n\n"
    md += "See `discovery/` for raw JSON data and `history/` for historical snapshots.\n"

    # Write file
    output_path = REPO_DIR / "ARCHITECTURE.md"
    with open(output_path, "w") as f:
        f.write(md)

    print(f"Generated: {output_path}")


if __name__ == "__main__":
    print("Generating ARCHITECTURE.md...")
    generate_architecture_md()
    print("Done!")

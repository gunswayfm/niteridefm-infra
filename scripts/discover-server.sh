#!/bin/bash
# discover-server.sh
# Run on target server via SSH to collect infrastructure information
# Outputs JSON to stdout

set -e

# Use python for reliable JSON output
python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import os
import re
from datetime import datetime

def run_cmd(cmd, default=""):
    """Run a command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.stdout.strip()
    except:
        return default

def get_system_info():
    """Get system information"""
    return {
        "hostname": run_cmd("hostname"),
        "kernel": run_cmd("uname -r"),
        "os": run_cmd("grep '^PRETTY_NAME=' /etc/os-release | cut -d'\"' -f2"),
        "arch": run_cmd("uname -m"),
        "uptime": run_cmd("uptime"),
        "load_average": run_cmd("cat /proc/loadavg | awk '{print $1\", \"$2\", \"$3}'")
    }

def get_memory_info():
    """Get memory information"""
    try:
        output = run_cmd("free -b | grep '^Mem:'")
        parts = output.split()
        return {
            "total_bytes": int(parts[1]) if len(parts) > 1 else 0,
            "used_bytes": int(parts[2]) if len(parts) > 2 else 0,
            "free_bytes": int(parts[3]) if len(parts) > 3 else 0,
            "available_bytes": int(parts[6]) if len(parts) > 6 else 0
        }
    except:
        return {"total_bytes": 0, "used_bytes": 0, "free_bytes": 0, "available_bytes": 0}

def get_disk_info():
    """Get disk usage information"""
    disks = []
    try:
        output = run_cmd("df -B1 --output=source,fstype,size,used,avail,pcent,target | tail -n +2 | grep -v '^tmpfs\\|^devtmpfs\\|^udev'")
        for line in output.split('\n'):
            if not line.strip():
                continue
            parts = line.split()
            if len(parts) >= 7:
                disks.append({
                    "source": parts[0],
                    "fstype": parts[1],
                    "size_bytes": int(parts[2]),
                    "used_bytes": int(parts[3]),
                    "available_bytes": int(parts[4]),
                    "percent_used": int(parts[5].rstrip('%')),
                    "mount_point": parts[6]
                })
    except:
        pass
    return disks

def get_ports_info():
    """Get listening ports with enhanced process detection"""
    ports = []
    pid_to_pm2 = {}

    # Build PID to PM2 app mapping
    try:
        pm2_output = run_cmd("pm2 jlist 2>/dev/null")
        if pm2_output:
            pm2_apps = json.loads(pm2_output)
            for app in pm2_apps:
                if isinstance(app, dict):
                    pid = app.get("pid", 0)
                    name = app.get("name", "unknown")
                    if pid:
                        pid_to_pm2[pid] = name
    except:
        pass

    try:
        output = run_cmd("ss -tlnp | tail -n +2")
        for line in output.split('\n'):
            if not line.strip():
                continue
            parts = line.split()
            if len(parts) >= 5:
                local_addr = parts[3]
                # Extract port from address (handle IPv4 and IPv6)
                if ']:' in local_addr:
                    port = local_addr.split(']:')[-1]
                    addr = local_addr.rsplit(':', 1)[0]
                else:
                    port = local_addr.rsplit(':', 1)[-1]
                    addr = local_addr.rsplit(':', 1)[0] if ':' in local_addr else '*'

                # Extract process name and PID
                process = "unknown"
                pid = 0
                pm2_app = None

                if len(parts) >= 6:
                    proc_info = parts[5] if len(parts) > 5 else ""
                    match = re.search(r'users:\(\("([^"]+)"', proc_info)
                    if match:
                        process = match.group(1)
                    pid_match = re.search(r'pid=(\d+)', proc_info)
                    if pid_match:
                        pid = int(pid_match.group(1))
                        # Check if this PID belongs to a PM2 app
                        if pid in pid_to_pm2:
                            pm2_app = pid_to_pm2[pid]
                        else:
                            # Check parent PID for PM2
                            try:
                                ppid = int(run_cmd(f"ps -o ppid= -p {pid} 2>/dev/null").strip())
                                if ppid in pid_to_pm2:
                                    pm2_app = pid_to_pm2[ppid]
                            except:
                                pass

                try:
                    port_entry = {
                        "port": int(port),
                        "address": addr,
                        "process": process,
                        "pid": pid
                    }
                    if pm2_app:
                        port_entry["pm2_app"] = pm2_app
                    ports.append(port_entry)
                except ValueError:
                    pass
    except:
        pass
    return ports

def get_pm2_info():
    """Get PM2 processes with port detection"""
    apps = []
    try:
        output = run_cmd("pm2 jlist 2>/dev/null")
        if output:
            pm2_apps = json.loads(output)
            for app in pm2_apps:
                if isinstance(app, dict):
                    pid = app.get("pid", 0)
                    name = app.get("name", "unknown")

                    # Try to find what port this app is listening on
                    port = None
                    if pid:
                        port_output = run_cmd(f"ss -tlnp | grep 'pid={pid}' | head -1")
                        if port_output:
                            match = re.search(r':(\d+)\s', port_output)
                            if match:
                                port = int(match.group(1))

                    app_info = {
                        "name": name,
                        "pid": pid,
                        "status": app.get("pm2_env", {}).get("status", "unknown") if isinstance(app.get("pm2_env"), dict) else "unknown",
                        "memory": app.get("monit", {}).get("memory", 0) if isinstance(app.get("monit"), dict) else 0,
                        "cpu": app.get("monit", {}).get("cpu", 0) if isinstance(app.get("monit"), dict) else 0,
                        "restarts": app.get("pm2_env", {}).get("restart_time", 0) if isinstance(app.get("pm2_env"), dict) else 0,
                    }
                    if port:
                        app_info["port"] = port

                    # Try to get port from env or script args
                    pm2_env = app.get("pm2_env", {})
                    if isinstance(pm2_env, dict):
                        env_port = pm2_env.get("PORT") or pm2_env.get("env", {}).get("PORT")
                        if env_port and not port:
                            try:
                                app_info["port"] = int(env_port)
                            except:
                                pass

                    apps.append(app_info)
    except:
        pass
    return apps

def get_docker_info():
    """Get Docker containers"""
    containers = []
    try:
        output = run_cmd("docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' 2>/dev/null")
        for line in output.split('\n'):
            if not line.strip():
                continue
            parts = line.split('|')
            if len(parts) >= 4:
                # Parse ports to extract host:container mappings
                ports_str = parts[4] if len(parts) > 4 else ""
                port_mappings = []
                if ports_str:
                    for port_part in ports_str.split(', '):
                        match = re.search(r'(\d+)->(\d+)', port_part)
                        if match:
                            port_mappings.append({
                                "host": int(match.group(1)),
                                "container": int(match.group(2))
                            })

                containers.append({
                    "id": parts[0],
                    "name": parts[1],
                    "image": parts[2],
                    "status": parts[3],
                    "ports_raw": ports_str,
                    "port_mappings": port_mappings
                })
    except:
        pass
    return containers

def get_docker_compose_info():
    """Get Docker Compose projects"""
    try:
        output = run_cmd("docker compose ls --format json 2>/dev/null")
        if output:
            return json.loads(output)
    except:
        pass
    return []

def get_systemd_info():
    """Get running systemd services"""
    services = []
    try:
        output = run_cmd("systemctl list-units --type=service --state=running --no-pager --plain | grep '\\.service'")
        for line in output.split('\n'):
            if not line.strip():
                continue
            parts = line.split()
            if len(parts) >= 4:
                services.append({
                    "unit": parts[0],
                    "load": parts[1],
                    "active": parts[2],
                    "sub": parts[3]
                })
    except:
        pass
    return services

def get_nginx_info():
    """Get Nginx information with parsed routes"""
    try:
        version = run_cmd("nginx -v 2>&1 | cut -d'/' -f2")
        if not version:
            return {"installed": False}

        # Get full config
        config = run_cmd("nginx -T 2>/dev/null")

        # Parse server blocks and proxy_pass directives
        server_blocks = []
        current_server = None
        current_location = None

        for line in config.split('\n'):
            line = line.strip()

            # Detect server block start
            if line.startswith('server {') or line == 'server {':
                current_server = {"listen": [], "server_name": [], "locations": []}
            elif current_server is not None:
                if line.startswith('listen '):
                    listen = line.replace('listen ', '').rstrip(';').strip()
                    current_server["listen"].append(listen)
                elif line.startswith('server_name '):
                    names = line.replace('server_name ', '').rstrip(';').strip()
                    current_server["server_name"] = names.split()
                elif line.startswith('location '):
                    path = line.replace('location ', '').rstrip(' {').strip()
                    current_location = {"path": path, "proxy_pass": None, "type": "static"}
                elif current_location is not None:
                    if line.startswith('proxy_pass '):
                        proxy = line.replace('proxy_pass ', '').rstrip(';').strip()
                        current_location["proxy_pass"] = proxy
                        current_location["type"] = "proxy"
                    elif line == '}':
                        current_server["locations"].append(current_location)
                        current_location = None
                elif line == '}' and current_location is None:
                    if current_server.get("server_name") or current_server.get("listen"):
                        server_blocks.append(current_server)
                    current_server = None

        # Extract unique proxy destinations
        proxy_destinations = set()
        for server in server_blocks:
            for loc in server.get("locations", []):
                if loc.get("proxy_pass"):
                    proxy_destinations.add(loc["proxy_pass"])

        return {
            "installed": True,
            "version": version,
            "server_blocks": server_blocks[:20],  # Limit to first 20
            "proxy_destinations": list(proxy_destinations),
            "config_preview": config[:3000] if config else ""
        }
    except:
        pass
    return {"installed": False}

def get_cron_info():
    """Get cron information"""
    try:
        user_crontab = run_cmd("crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$'")
        system_cron = run_cmd("ls /etc/cron.d/ 2>/dev/null").split()
        return {
            "user_crontab": user_crontab,
            "system_cron_files": system_cron
        }
    except:
        return {"user_crontab": "", "system_cron_files": []}

def get_env_info():
    """Get safe environment variables"""
    env_file = "/opt/niteride/.env"
    result = {"env_file": None, "variables": {}}

    if os.path.exists(env_file):
        result["env_file"] = env_file
        try:
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if '=' in line:
                        key, _, value = line.partition('=')
                        # Skip sensitive values
                        if any(s in key.upper() for s in ['PASSWORD', 'SECRET', 'KEY', 'TOKEN', 'CREDENTIAL', 'PRIVATE']):
                            result["variables"][key] = "[REDACTED]"
                        else:
                            result["variables"][key] = value
        except:
            pass

    return result

def get_connections_info(ports, pm2_apps, docker_containers, nginx_info):
    """Infer service connections from discovered data"""
    connections = []

    # Find Redis connections
    redis_port = None
    for p in ports:
        if p.get("port") == 6379:
            redis_port = 6379
            break

    if redis_port:
        for app in pm2_apps:
            # Assume streaming/state apps connect to Redis
            if any(kw in app.get("name", "").lower() for kw in ["stream", "state", "cache", "session", "core"]):
                connections.append({
                    "from": app.get("name"),
                    "to": "redis",
                    "port": 6379,
                    "type": "data"
                })

    # Find Postgres connections
    for p in ports:
        if p.get("port") == 5432 or p.get("port") == 5433:
            for app in pm2_apps:
                if any(kw in app.get("name", "").lower() for kw in ["admin", "storage", "backend", "service"]):
                    connections.append({
                        "from": app.get("name"),
                        "to": "postgres",
                        "port": p.get("port"),
                        "type": "data"
                    })

    # Parse nginx proxy connections
    if nginx_info.get("installed"):
        for dest in nginx_info.get("proxy_destinations", []):
            match = re.search(r'http[s]?://([^:/]+):?(\d+)?', dest)
            if match:
                host = match.group(1)
                port = int(match.group(2)) if match.group(2) else 80
                connections.append({
                    "from": "nginx",
                    "to": dest,
                    "port": port,
                    "type": "proxy"
                })

    return connections

def get_external_services():
    """Detect external service connections from env and config"""
    external = []

    # Check for Supabase
    env_output = run_cmd("grep -i supabase /opt/niteride/.env 2>/dev/null || true")
    if "supabase" in env_output.lower():
        external.append({
            "name": "Supabase",
            "type": "auth/database",
            "detected_in": ".env"
        })

    # Check for CDN references
    env_output = run_cmd("grep -iE 'cdn|cloudflare|cloudfront' /opt/niteride/.env 2>/dev/null || true")
    if env_output:
        external.append({
            "name": "CDN",
            "type": "content_delivery",
            "detected_in": ".env"
        })

    # Check for Stripe
    env_output = run_cmd("grep -i stripe /opt/niteride/.env 2>/dev/null || true")
    if "stripe" in env_output.lower():
        external.append({
            "name": "Stripe",
            "type": "payments",
            "detected_in": ".env"
        })

    # Check for email services
    env_output = run_cmd("grep -iE 'smtp|sendgrid|mailgun|ses' /opt/niteride/.env 2>/dev/null || true")
    if env_output:
        external.append({
            "name": "Email Service",
            "type": "email",
            "detected_in": ".env"
        })

    # Check for S3/storage
    env_output = run_cmd("grep -iE 's3|minio|storage.*bucket' /opt/niteride/.env 2>/dev/null || true")
    if env_output:
        external.append({
            "name": "Object Storage",
            "type": "storage",
            "detected_in": ".env"
        })

    return external

# Collect all data
ports = get_ports_info()
pm2_apps = get_pm2_info()
docker_containers = get_docker_info()
nginx_info = get_nginx_info()

# Build output
output = {
    "timestamp": datetime.now().isoformat(),
    "system": get_system_info(),
    "memory": get_memory_info(),
    "disk": get_disk_info(),
    "ports": ports,
    "pm2": pm2_apps,
    "docker_containers": docker_containers,
    "docker_compose": get_docker_compose_info(),
    "systemd": get_systemd_info(),
    "nginx": nginx_info,
    "cron": get_cron_info(),
    "env": get_env_info(),
    "connections": get_connections_info(ports, pm2_apps, docker_containers, nginx_info),
    "external_services": get_external_services()
}

print(json.dumps(output, indent=2))
PYTHON_SCRIPT

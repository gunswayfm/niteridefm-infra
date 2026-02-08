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
    """Get listening ports"""
    ports = []
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

                # Extract process name
                process = "unknown"
                pid = 0
                if len(parts) >= 6:
                    proc_info = parts[5] if len(parts) > 5 else ""
                    match = re.search(r'users:\(\("([^"]+)"', proc_info)
                    if match:
                        process = match.group(1)
                    pid_match = re.search(r'pid=(\d+)', proc_info)
                    if pid_match:
                        pid = int(pid_match.group(1))

                try:
                    ports.append({
                        "port": int(port),
                        "address": addr,
                        "process": process,
                        "pid": pid
                    })
                except ValueError:
                    pass
    except:
        pass
    return ports

def get_pm2_info():
    """Get PM2 processes"""
    try:
        output = run_cmd("pm2 jlist 2>/dev/null")
        if output:
            return json.loads(output)
    except:
        pass
    return []

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
                containers.append({
                    "id": parts[0],
                    "name": parts[1],
                    "image": parts[2],
                    "status": parts[3],
                    "ports": parts[4] if len(parts) > 4 else ""
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
    """Get Nginx information"""
    try:
        version = run_cmd("nginx -v 2>&1 | cut -d'/' -f2")
        if version:
            # Get first 200 lines of config
            config = run_cmd("nginx -T 2>/dev/null | head -200")
            return {
                "installed": True,
                "version": version,
                "config_preview": config[:5000] if config else ""
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
                        if any(s in key.upper() for s in ['PASSWORD', 'SECRET', 'KEY', 'TOKEN', 'CREDENTIAL']):
                            continue
                        result["variables"][key] = value
        except:
            pass

    return result

# Build output
output = {
    "timestamp": datetime.now().isoformat(),
    "system": get_system_info(),
    "memory": get_memory_info(),
    "disk": get_disk_info(),
    "ports": get_ports_info(),
    "pm2": get_pm2_info(),
    "docker_containers": get_docker_info(),
    "docker_compose": get_docker_compose_info(),
    "systemd": get_systemd_info(),
    "nginx": get_nginx_info(),
    "cron": get_cron_info(),
    "env": get_env_info()
}

print(json.dumps(output, indent=2))
PYTHON_SCRIPT

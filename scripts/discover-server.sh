#!/bin/bash
# discover-server.sh
# Run on target server via SSH to collect infrastructure information
# Outputs JSON to stdout

set -e

# Helper to escape JSON strings
json_escape() {
    python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

# System information
get_system_info() {
    local hostname=$(hostname)
    local kernel=$(uname -r)
    local os=$(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME=" | cut -d'"' -f2 || echo "Unknown")
    local arch=$(uname -m)
    local uptime_raw=$(uptime)
    local load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1", "$2", "$3}' || echo "N/A")

    cat <<EOF
{
    "hostname": "$hostname",
    "kernel": "$kernel",
    "os": "$os",
    "arch": "$arch",
    "uptime": $(echo "$uptime_raw" | json_escape),
    "load_average": "$load"
}
EOF
}

# Memory information
get_memory_info() {
    local mem_total=$(free -b | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -b | awk '/^Mem:/ {print $3}')
    local mem_free=$(free -b | awk '/^Mem:/ {print $4}')
    local mem_available=$(free -b | awk '/^Mem:/ {print $7}')

    cat <<EOF
{
    "total_bytes": $mem_total,
    "used_bytes": $mem_used,
    "free_bytes": $mem_free,
    "available_bytes": ${mem_available:-0}
}
EOF
}

# Disk information
get_disk_info() {
    echo "["
    local first=true
    df -B1 --output=source,fstype,size,used,avail,pcent,target 2>/dev/null | tail -n +2 | grep -v "^tmpfs\|^devtmpfs\|^udev" | while read source fstype size used avail pcent target; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        pcent_num=$(echo "$pcent" | tr -d '%')
        cat <<EOF
    {
        "source": "$source",
        "fstype": "$fstype",
        "size_bytes": $size,
        "used_bytes": $used,
        "available_bytes": $avail,
        "percent_used": $pcent_num,
        "mount_point": "$target"
    }
EOF
    done
    echo "]"
}

# Listening ports
get_ports_info() {
    echo "["
    local first=true
    ss -tlnp 2>/dev/null | tail -n +2 | while read state recv send local_addr peer_addr process; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        local port=$(echo "$local_addr" | rev | cut -d':' -f1 | rev)
        local addr=$(echo "$local_addr" | rev | cut -d':' -f2- | rev)
        local proc_name=$(echo "$process" | grep -oP 'users:\(\("\K[^"]+' || echo "unknown")
        local pid=$(echo "$process" | grep -oP 'pid=\K[0-9]+' || echo "0")

        cat <<EOF
    {
        "port": $port,
        "address": "$addr",
        "process": "$proc_name",
        "pid": $pid
    }
EOF
    done
    echo "]"
}

# PM2 processes (if available)
get_pm2_info() {
    if command -v pm2 &> /dev/null; then
        pm2 jlist 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

# Docker containers (if available)
get_docker_info() {
    if command -v docker &> /dev/null; then
        docker ps --format '{"id":"{{.ID}}","name":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}","ports":"{{.Ports}}"}' 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

# Docker Compose projects (if available)
get_docker_compose_info() {
    if command -v docker &> /dev/null; then
        docker compose ls --format json 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

# Systemd services
get_systemd_info() {
    echo "["
    local first=true
    systemctl list-units --type=service --state=running --no-pager --plain 2>/dev/null | grep '\.service' | while read unit load active sub description; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        cat <<EOF
    {
        "unit": "$unit",
        "load": "$load",
        "active": "$active",
        "sub": "$sub"
    }
EOF
    done
    echo "]"
}

# Nginx configuration (if available)
get_nginx_info() {
    if command -v nginx &> /dev/null; then
        local version=$(nginx -v 2>&1 | cut -d'/' -f2)
        local config=$(nginx -T 2>/dev/null | head -500 | json_escape)

        cat <<EOF
{
    "installed": true,
    "version": "$version",
    "config_preview": $config
}
EOF
    else
        echo '{"installed": false}'
    fi
}

# Cron jobs
get_cron_info() {
    echo "{"
    echo '  "user_crontab": '
    crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | json_escape
    echo ','
    echo '  "system_cron_files": ['
    local first=true
    for f in /etc/cron.d/*; do
        if [ -f "$f" ]; then
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            echo "    \"$(basename "$f")\""
        fi
    done
    echo "  ]"
    echo "}"
}

# Environment variables (safe ones only - no secrets)
get_env_info() {
    local env_file="/opt/niteride/.env"
    if [ -f "$env_file" ]; then
        echo "{"
        echo '  "env_file": "'$env_file'",'
        echo '  "variables": {'
        local first=true
        grep -v '^#' "$env_file" 2>/dev/null | grep -v '^$' | grep -viE 'password|secret|key|token|credential' | while IFS='=' read -r key value; do
            if [ -n "$key" ]; then
                if [ "$first" = true ]; then
                    first=false
                else
                    echo ","
                fi
                echo "    \"$key\": $(echo "$value" | json_escape)"
            fi
        done
        echo "  }"
        echo "}"
    else
        echo '{"env_file": null, "variables": {}}'
    fi
}

# Main output
main() {
    cat <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "system": $(get_system_info),
    "memory": $(get_memory_info),
    "disk": $(get_disk_info),
    "ports": $(get_ports_info),
    "pm2": $(get_pm2_info),
    "docker_containers": $(get_docker_info),
    "docker_compose": $(get_docker_compose_info),
    "systemd": $(get_systemd_info),
    "nginx": $(get_nginx_info),
    "cron": $(get_cron_info),
    "env": $(get_env_info)
}
EOF
}

main

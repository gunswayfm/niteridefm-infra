#!/bin/bash
# discover.sh
# Main orchestrator - SSHes into each server and runs discovery
# Can run locally (with key paths) or in GitHub Actions (with secrets)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DATE=$(date +%Y-%m-%d)

# Server configuration
declare -A SERVERS
SERVERS[web]="194.247.183.37"
SERVERS[stream]="194.247.182.249"
SERVERS[grid]="82.22.53.68"
SERVERS[monitoring]="194.247.182.159"

# SSH key paths (for local runs)
# In GitHub Actions, these are set via environment variables
declare -A SSH_KEYS_LOCAL
SSH_KEYS_LOCAL[web]="$HOME/repos/niteridefm/myKeys/niteride_web_node"
SSH_KEYS_LOCAL[stream]="$HOME/repos/niteridefm/myKeys/hostkey_iceland"
SSH_KEYS_LOCAL[grid]="$HOME/repos/niteridefm/myKeys/niteride_grid_node"
SSH_KEYS_LOCAL[monitoring]="$HOME/Documents/myKeys/hostkey_iceland_loki"

# Create directories
mkdir -p "$REPO_DIR/discovery"
mkdir -p "$REPO_DIR/history/$DATE"

# Function to get SSH key path
get_ssh_key() {
    local server=$1

    # Check for GitHub Actions environment variables first
    case $server in
        web)
            if [ -n "$WEB_SERVER_SSH_KEY_PATH" ]; then
                echo "$WEB_SERVER_SSH_KEY_PATH"
                return
            fi
            ;;
        stream)
            if [ -n "$STREAM_SERVER_SSH_KEY_PATH" ]; then
                echo "$STREAM_SERVER_SSH_KEY_PATH"
                return
            fi
            ;;
        grid)
            if [ -n "$GRID_SERVER_SSH_KEY_PATH" ]; then
                echo "$GRID_SERVER_SSH_KEY_PATH"
                return
            fi
            ;;
        monitoring)
            if [ -n "$MONITORING_SERVER_SSH_KEY_PATH" ]; then
                echo "$MONITORING_SERVER_SSH_KEY_PATH"
                return
            fi
            ;;
    esac

    # Fall back to local key paths
    echo "${SSH_KEYS_LOCAL[$server]}"
}

# Function to discover a single server
discover_server() {
    local server=$1
    local host=${SERVERS[$server]}
    local key_path=$(get_ssh_key "$server")

    echo "Discovering $server ($host)..."

    if [ ! -f "$key_path" ]; then
        echo "  ERROR: SSH key not found at $key_path"
        return 1
    fi

    # Run discovery script on remote server
    ssh -i "$key_path" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 \
        -o LogLevel=ERROR \
        "root@$host" \
        'bash -s' < "$SCRIPT_DIR/discover-server.sh" > "$REPO_DIR/discovery/${server}-server.json" 2>/dev/null

    if [ $? -eq 0 ]; then
        # Validate JSON
        if python3 -c "import json; json.load(open('$REPO_DIR/discovery/${server}-server.json'))" 2>/dev/null; then
            echo "  OK: Valid JSON received"
            # Copy to history
            cp "$REPO_DIR/discovery/${server}-server.json" "$REPO_DIR/history/$DATE/${server}-server.json"
        else
            echo "  WARNING: Invalid JSON received, keeping raw output"
        fi
    else
        echo "  ERROR: SSH connection failed"
        return 1
    fi
}

# Main
main() {
    local target=${1:-all}

    echo "=== NiteRide Infrastructure Discovery ==="
    echo "Date: $DATE"
    echo ""

    if [ "$target" = "all" ]; then
        for server in "${!SERVERS[@]}"; do
            discover_server "$server" || echo "  Failed to discover $server"
            echo ""
        done
    else
        if [ -n "${SERVERS[$target]}" ]; then
            discover_server "$target"
        else
            echo "Unknown server: $target"
            echo "Available servers: ${!SERVERS[*]}"
            exit 1
        fi
    fi

    echo "=== Discovery Complete ==="
    echo "Results saved to: $REPO_DIR/discovery/"
    echo "History saved to: $REPO_DIR/history/$DATE/"
}

main "$@"

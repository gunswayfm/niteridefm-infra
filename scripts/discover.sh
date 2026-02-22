#!/bin/bash
# discover.sh
# Main orchestrator - SSHes into each server and runs discovery
# Compatible with bash 3.x (macOS) and 4.x (Linux)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DATE=$(date +%Y-%m-%d)

# Get server IP by name
get_server_ip() {
    case "$1" in
        web) echo "194.247.183.37" ;;
        stream) echo "194.247.182.249" ;;
        grid) echo "82.22.53.68" ;;
        monitoring) echo "194.247.182.159" ;;
        fe-ppe) echo "82.22.53.147" ;;
        be-ppe) echo "82.22.53.161" ;;
        fe-ch2) echo "82.22.53.167" ;;
        *) echo "" ;;
    esac
}

# Expand tilde in path
expand_path() {
    local path="$1"
    # Replace ~ with $HOME
    echo "${path/#\~/$HOME}"
}

# Get SSH key path by server name
get_ssh_key() {
    local server=$1
    local path=""

    # Check for GitHub Actions environment variables first
    case "$server" in
        web)
            if [ -n "$WEB_SERVER_SSH_KEY_PATH" ]; then
                path="$WEB_SERVER_SSH_KEY_PATH"
            else
                path="$HOME/repos/niteridefm/myKeys/niteride_web_node"
            fi
            ;;
        stream)
            if [ -n "$STREAM_SERVER_SSH_KEY_PATH" ]; then
                path="$STREAM_SERVER_SSH_KEY_PATH"
            else
                path="$HOME/repos/niteridefm/myKeys/hostkey_iceland"
            fi
            ;;
        grid)
            if [ -n "$GRID_SERVER_SSH_KEY_PATH" ]; then
                path="$GRID_SERVER_SSH_KEY_PATH"
            else
                path="$HOME/repos/niteridefm/myKeys/niteride_grid_node"
            fi
            ;;
        monitoring)
            if [ -n "$MONITORING_SERVER_SSH_KEY_PATH" ]; then
                path="$MONITORING_SERVER_SSH_KEY_PATH"
            else
                path="$HOME/Documents/myKeys/hostkey_iceland_loki"
            fi
            ;;
        fe-ppe)
            if [ -n "$FE_PPE_SERVER_SSH_KEY_PATH" ]; then
                path="$FE_PPE_SERVER_SSH_KEY_PATH"
            else
                path="$HOME/repos/niteridefm/myKeys/niteride-fe-ppe"
            fi
            ;;
        be-ppe)
            if [ -n "$BE_PPE_SERVER_SSH_KEY_PATH" ]; then
                path="$BE_PPE_SERVER_SSH_KEY_PATH"
            else
                path="$HOME/repos/niteridefm/myKeys/niteride-be-ppe"
            fi
            ;;
        fe-ch2)
            if [ -n "$FE_CH2_SERVER_SSH_KEY_PATH" ]; then
                path="$FE_CH2_SERVER_SSH_KEY_PATH"
            else
                path="$HOME/repos/niteridefm/myKeys/niteride-fm-ch2"
            fi
            ;;
    esac

    # Expand tilde if present
    expand_path "$path"
}

# Create directories
mkdir -p "$REPO_DIR/discovery"
mkdir -p "$REPO_DIR/history/$DATE"

# Function to discover a single server
discover_server() {
    local server=$1
    local host=$(get_server_ip "$server")
    local key_path=$(get_ssh_key "$server")

    if [ -z "$host" ]; then
        echo "Unknown server: $server"
        return 1
    fi

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
        for server in web stream grid monitoring fe-ppe be-ppe fe-ch2; do
            discover_server "$server" || echo "  Failed to discover $server"
            echo ""
        done
    else
        discover_server "$target"
    fi

    echo "=== Discovery Complete ==="
    echo "Results saved to: $REPO_DIR/discovery/"
    echo "History saved to: $REPO_DIR/history/$DATE/"
}

main "$@"

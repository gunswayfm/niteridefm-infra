#!/usr/bin/env python3
"""
generate-diagram.py
Generates architecture diagrams from discovery data using mingrammer/diagrams
"""

import json
import os
from pathlib import Path

try:
    from diagrams import Diagram, Cluster, Edge
    from diagrams.onprem.compute import Server
    from diagrams.onprem.database import PostgreSQL
    from diagrams.onprem.inmemory import Redis
    from diagrams.onprem.monitoring import Grafana
    from diagrams.onprem.network import Nginx
    from diagrams.onprem.container import Docker
    from diagrams.onprem.logging import Loki
    from diagrams.programming.language import Rust, Nodejs
    from diagrams.generic.storage import Storage
    DIAGRAMS_AVAILABLE = True
except ImportError:
    DIAGRAMS_AVAILABLE = False
    print("Warning: 'diagrams' package not installed. Run: pip install diagrams")

REPO_DIR = Path(__file__).parent.parent
DISCOVERY_DIR = REPO_DIR / "discovery"
DIAGRAMS_DIR = REPO_DIR / "diagrams"


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


def get_pm2_services(data: dict) -> list[str]:
    """Extract PM2 service names from discovery data"""
    pm2 = data.get("pm2", [])
    if isinstance(pm2, list):
        return [p.get("name", "unknown") for p in pm2 if isinstance(p, dict)]
    return []


def get_docker_containers(data: dict) -> list[str]:
    """Extract Docker container names from discovery data"""
    containers = data.get("docker_containers", [])
    if isinstance(containers, list):
        return [c.get("name", "unknown") for c in containers if isinstance(c, dict)]
    return []


def get_listening_ports(data: dict) -> list[dict]:
    """Extract listening ports from discovery data"""
    return data.get("ports", [])


def generate_architecture_diagram():
    """Generate the main architecture diagram"""
    if not DIAGRAMS_AVAILABLE:
        print("Skipping diagram generation - diagrams package not available")
        return

    DIAGRAMS_DIR.mkdir(exist_ok=True)

    # Load all discovery data
    web_data = load_discovery("web")
    stream_data = load_discovery("stream")
    grid_data = load_discovery("grid")
    monitoring_data = load_discovery("monitoring")

    with Diagram(
        "NiteRide.FM Infrastructure",
        show=False,
        filename=str(DIAGRAMS_DIR / "architecture"),
        outformat="png",
        direction="TB"
    ):
        # Web Server Cluster
        with Cluster("Web Server\n194.247.183.37"):
            nginx_web = Nginx("Nginx\nProxy")

            if web_data:
                pm2_services = get_pm2_services(web_data)
                if pm2_services:
                    node_services = Nodejs(f"V9 Microservices\n({len(pm2_services)} PM2)")
                else:
                    node_services = Nodejs("V9 Microservices")
            else:
                node_services = Nodejs("V9 Microservices")

            nginx_web >> node_services

        # Stream Server Cluster
        with Cluster("Stream Server\n194.247.182.249"):
            if stream_data:
                pm2_services = get_pm2_services(stream_data)
                containers = get_docker_containers(stream_data)
            else:
                pm2_services = []
                containers = []

            hls_server = Server("HLS Streaming")
            redis_cache = Redis("Redis\nState")
            admin_api = Nodejs(f"Admin API\n({len(pm2_services)} PM2)")

            hls_server >> redis_cache
            admin_api >> redis_cache

        # Grid Server Cluster
        with Cluster("Grid Server\n82.22.53.68"):
            if grid_data:
                containers = get_docker_containers(grid_data)
            else:
                containers = []

            lemmy_api = Rust("Lemmy API\n(Actix-web)")
            postgres_db = PostgreSQL("PostgreSQL 16")
            pictrs = Docker("Pictrs\nImages")

            lemmy_api >> postgres_db
            lemmy_api >> pictrs

        # Monitoring Server Cluster
        with Cluster("Monitoring\n194.247.182.159"):
            grafana = Grafana("Grafana\nDashboards")
            loki_logs = Loki("Loki\nLog Aggregation")

            grafana >> loki_logs

        # Cross-cluster connections
        node_services >> Edge(label="API") >> hls_server
        node_services >> Edge(label="Auth") >> lemmy_api

        # Monitoring connections (dashed)
        hls_server >> Edge(style="dashed", label="logs") >> loki_logs
        admin_api >> Edge(style="dashed", label="logs") >> loki_logs
        lemmy_api >> Edge(style="dashed", label="logs") >> loki_logs

    print(f"Generated: {DIAGRAMS_DIR / 'architecture.png'}")


def generate_network_diagram():
    """Generate network/ports diagram"""
    if not DIAGRAMS_AVAILABLE:
        return

    DIAGRAMS_DIR.mkdir(exist_ok=True)

    servers = {
        "web": ("Web Server", "194.247.183.37"),
        "stream": ("Stream Server", "194.247.182.249"),
        "grid": ("Grid Server", "82.22.53.68"),
        "monitoring": ("Monitoring", "194.247.182.159"),
    }

    with Diagram(
        "NiteRide.FM Network Topology",
        show=False,
        filename=str(DIAGRAMS_DIR / "network"),
        outformat="png",
        direction="LR"
    ):
        server_nodes = {}

        for name, (label, ip) in servers.items():
            data = load_discovery(name)
            if data:
                ports = get_listening_ports(data)
                port_list = [str(p.get("port", "?")) for p in ports[:5]]
                port_str = ", ".join(port_list)
                if len(ports) > 5:
                    port_str += f" +{len(ports)-5} more"
            else:
                port_str = "?"

            server_nodes[name] = Server(f"{label}\n{ip}\nPorts: {port_str}")

        # Show connections between servers
        server_nodes["web"] >> Edge(label="proxy") >> server_nodes["stream"]
        server_nodes["web"] >> Edge(label="auth") >> server_nodes["grid"]
        server_nodes["stream"] >> Edge(style="dashed") >> server_nodes["monitoring"]
        server_nodes["grid"] >> Edge(style="dashed") >> server_nodes["monitoring"]

    print(f"Generated: {DIAGRAMS_DIR / 'network.png'}")


if __name__ == "__main__":
    print("Generating architecture diagrams...")
    generate_architecture_diagram()
    generate_network_diagram()
    print("Done!")

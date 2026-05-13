#!/bin/bash
# ============================================
# IoT-NAS — Node 1 Setup Script
# ============================================
# Run on EC2 t3.large (NAS Core) after SSH
# Usage: chmod +x setup-node1.sh && sudo ./setup-node1.sh
set -e

echo "============================================"
echo "  IoT-NAS — Node 1 (NAS Core) Setup"
echo "============================================"

# ---- 1. System Updates ----
echo "[1/7] Updating system packages..."
apt-get update -y
apt-get upgrade -y
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq \
    htop \
    python3-pip \
    python3-venv

# ---- 2. Install Docker ----
echo "[2/7] Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    echo "Docker installed: $(docker --version)"
else
    echo "Docker already installed: $(docker --version)"
fi

# Verify Docker Compose v2
docker compose version || {
    echo "ERROR: Docker Compose v2 not available"
    exit 1
}

# ---- 3. Install Node Exporter (host-level metrics) ----
echo "[3/7] Installing Node Exporter..."
if ! systemctl is-active --quiet node_exporter; then
    NODE_EXPORTER_VERSION="1.7.0"
    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    
    # Create systemd service
    cat > /etc/systemd/system/node_exporter.service << 'NODEEOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=nobody
Group=nogroup
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
NODEEOF
    
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    echo "Node Exporter installed and running on :9100"
else
    echo "Node Exporter already running"
fi

# ---- 4. Format EBS for Ceph OSD (if attached) ----
echo "[4/7] Checking for additional EBS volumes..."
CEPH_DISK=""
for disk in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$disk" ]; then
        CEPH_DISK="$disk"
        echo "Found EBS volume: $CEPH_DISK"
        # Check if already formatted
        if ! blkid "$CEPH_DISK" &> /dev/null; then
            echo "Wiping $CEPH_DISK for Ceph OSD..."
            wipefs -a "$CEPH_DISK"
            echo "Disk ready for Ceph"
        else
            echo "WARNING: $CEPH_DISK already has a filesystem. Skipping wipe."
            echo "To force: sudo wipefs -a $CEPH_DISK"
        fi
        break
    fi
done
if [ -z "$CEPH_DISK" ]; then
    echo "No additional EBS volume found. Attach a 20GB gp3 EBS for Ceph OSD."
fi

# ---- 5. Clone/Setup project ----
echo "[5/7] Setting up project directory..."
PROJECT_DIR="/home/ubuntu/iot-nas"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Project directory not found at $PROJECT_DIR"
    echo "Please copy your project files here, e.g.:"
    echo "  scp -r -i your-key.pem ./IoT_NAS/* ubuntu@<EC2_IP>:~/iot-nas/"
    echo "Or: git clone <your-repo-url> ~/iot-nas"
    mkdir -p "$PROJECT_DIR"
fi

# ---- 6. Start Docker services ----
echo "[6/7] Starting Docker services..."
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    cd "$PROJECT_DIR"
    echo "Building containers (this may take 5-10 minutes on first run)..."
    docker compose build --parallel
    docker compose up -d
    echo "Waiting 30s for services to initialize..."
    sleep 30
    docker compose ps
else
    echo "docker-compose.yml not found at $PROJECT_DIR"
    echo "Copy project files first, then re-run this step."
fi

# ---- 7. Install simulator dependencies ----
echo "[7/7] Setting up IoT simulator..."
if [ -f "$PROJECT_DIR/simulator/requirements.txt" ]; then
    cd "$PROJECT_DIR/simulator"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    deactivate
    echo "Simulator ready. Run with:"
    echo "  cd ~/iot-nas/simulator && source venv/bin/activate && python simulate.py"
fi

echo ""
echo "============================================"
echo "  Node 1 Setup Complete!"
echo "============================================"
echo ""
echo "  Services: docker compose ps"
echo "  Logs:     docker compose logs -f"
echo "  Health:   curl localhost:8001/health"
echo "           curl localhost:8000/health"
echo "           curl localhost:8002/health"
echo ""
echo "  Next steps:"
echo "  1. Copy project to Nodes 2/3 and run setup-ceph-nodes.sh"
echo "  2. Run setup-ceph-cluster.sh on this node"
echo "  3. Import n8n workflows at http://<PUBLIC_IP>:5678"
echo "============================================"

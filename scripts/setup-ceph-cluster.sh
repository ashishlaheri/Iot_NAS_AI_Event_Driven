#!/bin/bash
# ============================================
# IoT-NAS — Ceph Cluster Setup Script
# ============================================
# Run on Node 1 AFTER setup-node1.sh and setup-ceph-nodes.sh
# 
# BEFORE RUNNING: Set the IP addresses below!
# 
# Usage: chmod +x setup-ceph-cluster.sh && sudo ./setup-ceph-cluster.sh
set -e

# ============================================
# ⚠️  CONFIGURE THESE BEFORE RUNNING ⚠️
# ============================================
# Use PRIVATE IPs (from hostname -I on each node)
NODE1_IP="${NODE1_IP:-REPLACE_ME}"
NODE2_IP="${NODE2_IP:-REPLACE_ME}"
NODE3_IP="${NODE3_IP:-REPLACE_ME}"

if [[ "$NODE1_IP" == "REPLACE_ME" ]]; then
    echo "ERROR: Set NODE1_IP, NODE2_IP, NODE3_IP before running!"
    echo ""
    echo "Usage:"
    echo "  export NODE1_IP=10.0.1.10"
    echo "  export NODE2_IP=10.0.1.11"
    echo "  export NODE3_IP=10.0.1.12"
    echo "  sudo -E ./setup-ceph-cluster.sh"
    exit 1
fi

echo "============================================"
echo "  IoT-NAS — Ceph 3-Node Cluster Setup"
echo "============================================"
echo "  Node 1 (MON+MGR+OSD): $NODE1_IP"
echo "  Node 2 (OSD):         $NODE2_IP"
echo "  Node 3 (OSD):         $NODE3_IP"
echo "============================================"

# ---- 1. Install cephadm ----
echo "[1/9] Installing cephadm..."
if ! command -v cephadm &> /dev/null; then
    CEPH_RELEASE="reef"  # Latest stable
    curl --silent --remote-name --location \
        "https://download.ceph.com/rpm-${CEPH_RELEASE}/el9/noarch/cephadm"
    chmod +x cephadm
    ./cephadm add-repo --release "$CEPH_RELEASE"
    ./cephadm install
    echo "cephadm installed: $(cephadm version)"
else
    echo "cephadm already installed"
fi

# ---- 2. Bootstrap Ceph cluster on Node 1 ----
echo "[2/9] Bootstrapping Ceph cluster..."
if ! ceph status &> /dev/null; then
    cephadm bootstrap \
        --mon-ip "$NODE1_IP" \
        --initial-dashboard-user admin \
        --initial-dashboard-password iotnas2024 \
        --dashboard-password-noupdate \
        --allow-fqdn-hostname \
        --skip-monitoring-stack
    echo "Ceph bootstrap complete"
else
    echo "Ceph cluster already running"
fi

# Wait for bootstrap to stabilize
echo "Waiting 30s for cluster to stabilize..."
sleep 30

# ---- 3. Install ceph CLI tools ----
echo "[3/9] Installing Ceph CLI tools..."
cephadm install ceph-common

# ---- 4. Copy SSH key to other nodes ----
echo "[4/9] Distributing Ceph SSH key to Node 2 and Node 3..."
CEPH_PUB_KEY=$(ceph cephadm get-pub-key)

for NODE_IP in $NODE2_IP $NODE3_IP; do
    echo "Copying key to $NODE_IP..."
    ssh-copy-id -f -i /etc/ceph/ceph.pub root@"$NODE_IP" 2>/dev/null || {
        echo "Auto-copy failed. Manually add this key to root@$NODE_IP:~/.ssh/authorized_keys:"
        echo "$CEPH_PUB_KEY"
        echo ""
        echo "Run on Node 2/3:"
        echo "  echo '$CEPH_PUB_KEY' >> /root/.ssh/authorized_keys"
        echo ""
        read -p "Press Enter after adding the key to $NODE_IP..."
    }
done

# ---- 5. Add hosts ----
echo "[5/9] Adding Ceph hosts..."
ceph orch host add iot-nas-ceph2 "$NODE2_IP"
ceph orch host add iot-nas-ceph3 "$NODE3_IP"
echo "Waiting 30s for hosts to register..."
sleep 30
ceph orch host ls

# ---- 6. Add OSDs ----
echo "[6/9] Adding Ceph OSDs..."

# Detect available disks on each node
# Common EBS device names on Nitro instances
for DISK in /dev/nvme1n1 /dev/xvdf; do
    # Node 1 OSD
    if [ -b "$DISK" ]; then
        echo "Adding OSD on Node 1: $DISK"
        ceph orch daemon add osd "$(hostname -s):$DISK" || echo "OSD on Node 1 may already exist"
        break
    fi
done

# Node 2 and 3 OSDs (cephadm discovers available devices)
echo "Adding OSDs on Node 2 and Node 3..."
ceph orch daemon add osd "iot-nas-ceph2:/dev/nvme1n1" 2>/dev/null || \
    ceph orch daemon add osd "iot-nas-ceph2:/dev/xvdf" 2>/dev/null || \
    echo "WARNING: Could not auto-add OSD on Node 2. Check: ceph orch device ls"

ceph orch daemon add osd "iot-nas-ceph3:/dev/nvme1n1" 2>/dev/null || \
    ceph orch daemon add osd "iot-nas-ceph3:/dev/xvdf" 2>/dev/null || \
    echo "WARNING: Could not auto-add OSD on Node 3. Check: ceph orch device ls"

echo "Waiting 60s for OSDs to come up..."
sleep 60

# ---- 7. Verify OSD status ----
echo "[7/9] Checking OSD status..."
ceph osd tree
ceph status

# ---- 8. Create storage pools ----
echo "[8/9] Creating storage pools..."
# P1/P2 high-priority pool (size=2 for 2 replicas)
ceph osd pool create iot-p1-nvme 32 32 replicated
ceph osd pool set iot-p1-nvme size 2
ceph osd pool set iot-p1-nvme min_size 1

# P3 replicated pool
ceph osd pool create iot-p3-replicated 32 32 replicated
ceph osd pool set iot-p3-replicated size 2
ceph osd pool set iot-p3-replicated min_size 1

# Forensic logs pool
ceph osd pool create iot-forensic-logs 16 16 replicated
ceph osd pool set iot-forensic-logs size 2
ceph osd pool set iot-forensic-logs min_size 1

echo "Pools created:"
ceph osd pool ls detail

# ---- 9. Deploy RADOS Gateway (S3 compatible) ----
echo "[9/9] Deploying RADOS Gateway for S3 compatibility..."
ceph orch apply rgw iotnas --placement="1 $(hostname -s)" --port=7480

echo "Waiting 30s for RGW to start..."
sleep 30

# Create S3 user and bucket
radosgw-admin user create \
    --uid=iotnas \
    --display-name="IoT-NAS S3 User" \
    --access-key=IOTNAS_ACCESS_KEY \
    --secret-key=IOTNAS_SECRET_KEY 2>/dev/null || echo "User may already exist"

echo ""
echo "============================================"
echo "  Ceph Cluster Setup Complete!"
echo "============================================"
echo ""
echo "  Status:    sudo ceph status"
echo "  OSDs:      sudo ceph osd tree"
echo "  Pools:     sudo ceph osd pool ls detail"
echo "  Dashboard: https://${NODE1_IP}:8443"
echo "             User: admin / Password: iotnas2024"
echo ""
echo "  S3 Endpoint: http://${NODE1_IP}:7480"
echo "  S3 Access:   IOTNAS_ACCESS_KEY"
echo "  S3 Secret:   IOTNAS_SECRET_KEY"
echo ""
echo "  Fault tolerance demo:"
echo "    ssh root@$NODE3_IP 'systemctl stop ceph-osd@*'"
echo "    ceph status  # → HEALTH_WARN, 2 OSDs"
echo "    ssh root@$NODE3_IP 'systemctl start ceph-osd@*'"
echo "    ceph status  # → HEALTH_OK after ~2-4 min"
echo "============================================"

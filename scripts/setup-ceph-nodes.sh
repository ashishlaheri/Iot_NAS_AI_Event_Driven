#!/bin/bash
# ============================================
# IoT-NAS — Ceph Node Setup Script
# ============================================
# Run on Node 2 and Node 3 (t3.medium) to prepare for Ceph
# Usage: chmod +x setup-ceph-nodes.sh && sudo ./setup-ceph-nodes.sh
set -e

echo "============================================"
echo "  IoT-NAS — Ceph Node Preparation"
echo "============================================"

# ---- 1. System Updates ----
echo "[1/5] Updating system packages..."
apt-get update -y
apt-get install -y \
    curl \
    lvm2 \
    chrony \
    python3 \
    jq

# ---- 2. Install Docker (required by cephadm) ----
echo "[2/5] Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    echo "Docker installed: $(docker --version)"
else
    echo "Docker already installed: $(docker --version)"
fi

# ---- 3. Enable root SSH (required by cephadm) ----
echo "[3/5] Enabling root SSH access for cephadm..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# Copy ubuntu user's authorized keys to root
mkdir -p /root/.ssh
cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys 2>/dev/null || true
chmod 600 /root/.ssh/authorized_keys
chmod 700 /root/.ssh

echo "Root SSH enabled"

# ---- 4. Prepare EBS disk for Ceph OSD ----
echo "[4/5] Preparing EBS volume for Ceph OSD..."
CEPH_DISK=""
for disk in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$disk" ]; then
        CEPH_DISK="$disk"
        echo "Found EBS volume: $CEPH_DISK"
        if ! blkid "$CEPH_DISK" &> /dev/null; then
            wipefs -a "$CEPH_DISK"
            echo "Disk wiped and ready for Ceph OSD"
        else
            echo "WARNING: $CEPH_DISK has existing data."
            echo "To wipe: sudo wipefs -a $CEPH_DISK"
        fi
        break
    fi
done
if [ -z "$CEPH_DISK" ]; then
    echo "ERROR: No additional EBS volume found!"
    echo "Attach a 20GB gp3 EBS volume to this instance first."
fi

# ---- 5. Sync time (critical for Ceph) ----
echo "[5/5] Configuring time sync..."
systemctl enable chrony
systemctl start chrony
chronyc makestep 2>/dev/null || true

PRIVATE_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================"
echo "  Ceph Node Preparation Complete!"
echo "============================================"
echo ""
echo "  Private IP: $PRIVATE_IP"
echo "  Ceph disk:  ${CEPH_DISK:-NOT FOUND}"
echo ""
echo "  Note this IP — you need it for setup-ceph-cluster.sh"
echo "  Root SSH is enabled for cephadm"
echo "============================================"

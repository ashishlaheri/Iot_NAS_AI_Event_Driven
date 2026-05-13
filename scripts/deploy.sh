#!/bin/bash
# IoT-NAS — Deploy Script (from local machine)
# Transfers project to Node 1 and triggers setup
# Set KEY_FILE, NODE1_IP, NODE2_IP, NODE3_IP env vars before running
set -e

KEY_FILE="${KEY_FILE:-~/.ssh/iot-nas-key.pem}"
NODE1_PUBLIC_IP="${NODE1_IP:-REPLACE_ME}"
NODE2_PUBLIC_IP="${NODE2_IP:-REPLACE_ME}"
NODE3_PUBLIC_IP="${NODE3_IP:-REPLACE_ME}"
PROJECT_DIR="$(dirname "$(dirname "$0")")"
SSH_USER="ubuntu"
SSH_OPTS="-i $KEY_FILE -o StrictHostKeyChecking=no"

if [[ "$NODE1_PUBLIC_IP" == "REPLACE_ME" ]]; then
    echo "Set NODE1_IP, NODE2_IP, NODE3_IP, KEY_FILE env vars first!"
    exit 1
fi

echo "[1/4] Uploading project to Node 1..."
rsync -avz -e "ssh $SSH_OPTS" --exclude '.git' --exclude 'venv' \
    "$PROJECT_DIR/" "$SSH_USER@$NODE1_PUBLIC_IP:~/iot-nas/"

echo "[2/4] Running Node 1 setup..."
ssh $SSH_OPTS "$SSH_USER@$NODE1_PUBLIC_IP" \
    "chmod +x ~/iot-nas/scripts/*.sh && sudo ~/iot-nas/scripts/setup-node1.sh"

echo "[3/4] Setting up Node 2..."
scp $SSH_OPTS "$PROJECT_DIR/scripts/setup-ceph-nodes.sh" "$SSH_USER@$NODE2_PUBLIC_IP:~/"
ssh $SSH_OPTS "$SSH_USER@$NODE2_PUBLIC_IP" "chmod +x ~/setup-ceph-nodes.sh && sudo ~/setup-ceph-nodes.sh"

echo "[4/4] Setting up Node 3..."
scp $SSH_OPTS "$PROJECT_DIR/scripts/setup-ceph-nodes.sh" "$SSH_USER@$NODE3_PUBLIC_IP:~/"
ssh $SSH_OPTS "$SSH_USER@$NODE3_PUBLIC_IP" "chmod +x ~/setup-ceph-nodes.sh && sudo ~/setup-ceph-nodes.sh"

echo "All nodes ready. SSH into Node 1 to run setup-ceph-cluster.sh next."

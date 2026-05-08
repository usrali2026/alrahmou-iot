#!/bin/bash
set -e

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"

echo "[WORKER] Updating packages..."
sudo apt-get update -y >/dev/null

echo "[WORKER] Installing base tools (curl)..."
sudo apt-get install -y curl >/dev/null

echo "[WORKER] Waiting for token from ${SERVER_IP}:9999..."
TOKEN=""
while [ -z "$TOKEN" ]; do
  TOKEN=$(curl -sf "http://${SERVER_IP}:9999" 2>/dev/null || true)
  [ -z "$TOKEN" ] && sleep 2
done
echo "[WORKER] Got token, joining cluster..."

echo "[WORKER] Installing K3s agent on ${WORKER_IP}..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${TOKEN}" \
  INSTALL_K3S_EXEC="agent \
    --node-ip ${WORKER_IP}" sh -

echo "[WORKER] K3s agent installed."
sudo systemctl status k3s-agent --no-pager -l || true

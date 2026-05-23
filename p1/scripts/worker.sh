#!/bin/bash
set -euo pipefail

NET_IFACE="enp0s8"
SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"
K3S_TOKEN="k3s-iot-shared-token"

echo "[worker] Waiting for K3s server at ${SERVER_IP}:6443..."
until curl -sk "https://${SERVER_IP}:6443/ping" &>/dev/null; do
  sleep 3
done

echo "[worker] Installing K3s in agent mode..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${SERVER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="agent \
    --node-ip=${WORKER_IP} \
    --flannel-iface=${NET_IFACE}" \
  sh -

echo "[worker] Agent installed and joined cluster."

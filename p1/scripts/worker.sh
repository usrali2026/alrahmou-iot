#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"
K3S_TOKEN="k3s-iot-shared-token"

detect_iface() {
  local iface
  iface="$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.56\./ {print $2; exit}')"
  if [ -z "${iface}" ]; then
    iface="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  fi
  echo "${iface}"
}

NET_IFACE="$(detect_iface)"

if [ -z "${NET_IFACE}" ]; then
  echo "[worker] unable to detect network interface" >&2
  exit 1
fi

echo "[worker] Waiting for K3s server at ${SERVER_IP}:6443..."
timeout=120
interval=3
elapsed=0
until curl -sk "https://${SERVER_IP}:6443/ping" &>/dev/null; do
  sleep ${interval}
  elapsed=$((elapsed+interval))
  if [ ${elapsed} -ge ${timeout} ]; then
    echo "[worker] timeout waiting for server ping after ${timeout}s" >&2
    exit 1
  fi
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

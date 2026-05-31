#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"
K3S_TOKEN="k3s-iot-shared-token"

detect_iface() {
  local iface

  for _ in $(seq 1 60); do
    iface="$(ip -o -4 addr show | awk -v ip="${WORKER_IP}" '$4 ~ "^" ip "\\/" {print $2; exit}')"
    if [ -n "${iface}" ]; then
      echo "${iface}"
      return 0
    fi
    sleep 1
  done

  return 1
}

if ! NET_IFACE="$(detect_iface)"; then
  echo "[worker] unable to detect network interface for ${WORKER_IP}" >&2
  ip -o -4 addr show >&2 || true
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1; then
  echo "[worker] Installing curl..."
  apt-get update -y >/dev/null
  apt-get install -y curl >/dev/null
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

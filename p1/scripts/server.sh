#!/bin/bash
set -e

SERVER_IP="192.168.56.110"

echo "[SERVER] Updating packages..."
sudo apt-get update -y >/dev/null

echo "[SERVER] Installing base tools (curl, netcat)..."
sudo apt-get install -y curl netcat-openbsd >/dev/null

echo "[SERVER] Installing K3s server on ${SERVER_IP}..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip ${SERVER_IP} \
  --bind-address ${SERVER_IP} \
  --advertise-address ${SERVER_IP}" sh -

echo "[SERVER] Waiting for K3s server node to be Ready..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 3
done

echo "[SERVER] Nodes:"
kubectl get nodes -o wide

TOKEN_FILE=/var/lib/rancher/k3s/server/node-token
PORT=9999

echo "[SERVER] Serving join token on port ${PORT}..."
while true; do
  if [ -f "$TOKEN_FILE" ]; then
    tok=$(cat "$TOKEN_FILE")
    body="${tok}"
    len=${#body}
    {
      printf 'HTTP/1.1 200 OK\r\n'
      printf 'Content-Type: text/plain\r\n'
      printf 'Content-Length: %s\r\n' "$len"
      printf '\r\n'
      printf '%s' "$body"
    } | nc -l -p "${PORT}" -q 1 2>/dev/null || true
  else
    sleep 1
  fi
done &

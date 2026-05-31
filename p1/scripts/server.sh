#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"
K3S_TOKEN="k3s-iot-shared-token"

detect_iface() {
  local iface

  for _ in $(seq 1 60); do
    iface="$(ip -o -4 addr show | awk -v ip="${SERVER_IP}" '$4 ~ "^" ip "\\/" {print $2; exit}')"
    if [ -n "${iface}" ]; then
      echo "${iface}"
      return 0
    fi
    sleep 1
  done

  return 1
}

if ! NET_IFACE="$(detect_iface)"; then
  echo "[server] unable to detect network interface for ${SERVER_IP}" >&2
  ip -o -4 addr show >&2 || true
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1; then
  echo "[server] Installing curl..."
  apt-get update -y >/dev/null
  apt-get install -y curl >/dev/null
fi

echo "[server] Installing K3s in controller mode..."
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="server \
    --bind-address=${SERVER_IP} \
    --advertise-address=${SERVER_IP} \
    --node-ip=${SERVER_IP} \
      --flannel-iface=${NET_IFACE} \
      --write-kubeconfig-mode=644" \
  sh -

echo "[server] Waiting for node to become Ready..."
timeout=180
interval=3
elapsed=0
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep ${interval}
  elapsed=$((elapsed+interval))
  if [ ${elapsed} -ge ${timeout} ]; then
    echo "[server] timeout waiting for node Ready after ${timeout}s" >&2
    break
  fi
done

echo "[server] Configuring kubeconfig for vagrant user..."
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
cat >/etc/profile.d/kubeconfig.sh <<'EOF'
export KUBECONFIG=/home/vagrant/.kube/config
EOF
chmod 644 /etc/profile.d/kubeconfig.sh

echo "[server] Node status:"
kubectl get nodes -o wide
echo "[server] Done."

#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"
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
  echo "[server] unable to detect network interface" >&2
  exit 1
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

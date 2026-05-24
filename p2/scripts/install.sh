#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"
NET_IFACE="$(ip -o -4 addr show | awk -v ip="${SERVER_IP}" '$4 ~ "^" ip "\\/" {print $2; exit}')"

if [[ -z "${NET_IFACE}" ]]; then
  NET_IFACE="eth1"
fi

echo "[p2] Installing K3s in server mode..."
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server \
    --bind-address=${SERVER_IP} \
    --advertise-address=${SERVER_IP} \
    --node-ip=${SERVER_IP} \
    --flannel-iface=${NET_IFACE}" \
  sh -

echo "[p2] Waiting for node to become Ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 3
done

echo "[p2] Deploying applications..."
MANIFESTS_DIR="/home/vagrant/confs"

if [[ ! -d "${MANIFESTS_DIR}" ]]; then
  echo "[p2] ERROR: manifests directory not found at ${MANIFESTS_DIR}"
  exit 1
fi

kubectl apply -f "${MANIFESTS_DIR}/"

echo "[p2] Waiting for all deployments to roll out..."
kubectl rollout status deployment/app1 --timeout=120s
kubectl rollout status deployment/app2 --timeout=120s
kubectl rollout status deployment/app3 --timeout=120s

echo "[p2] Configuring kubeconfig for vagrant user..."
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc

echo ""
echo "[p2] Setup complete. Test with:"
echo "  curl -H 'Host: app1.com' http://${SERVER_IP}"
echo "  curl -H 'Host: app2.com' http://${SERVER_IP}"
echo "  curl http://${SERVER_IP}          # → app3 (default)"

#!/bin/bash
set -euo pipefail

NET_IFACE="enp0s8"        # second NIC on ubuntu/jammy64 (private_network)
SERVER_IP="192.168.56.110"
K3S_TOKEN="k3s-iot-shared-token"

echo "[server] Installing K3s in controller mode..."
curl -sfL https://get.k3s.io | \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="server \
    --bind-address=${SERVER_IP} \
    --advertise-address=${SERVER_IP} \
    --node-ip=${SERVER_IP} \
    --flannel-iface=${NET_IFACE}" \
  sh -

echo "[server] Waiting for node to become Ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 3
done

echo "[server] Configuring kubeconfig for vagrant user..."
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc

echo "[server] Node status:"
kubectl get nodes -o wide
echo "[server] Done."

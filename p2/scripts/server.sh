#!/bin/bash
set -e

SERVER_IP="192.168.56.110"
MANIFEST_DIR="/home/vagrant/confs"

echo "[SERVER] Updating packages..."
sudo apt-get update -y >/dev/null

echo "[SERVER] Installing curl..."
sudo apt-get install -y curl >/dev/null

echo "[SERVER] Installing K3s server on ${SERVER_IP}..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip ${SERVER_IP} \
  --bind-address ${SERVER_IP} \
  --advertise-address ${SERVER_IP}" sh -

echo "[SERVER] Waiting for node to be Ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready "; do
  sleep 3
done

echo "[SERVER] Waiting for Traefik ingress controller..."
until kubectl -n kube-system get pods 2>/dev/null | grep -E 'traefik.*Running' >/dev/null; do
  sleep 3
done

echo "[SERVER] Creating webapps namespace..."
kubectl create namespace webapps --dry-run=client -o yaml | kubectl apply -f -

echo "[SERVER] Checking uploaded manifests..."
ls -R "${MANIFEST_DIR}"

echo "[SERVER] Applying application manifests..."
kubectl apply -f "${MANIFEST_DIR}/app1.yaml"    -n webapps
kubectl apply -f "${MANIFEST_DIR}/app2.yaml"    -n webapps
kubectl apply -f "${MANIFEST_DIR}/app3.yaml"    -n webapps
kubectl apply -f "${MANIFEST_DIR}/ingress.yaml" -n webapps

echo "[SERVER] Waiting for applications..."
kubectl rollout status deployment/app1-deployment -n webapps --timeout=120s
kubectl rollout status deployment/app2-deployment -n webapps --timeout=120s
kubectl rollout status deployment/app3-deployment -n webapps --timeout=120s

echo "[SERVER] Final status:"
kubectl get pods,svc,ingress -n webapps

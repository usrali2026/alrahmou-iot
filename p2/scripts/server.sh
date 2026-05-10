#!/bin/bash
set -e

SERVER_IP="192.168.56.110"
MANIFEST_DIR="/home/vagrant/confs"

echo "[SERVER] Updating packages..."
sudo DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get update -y </dev/null >/dev/null

echo "[SERVER] Installing curl..."
sudo DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true apt-get install -y curl </dev/null >/dev/null

echo "[SERVER] Configuring network interface eth1..."
sudo ip link set eth1 up
sudo ip addr add ${SERVER_IP}/24 dev eth1 2>/dev/null || true
sudo ip route add 192.168.56.0/24 dev eth1 2>/dev/null || true

echo "[SERVER] Waiting for eth1 to be ready..."
sleep 2

echo "[SERVER] Installing K3s server on ${SERVER_IP}..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip ${SERVER_IP} \
  --bind-address 0.0.0.0 \
  --advertise-address ${SERVER_IP}" sh -

echo "[SERVER] Waiting for node to be Ready..."
timeout=60
while [ $timeout -gt 0 ] && ! kubectl get nodes 2>/dev/null | grep -q " Ready "; do
  sleep 3
  timeout=$((timeout - 3))
done
if [ $timeout -le 0 ]; then echo "[SERVER] WARNING: Timeout waiting for node Ready"; fi

echo "[SERVER] Waiting for Traefik ingress controller..."
timeout=60
while [ $timeout -gt 0 ] && ! kubectl -n kube-system get pods 2>/dev/null | grep -E 'traefik.*Running' >/dev/null; do
  sleep 3
  timeout=$((timeout - 3))
done
if [ $timeout -le 0 ]; then echo "[SERVER] WARNING: Timeout waiting for Traefik"; fi

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

echo "[SERVER] Validating ingress Host-based routing..."

check_host_route() {
  host="$1"
  expected="$2"
  attempts=20

  while [ $attempts -gt 0 ]; do
    response=$(curl -s -H "Host: ${host}" "http://${SERVER_IP}/" || true)
    if echo "$response" | grep -qi "$expected"; then
      echo "[SERVER] OK: Host ${host} -> ${response}"
      return 0
    fi
    sleep 2
    attempts=$((attempts - 1))
  done

  echo "[SERVER] ERROR: Host ${host} did not return expected content '${expected}'. Last response: ${response}"
  return 1
}

check_host_route "app1.com" "Hello from app1"
check_host_route "app2.com" "Hello from app2"
check_host_route "unknown.com" "Hello from app3"

echo "[SERVER] Ingress validation passed."

#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"
MANIFEST_DIR="/home/vagrant/confs"

echo "[SERVER] provision v2 — waiting for eth1, no helm CLI"
echo "[SERVER] Updating packages..."
export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1; then
  apt-get update -y >/dev/null
  apt-get install -y curl >/dev/null
fi

detect_net_iface() {
  local iface candidate

  # Vagrant private_network may appear shortly after boot — never use lo.
  for _ in $(seq 1 15); do
    iface=$(ip -o -4 addr show | awk -v ip="${SERVER_IP}" '$4 ~ "^" ip "\\/" {print $2; exit}')
    if [[ -n "${iface}" && "${iface}" != "lo" ]]; then
      echo "${iface}"
      return 0
    fi
    sleep 1
  done

  for candidate in eth1 enp0s8 enp0s9 enp0s6; do
    if ip link show "${candidate}" &>/dev/null; then
      ip link set "${candidate}" up || true
      ip addr show dev "${candidate}" | grep -q "${SERVER_IP}/" \
        || ip addr add "${SERVER_IP}/24" dev "${candidate}" 2>/dev/null || true
      if ip addr show dev "${candidate}" | grep -q "${SERVER_IP}/"; then
        echo "${candidate}"
        return 0
      fi
    fi
  done

  echo "[SERVER] ERROR: ${SERVER_IP} not on any interface (got lo or none)." >&2
  ip -o -4 addr show >&2 || true
  exit 1
}

NET_IFACE="$(detect_net_iface)"
echo "[SERVER] Network interface: ${NET_IFACE} (${SERVER_IP})"

if ! systemctl is-active k3s &>/dev/null; then
  echo "[SERVER] Installing K3s server on ${SERVER_IP}..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
    --write-kubeconfig-mode 644 \
    --node-ip ${SERVER_IP} \
    --advertise-address ${SERVER_IP} \
    --flannel-iface ${NET_IFACE}" sh -
else
  echo "[SERVER] K3s already running."
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "[SERVER] Waiting for node to be Ready..."
kubectl wait --for=condition=Ready node --all --timeout=45s >/dev/null 2>&1 || {
  kubectl get nodes 2>/dev/null || true
}

wait_for_traefik() {
  echo "[SERVER] Waiting for Traefik (k3s helm-controller, no helm CLI needed)..."
  local i
  for i in $(seq 1 60); do
    if kubectl get svc -n kube-system traefik &>/dev/null; then
      echo "[SERVER] Traefik service is up."
      return 0
    fi
    # Restart stuck k3s traefik helm jobs once (common on slow first boot)
    if [[ "${i}" -eq 20 ]]; then
      echo "[SERVER] Nudging Traefik helm jobs..."
      kubectl delete job -n kube-system helm-install-traefik helm-install-traefik-crd \
        --ignore-not-found --force --grace-period=0 2>/dev/null || true
    fi
    sleep 2
  done
  echo "[SERVER] ERROR: Traefik not ready." >&2
  kubectl get pods,jobs -n kube-system 2>/dev/null | grep traefik || true
  return 1
}

wait_for_port80() {
  echo "[SERVER] Waiting for listener on :80..."
  local i
  for i in $(seq 1 10); do
    if ss -tln | grep -q ':80 '; then
      echo "[SERVER] Port 80 is listening."
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_traefik
wait_for_port80 || echo "[SERVER] WARN: port 80 not up yet; ingress tests may fail."

echo "[SERVER] Creating webapps namespace..."
kubectl create namespace webapps --dry-run=client -o yaml | kubectl apply -f -

echo "[SERVER] Applying manifests from ${MANIFEST_DIR}..."
kubectl apply -f "${MANIFEST_DIR}/app1.yaml" -n webapps
kubectl apply -f "${MANIFEST_DIR}/app2.yaml" -n webapps
kubectl apply -f "${MANIFEST_DIR}/app3.yaml" -n webapps
kubectl apply -f "${MANIFEST_DIR}/ingress.yaml" -n webapps

echo "[SERVER] Waiting for rollouts..."
kubectl rollout status deployment/app1-deployment -n webapps --timeout=90s || true
kubectl rollout status deployment/app2-deployment -n webapps --timeout=90s || true
kubectl rollout status deployment/app3-deployment -n webapps --timeout=90s || true

kubectl get pods,svc,ingress -n webapps

check_host_route() {
  local host="$1" expected="$2" response attempts=40
  attempts=10
  while [[ "${attempts}" -gt 0 ]]; do
    response=$(curl -sf -H "Host: ${host}" "http://${SERVER_IP}/" 2>/dev/null || true)
    if echo "${response}" | grep -qi "${expected}"; then
      echo "[SERVER] OK: Host ${host} -> $(echo "${response}" | grep -oi '<h1>.*</h1>' | head -1)"
      return 0
    fi
    sleep 1
    attempts=$((attempts - 1))
  done
  echo "[SERVER] ERROR: Host ${host} expected '${expected}', got: ${response:-empty}" >&2
  kubectl get ingress -n webapps
  kubectl get svc -n kube-system traefik 2>/dev/null || true
  return 1
}

echo "[SERVER] Validating Host-based routing (subject requirement)..."
check_host_route "app1.com" "Hello from app1."
check_host_route "app2.com" "Hello from app2."
check_host_route "unknown.com" "Hello from app3."
echo "[SERVER] All ingress checks passed."

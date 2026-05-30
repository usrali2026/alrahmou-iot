#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

detect_net_iface() {
  local iface
  iface=$(ip -o -4 addr show | awk -v ip="${SERVER_IP}" '$4 ~ "^" ip "\\/" {print $2; exit}')
  if [[ -n "${iface}" ]]; then
    echo "${iface}"
    return
  fi
  for candidate in eth1 enp0s6 enp0s8 enp0s9 eth0; do
    if ip -o -4 addr show dev "${candidate}" 2>/dev/null | grep -q "${SERVER_IP}/"; then
      echo "${candidate}"
      return
    fi
  done
  echo "[p2] ERROR: ${SERVER_IP} not configured on any interface." >&2
  ip -o -4 addr show >&2 || true
  exit 1
}

wait_for_traefik() {
  echo "[p2] Waiting for Traefik ingress controller (required for port 80)..."
  local i chart
  for i in $(seq 1 90); do
    if k3s kubectl get svc -n kube-system traefik &>/dev/null; then
      echo "[p2] Traefik service is up."
      return 0
    fi
    if [[ "${i}" -eq 30 ]]; then
      echo "[p2] Traefik slow — trying manual helm install..."
      chart=$(ls /var/lib/rancher/k3s/server/static/charts/traefik-*.tgz 2>/dev/null | head -1)
      if [[ -n "${chart}" ]] && ! helm ls -n kube-system 2>/dev/null | grep -qE '^traefik'; then
        helm install traefik "${chart}" -n kube-system --wait --timeout 10m || true
      fi
    fi
    sleep 10
  done
  echo "[p2] ERROR: Traefik did not become ready. Check: kubectl get pods -n kube-system | grep traefik" >&2
  echo "[p2] Hint: VM needs at least 2GB RAM for K3s + Traefik + apps." >&2
  return 1
}

wait_for_ingress() {
  echo "[p2] Waiting for HTTP on ${SERVER_IP}:80 ..."
  local i
  for i in $(seq 1 60); do
    if curl -sf --max-time 3 -H 'Host: app1.com' "http://${SERVER_IP}/" >/dev/null 2>&1; then
      echo "[p2] Ingress responding on ${SERVER_IP}."
      return 0
    fi
    sleep 5
  done
  echo "[p2] WARN: port 80 not responding yet (Traefik/svclb may still be starting)."
  ss -tlnp | grep ':80' || true
  k3s kubectl get svc -n kube-system traefik 2>/dev/null || true
  return 1
}

NET_IFACE="$(detect_net_iface)"
echo "[p2] Using network interface: ${NET_IFACE} (${SERVER_IP})"

if command -v k3s-uninstall.sh &>/dev/null && systemctl is-active k3s &>/dev/null; then
  echo "[p2] K3s already running; skipping install."
else
  if command -v k3s-uninstall.sh &>/dev/null; then
    echo "[p2] Removing previous failed K3s install..."
    k3s-uninstall.sh || true
  fi

  echo "[p2] Installing K3s in server mode..."
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_EXEC="server \
      --advertise-address=${SERVER_IP} \
      --node-ip=${SERVER_IP} \
      --flannel-iface=${NET_IFACE}" \
    sh -
fi

echo "[p2] Waiting for node to become Ready..."
until k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 3
done

wait_for_traefik

echo "[p2] Deploying applications..."
MANIFESTS_DIR="/home/vagrant/confs"

if [[ ! -d "${MANIFESTS_DIR}" ]]; then
  echo "[p2] ERROR: manifests directory not found at ${MANIFESTS_DIR}"
  ls -la /home/vagrant/ || true
  exit 1
fi

k3s kubectl apply -f "${MANIFESTS_DIR}/"

echo "[p2] Waiting for all deployments to roll out..."
k3s kubectl rollout status deployment/app1-deployment --timeout=180s
k3s kubectl rollout status deployment/app2-deployment --timeout=180s
k3s kubectl rollout status deployment/app3-deployment --timeout=180s

wait_for_ingress || true

echo "[p2] Configuring kubeconfig for vagrant user..."
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sed -i "s/127.0.0.1/${SERVER_IP}/" /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
grep -q 'KUBECONFIG=/home/vagrant/.kube/config' /home/vagrant/.bashrc \
  || echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc

echo ""
echo "[p2] Setup complete. Test with:"
echo "  curl -H 'Host: app1.com' http://${SERVER_IP}"
echo "  curl -H 'Host: app2.com' http://${SERVER_IP}"
echo "  curl http://${SERVER_IP}          # → app3 (default)"

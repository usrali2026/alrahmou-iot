#!/bin/bash
set -euo pipefail

SERVER_IP="192.168.56.110"

echo "=== K3s server (${SERVER_IP}) ==="
if ! ping -c1 -W2 "${SERVER_IP}" &>/dev/null; then
  echo "ERROR: ${SERVER_IP} unreachable. Run: vagrant up"
  exit 1
fi
echo "Ping OK"

echo ""
echo "=== Traefik (port 80) ==="
if curl -sf --max-time 3 "http://${SERVER_IP}/" >/dev/null 2>&1 || \
   curl -sf --max-time 3 -H 'Host: app1.com' "http://${SERVER_IP}/" >/dev/null 2>&1; then
  echo "Port 80 OK"
else
  echo "FAIL — Traefik not listening. On VM run:"
  echo "  kubectl get svc -n kube-system traefik"
  echo "  kubectl get pods -n kube-system | grep traefik"
fi

show_app() {
  local label="$1" host="${2:-}"
  local body
  if [[ -n "${host}" ]]; then
    body=$(curl -sf --max-time 5 -H "Host: ${host}" "http://${SERVER_IP}/" 2>/dev/null || true)
  else
    body=$(curl -sf --max-time 5 "http://${SERVER_IP}/" 2>/dev/null || true)
  fi
  if echo "${body}" | grep -q '<h1>'; then
    echo "${body}" | grep -o '<h1>.*</h1>'
  else
    echo "FAIL"
  fi
}

echo ""
echo "=== app1.com ==="
show_app app1 app1.com

echo ""
echo "=== app2.com ==="
show_app app2 app2.com

echo ""
echo "=== default (app3) ==="
show_app app3

echo ""
echo "=== pods ==="
if command -v vagrant &>/dev/null && [[ -f Vagrantfile ]]; then
  vagrant ssh -c 'kubectl get pods,ingress -n webapps' 2>/dev/null || true
fi

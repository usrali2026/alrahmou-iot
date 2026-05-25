#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Open / verify Part 3 endpoints on THIS machine (where k3d runs).
#
#  App (playground):  http://localhost:8888/   — published by k3d at install
#  Argo CD UI:        https://localhost:8080/ — requires port-forward (below)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REAL_USER="${SUDO_USER:-${USER}}"
if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
  export KUBECONFIG="/home/${REAL_USER}/.kube/config"
else
  export KUBECONFIG="${HOME}/.kube/config"
fi

CLUSTER_NAME="iot"

echo "=== Cluster ==="
if ! k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "ERROR: k3d cluster '${CLUSTER_NAME}' is not running."
  echo "Start it: ./p3/scripts/install.sh"
  exit 1
fi
k3d cluster list | grep -E "NAME|${CLUSTER_NAME}"

echo ""
echo "=== Port 8888 (playground app) ==="
if ss -tln 2>/dev/null | grep -q ':8888 '; then
  echo "Listener OK on :8888"
else
  echo "WARN: nothing listening on :8888 — recreate cluster:"
  echo "  k3d cluster delete ${CLUSTER_NAME} && ./p3/scripts/install.sh"
fi

if curl -sf --max-time 5 http://127.0.0.1:8888/; then
  echo ""
  echo "App URL (use http, not https): http://localhost:8888/"
else
  echo "WARN: curl to http://127.0.0.1:8888/ failed."
  kubectl get pods,svc -n dev 2>/dev/null || true
fi

echo ""
echo "=== Argo CD UI (port 8080) ==="
if ss -tln 2>/dev/null | grep -q ':8080 '; then
  echo "Port 8080 already in use (port-forward may be running)."
  echo "Open: https://localhost:8080/  (user: admin)"
else
  echo "Argo CD is NOT exposed on :8080 by default."
  echo "Run in a separate terminal (leave it running):"
  echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "Then open: https://localhost:8080/  (accept self-signed cert, user: admin)"
  echo ""
  read -r -p "Start port-forward now in background? [y/N] " ans
  if [[ "${ans}" =~ ^[yY]$ ]]; then
    pkill -f 'port-forward.*argocd-server' 2>/dev/null || true
    kubectl port-forward svc/argocd-server -n argocd 8080:443 >/tmp/argocd-pf.log 2>&1 &
    sleep 2
    if ss -tln 2>/dev/null | grep -q ':8080 '; then
      echo "Port-forward started. Open https://localhost:8080/"
      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo
    else
      echo "Port-forward failed. See /tmp/argocd-pf.log"
      cat /tmp/argocd-pf.log 2>/dev/null || true
    fi
  fi
fi

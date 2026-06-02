#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Open / verify Part 3 endpoints on THIS machine (where k3d runs).
#
#  App (playground):  http://localhost:8888/   — published by k3d at install
#  Argo CD UI:        https://localhost:8080/ — published by k3d at install
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
if curl -skf --max-time 5 https://127.0.0.1:8080/ >/dev/null; then
  echo " UI OK — https://localhost:8080/  (user: admin)"
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo
else
  echo "WARN: Argo CD not reachable on :8080."
  echo "Re-run: ./p3/scripts/install.sh  (or expose via k3d NodePort 30443)"
  kubectl get svc argocd-server -n argocd 2>/dev/null || true
fi

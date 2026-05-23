#!/bin/bash
set -euo pipefail

REAL_USER="${SUDO_USER:-${USER}}"
if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
  export KUBECONFIG="/home/${REAL_USER}/.kube/config"
else
  export KUBECONFIG="${HOME}/.kube/config"
fi

CLUSTER_NAME="iot"

if ! k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "No k3d cluster '${CLUSTER_NAME}' — bonus is not installed yet."
  echo ""
  echo "Run first (10–20 min, needs sudo for /etc/hosts):"
  echo "  cd /media/ali/DEVWORK/projects/Devops/iot"
  echo "  sudo bash ./bonus/scripts/install.sh"
  exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
  echo "Cluster exists but kubectl cannot connect."
  echo "Try: k3d kubeconfig merge ${CLUSTER_NAME} --kubeconfig-merge-default"
  exit 1
fi

echo "=== GitLab ==="
if grep -q '[[:space:]]gitlab\.local' /etc/hosts 2>/dev/null; then
  curl -sf --max-time 5 http://gitlab.local:8929/-/health && echo " OK" || echo " not ready yet (GitLab still starting?)"
else
  echo " missing gitlab.local in /etc/hosts — re-run: sudo bash ./bonus/scripts/install.sh"
fi

echo ""
echo "=== App ==="
curl -sf http://127.0.0.1:8888/ && echo || echo " not ready on :8888"

echo ""
echo "=== Argo CD Application ==="
kubectl get application playground -n argocd 2>/dev/null || echo " not created yet (wait for gitlab_init.sh)"

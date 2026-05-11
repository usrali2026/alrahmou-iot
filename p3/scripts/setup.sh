#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Running full Part 3 setup"

if ! command -v docker >/dev/null 2>&1 ||
   ! command -v kubectl >/dev/null 2>&1 ||
   ! command -v k3d >/dev/null 2>&1; then
  "${SCRIPT_DIR}/install.sh"
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed, but it is not available for the current user session."
  echo "Log out and log back in, then run this script again."
  exit 1
fi

"${SCRIPT_DIR}/cluster.sh"
"${SCRIPT_DIR}/deploy-argocd.sh"
"${SCRIPT_DIR}/deploy-app.sh"

echo ""
echo "======================================="
echo "Setup complete"
echo "======================================="
echo ""
echo "Application:"
echo "http://localhost:8888"
echo ""
echo "ArgoCD UI:"
echo "http://localhost:8080"
echo ""

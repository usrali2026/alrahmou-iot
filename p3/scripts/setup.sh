#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Running full Part 3 setup"

"${SCRIPT_DIR}/install.sh"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed, but it is not available for the current user session."
  echo "Log out and log back in, then run this script again."
  exit 1
fi

"${SCRIPT_DIR}/cluster.sh"
"${SCRIPT_DIR}/deploy-argocd.sh"
"${SCRIPT_DIR}/deploy-app.sh"

echo "==> Setup complete"
echo "==> Application: http://localhost:8888"

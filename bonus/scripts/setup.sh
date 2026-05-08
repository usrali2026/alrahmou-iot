#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Running full bonus setup"

missing_tools=()
for tool in docker kubectl k3d helm jq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    missing_tools+=("${tool}")
  fi
done

if (( ${#missing_tools[@]} > 0 )); then
  echo "==> Missing tools: ${missing_tools[*]}"
  "${SCRIPT_DIR}/install.sh"
else
  echo "==> Required tools are already installed"
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed, but it is not available for the current user session."
  echo "Your user may need a fresh login session for the docker group to apply."
  echo "Log out and log back in, then run this script again."
  exit 1
fi

"${SCRIPT_DIR}/cluster.sh"
"${SCRIPT_DIR}/deploy-argocd.sh"
"${SCRIPT_DIR}/deploy-gitlab.sh"
"${SCRIPT_DIR}/seed-gitlab.sh"
"${SCRIPT_DIR}/deploy-app.sh"

echo "==> Bonus setup complete"
echo "==> Application: http://localhost:8888"
echo "==> GitLab UI: kubectl -n gitlab port-forward svc/gitlab-webservice-default 8081:8181"

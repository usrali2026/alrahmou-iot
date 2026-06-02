#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"

show_usage() {
  cat <<'EOF'
Usage: setup.sh [--install-only]

Default flow:
  1) Run install.sh (creates cluster, GitLab, ArgoCD, prints credentials once)

Note: GitLab, the app, and Argo CD are exposed via k3d port maps for host browser access:
  http://gitlab.localhost:8181  http://localhost:8888/  https://localhost:8080/

Options:
  --install-only  Same as default (install + summary from gitlab_init.sh)
  -h, --help      Show this help
EOF
}

mode="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-only)
      mode="install"
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_usage >&2
      exit 2
      ;;
  esac
  shift
done

echo "[setup] Running install flow..."
bash "$INSTALL_SCRIPT"
echo "[setup] Done."

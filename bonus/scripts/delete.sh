#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="iot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BONUS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

show_usage() {
  cat <<EOF
Usage: delete.sh [-y]

Delete the bonus k3d cluster '${CLUSTER_NAME}' and free local port 8080 if in use.

Options:
  -y, --yes   Skip confirmation prompt
  -h, --help  Show this help

Re-install afterward:
  cd ${BONUS_ROOT}
  bash scripts/setup.sh
EOF
}

confirm=yes
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) confirm=no ;;
    -h|--help) show_usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      show_usage >&2
      exit 2
      ;;
  esac
  shift
done

if ! command -v k3d &>/dev/null; then
  echo "[delete] k3d not found; nothing to delete."
  exit 0
fi

if ! k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "[delete] No k3d cluster '${CLUSTER_NAME}' — already removed."
  exit 0
fi

if [[ "${confirm}" == "yes" ]]; then
  read -r -p "Delete k3d cluster '${CLUSTER_NAME}'? [y/N] " answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "[delete] Aborted."
    exit 0
  fi
fi

# Free port 8080 from stale kubectl port-forwards (legacy setup)
pids=$(ss -ltnp "( sport = :8080 )" 2>/dev/null \
  | awk -F'pid=' '/kubectl/ {print $2}' | awk -F',' '{print $1}' | sort -u || true)
if [[ -n "${pids}" ]]; then
  echo "[delete] Stopping kubectl port-forward on :8080 (PID(s): ${pids})"
  kill ${pids} 2>/dev/null || true
fi
rm -f "${SCRIPT_DIR}/.argocd-port-forward.pid" "${SCRIPT_DIR}/.gitlab-port-forward.pid"

echo "[delete] Deleting k3d cluster '${CLUSTER_NAME}'..."
k3d cluster delete "${CLUSTER_NAME}"

echo "[delete] Done. Cluster '${CLUSTER_NAME}' removed."

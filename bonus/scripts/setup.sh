#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"
ARGOCD_FORWARD_PID_FILE="${SCRIPT_DIR}/.argocd-port-forward.pid"
GITLAB_FORWARD_PID_FILE="${SCRIPT_DIR}/.gitlab-port-forward.pid"
ROOT_PASSWORD=""

cleanup_port() {
  local port="$1"
  local pids
  pids=$(ss -ltnp "( sport = :${port} )" 2>/dev/null | awk -F'pid=' '/users:\(\("/ {print $2}' | awk -F',' '{print $1}' | sort -u || true)

  if [[ -n "${pids}" ]]; then
    echo "[setup] Freeing port ${port} from PID(s): ${pids}"
    kill ${pids} 2>/dev/null || true
    sleep 1
  fi
}

cleanup_ports() {
  # Free 8080 (ArgoCD) and 8181 (GitLab) managed by this script
  # Port 8888 (app) is managed by k3d, we don't touch it
  cleanup_port 8080
  cleanup_port 8181
}

start_argocd_forward() {
  if [[ -f "${ARGOCD_FORWARD_PID_FILE}" ]]; then
    local old_pid
    old_pid=$(cat "${ARGOCD_FORWARD_PID_FILE}" 2>/dev/null || true)
    if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
      echo "[setup] ArgoCD port-forward already running (PID ${old_pid})."
      return 0
    fi
  fi

  echo "[setup] Starting ArgoCD port-forward on https://localhost:8080 ..."
  nohup kubectl port-forward svc/argocd-server -n argocd 8080:443 > /tmp/argocd-port-forward.log 2>&1 &
  local pf_pid=$!
  echo "$pf_pid" > "${ARGOCD_FORWARD_PID_FILE}"
  sleep 1
  echo "[setup] ArgoCD URL: https://localhost:8080"
}

start_gitlab_forward() {
  if [[ -f "${GITLAB_FORWARD_PID_FILE}" ]]; then
    local old_pid
    old_pid=$(cat "${GITLAB_FORWARD_PID_FILE}" 2>/dev/null || true)
    if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
      echo "[setup] GitLab port-forward already running (PID ${old_pid})."
      return 0
    fi
  fi

  echo "[setup] Starting GitLab port-forward on http://localhost:8181 ..."
  nohup kubectl port-forward svc/gitlab-webservice-default -n gitlab 8181:8181 > /tmp/gitlab-port-forward.log 2>&1 &
  local pf_pid=$!
  echo "$pf_pid" > "${GITLAB_FORWARD_PID_FILE}"
  sleep 2
  echo "[setup] GitLab URL: http://localhost:8181"
}

get_root_password() {
  ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
    -n gitlab \
    -o jsonpath='{.data.password}' | base64 -d)
}

print_bonus_ready() {
  echo ""
  echo "══════════════════════════════════════════════════════════════════"
  echo " Bonus ready"
  echo " GitLab    : http://localhost:8181  (root + password below)"
  echo " App       : http://localhost:8888/"
  echo " Argo CD   : https://localhost:8080/"
  echo "══════════════════════════════════════════════════════════════════"
  echo ""
  echo " Root password: ${ROOT_PASSWORD}"
  echo ""
}

show_usage() {
  cat <<'EOF'
Usage: setup.sh [--install-only]

Default flow:
  1) Cleanup ports 8080, 8181 (managed by this script)
  2) Run install.sh (creates cluster, GitLab, ArgoCD)
  3) Start port-forwards for GitLab (8181) and ArgoCD (8080)
  4) Fetch root password and print summary with URLs

Note: Port 8888 (app) is managed by k3d automatically.

Options:
  --install-only  Run install.sh only (skip port-forwards and summary)
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

run_install() {
  echo "[setup] Running install flow..."
  bash "$INSTALL_SCRIPT"
}

case "$mode" in
  install)
    cleanup_ports
    run_install
    ;;
  all)
    cleanup_ports
    start_gitlab_forward
    run_install
    get_root_password
    start_argocd_forward
    print_bonus_ready
    ;;
esac

echo "[setup] Done."

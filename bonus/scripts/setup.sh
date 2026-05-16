#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log(){ echo -e "\n==> $1"; }

run(){
  log "$1"
  bash "${ROOT_DIR}/$1"
}

check_kube(){
  log "Checking Kubernetes cluster"

  if ! kubectl cluster-info >/dev/null 2>&1; then
    log "Cluster missing → rebuilding"
    run cluster.sh
  else
    log "Cluster found → re-applying deterministic setup"
    run cluster.sh
  fi
}

wait_ns(){
  local ns=$1
  log "Waiting namespace: $ns"

  for i in {1..60}; do
    kubectl get ns "$ns" >/dev/null 2>&1 && return 0
    sleep 2
  done

  echo "Namespace $ns failed" && exit 1
}

get_gitlab_url(){
  if kubectl get svc -n gitlab gitlab-webservice-default >/dev/null 2>&1; then
    echo "http://localhost:8181"
  else
    echo "GitLab service not ready"
  fi
}

get_gitlab_password(){
  kubectl get secret -n gitlab gitlab-root-password \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "N/A"
}

echo "==> FULL 42 BONUS (SELF-HEALING MODE)"

check_kube

wait_ns argocd
wait_ns gitlab
wait_ns dev

run deploy-argocd.sh
run deploy-gitlab.sh

run wait-ready.sh
run seed-gitlab.sh
run deploy-app.sh

GITLAB_URL="$(get_gitlab_url)"
GITLAB_PASSWORD="$(get_gitlab_password)"

echo ""
echo "======================================="
echo "✔ BONUS READY (SELF-HEALING)"
echo "======================================="
echo ""

echo "🔵 ArgoCD UI"
echo "  http://localhost:8080"
echo ""

echo "🟣 Application (wil-playground)"
echo "  http://localhost:8888"
echo ""

echo "🟡 GitLab UI"
echo ""
echo "  Access URL:"
echo "  $GITLAB_URL"
echo ""

echo "🔐 GitLab login"
echo "  username: root"
echo "  password: $GITLAB_PASSWORD"
echo ""

echo "  If password is empty or changed:"
echo "    kubectl exec -it -n gitlab deploy/gitlab-toolbox -- \\"
echo "      gitlab-rake \"gitlab:password:reset[root]\""
echo ""

echo "======================================="

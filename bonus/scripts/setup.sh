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
  kubectl cluster-info >/dev/null 2>&1 || {
    log "Cluster missing → rebuilding"
    run cluster.sh
    return
  }
  log "Cluster found → rebuilding"
  run cluster.sh
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

echo ""
echo "======================================="
echo "✔ BONUS READY (SELF-HEALING)"
echo "======================================="
echo "ArgoCD: http://localhost:8080"
echo "GitLab:  http://localhost:8181"
echo "App:     http://localhost:8888"

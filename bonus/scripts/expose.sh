#!/usr/bin/env bash
set -euo pipefail

stop_existing(){
  local pid_file=$1
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$pid_file"
  fi
}

start_forward(){
  local namespace=$1
  local service=$2
  local local_port=$3
  local service_port=$4
  local name=$5
  local pid_file="/tmp/${name}-pf.pid"
  local log_file="/tmp/${name}-pf.log"

  stop_existing "$pid_file"

  echo "==> Starting ${name} port-forward on http://127.0.0.1:${local_port}"
  kubectl -n "$namespace" port-forward "svc/${service}" "${local_port}:${service_port}" >"$log_file" 2>&1 &
  echo $! > "$pid_file"
}

start_forward argocd argocd-server 8080 80 argocd
start_forward gitlab gitlab-webservice-default 8181 8181 gitlab

sleep 5

echo "==> Argo CD available at http://127.0.0.1:8080"
echo "==> GitLab available at http://127.0.0.1:8181"

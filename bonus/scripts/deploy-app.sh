#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Deploying app via ArgoCD"

kubectl apply -f "${REPO_ROOT}/confs/app.yaml"

echo "==> Waiting app"

for i in {1..120}; do
  if kubectl -n dev get deployment wil-playground >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

kubectl wait --for=condition=available deployment/wil-playground \
  -n dev --timeout=600s

echo "==> App ready http://localhost:8888"

#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Deploying ArgoCD Application"

kubectl apply -f "${REPO_ROOT}/confs/app.yaml"

echo "==> Waiting for ArgoCD to create wil-playground deployment"
for _ in {1..60}; do
  if kubectl get deployment/wil-playground -n dev >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

if ! kubectl get deployment/wil-playground -n dev >/dev/null 2>&1; then
  echo "wil-playground deployment was not created within 300 seconds."
  echo "Check Argo CD application status with: kubectl get application wil-app -n argocd -o wide"
  exit 1
fi

echo "==> Waiting for wil-playground deployment"
kubectl wait --for=condition=available \
  deployment/wil-playground -n dev --timeout=300s

echo "==> wil-playground is available at http://localhost:8888"

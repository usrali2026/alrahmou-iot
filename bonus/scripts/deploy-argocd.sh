#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Argo CD"

kubectl apply --server-side --force-conflicts -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for Argo CD"
kubectl wait --for=condition=available \
  deployment/argocd-server -n argocd --timeout=300s

echo "==> Exposing Argo CD UI"

kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort"}}'

echo "==> Argo CD password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo

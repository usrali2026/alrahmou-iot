#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Argo CD"

kubectl apply --server-side --force-conflicts -n argocd -f \
https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for Argo CD"
kubectl wait --for=condition=available \
deployment/argocd-server -n argocd --timeout=300s

echo "==> Exposing Argo CD UI at http://localhost:8080"

kubectl -n argocd patch configmap argocd-cmd-params-cm \
  --type=merge \
  -p='{"data":{"server.insecure":"true"}}' >/dev/null

kubectl patch svc argocd-server -n argocd \
  --type=json \
  -p='[
    {"op":"replace","path":"/spec/type","value":"NodePort"},
    {"op":"add","path":"/spec/ports/0/nodePort","value":30880}
  ]' >/dev/null

kubectl rollout restart deploy/argocd-server -n argocd >/dev/null
kubectl rollout status deploy/argocd-server -n argocd --timeout=300s

echo "==> Argo CD password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo

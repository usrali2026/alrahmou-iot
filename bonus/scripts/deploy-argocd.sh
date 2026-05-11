#!/usr/bin/env bash
set -euo pipefail

NS="argocd"

echo "==> Installing Argo CD (self-healing Helm install)"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Adding Argo CD Helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "==> Installing Argo CD (primary attempt)"

helm upgrade --install argocd argo/argo-cd \
  -n "$NS" \
  --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30880 \
  --set server.service.nodePortHttps=30443 \
  --set configs.params.server\\.insecure=true \
  --wait \
  --timeout 10m || {

    echo "⚠ Primary install failed → retrying safe mode"

    helm upgrade --install argocd argo/argo-cd \
      -n "$NS" \
      --wait \
      --timeout 15m
}

echo "==> Waiting for Argo CD server"
kubectl rollout status deploy/argocd-server -n "$NS" --timeout=300s

echo "==> Exposing Argo CD UI on http://localhost:8080"
kubectl -n "$NS" patch configmap argocd-cmd-params-cm \
  --type=merge \
  -p='{"data":{"server.insecure":"true"}}' >/dev/null

kubectl -n "$NS" patch svc argocd-server \
  --type=json \
  -p='[
    {"op":"replace","path":"/spec/type","value":"NodePort"},
    {"op":"add","path":"/spec/ports/0/nodePort","value":30880}
  ]' >/dev/null

kubectl rollout restart deploy/argocd-server -n "$NS" >/dev/null
kubectl rollout status deploy/argocd-server -n "$NS" --timeout=300s

echo "==> Argo CD ready"
echo "UI: http://localhost:8080"

echo "==> Admin password:"
kubectl -n "$NS" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

echo

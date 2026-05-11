#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating k3d cluster (deterministic + DNS stable)"

k3d cluster delete iot 2>/dev/null || true

k3d cluster create iot \
  --servers 1 \
  --agents 1 \
  -p "8888:30080@loadbalancer" \
  -p "8080:30880@loadbalancer" \
  -p "8181:30881@loadbalancer" \
  --k3s-arg "--resolv-conf=/etc/resolv.conf@server:*"

echo "==> Creating namespaces"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

echo "==> Cluster ready"
kubectl get ns

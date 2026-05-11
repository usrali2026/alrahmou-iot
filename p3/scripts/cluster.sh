#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating k3d cluster"

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not available for the current user."
  echo "Run scripts/install.sh, then log out and log back in before running this script."
  exit 1
fi

k3d cluster delete iot 2>/dev/null || true

k3d cluster create iot \
  -p "8888:30080@loadbalancer" \
  -p "8080:30880@loadbalancer" \
  --servers 1 \
  --agents 1

echo "==> Creating namespaces"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

kubectl get ns

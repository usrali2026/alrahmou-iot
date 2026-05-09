#!/usr/bin/env bash
set -euo pipefail

echo "==> Cluster health check"

check(){
  kubectl get pods -A --no-headers | grep -E "CrashLoopBackOff|Error" && {
    echo "❌ Cluster unhealthy"
    kubectl get pods -A
    exit 1
  } || true
}

for i in {1..10}; do
  check
  sleep 5
done

echo "==> Cluster stable"

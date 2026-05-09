#!/usr/bin/env bash
set -euo pipefail

echo "==> Starting GitLab port-forward"

kubectl -n gitlab port-forward svc/gitlab-webservice-default 8181:8181 >/tmp/gitlab-pf.log 2>&1 &
echo $! > /tmp/gitlab-pf.pid

sleep 5

echo "==> GitLab available at http://127.0.0.1:8181"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-GitLabRoot42!}"

echo "==> Adding official GitLab Helm repository"
helm repo add gitlab https://charts.gitlab.io >/dev/null 2>&1 || true
helm repo update

if [[ -z "${GITLAB_CHART_VERSION:-}" ]]; then
  GITLAB_CHART_VERSION="$(helm search repo gitlab/gitlab -o json | jq -r '.[0].version')"
fi

if [[ -z "${GITLAB_CHART_VERSION}" || "${GITLAB_CHART_VERSION}" == "null" ]]; then
  echo "Could not discover the latest GitLab chart version from the official Helm repo."
  exit 1
fi

echo "==> Installing GitLab chart ${GITLAB_CHART_VERSION}"

kubectl create namespace gitlab || true
kubectl -n gitlab create secret generic gitlab-root-password \
  --from-literal=password="${ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --version "${GITLAB_CHART_VERSION}" \
  --values "${REPO_ROOT}/helm/gitlab-values.yaml" \
  --set gitlab.migrations.initialRootPassword.secret=gitlab-root-password \
  --set gitlab.migrations.initialRootPassword.key=password \
  --timeout 25m

echo "==> Waiting for GitLab webservice"
kubectl -n gitlab rollout status deployment/gitlab-webservice-default --timeout=25m

echo "==> Waiting for GitLab toolbox"
kubectl -n gitlab rollout status deployment/gitlab-toolbox --timeout=25m

echo "==> GitLab is installed in namespace gitlab"

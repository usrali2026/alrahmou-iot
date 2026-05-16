#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ensure_gitlab_repo_creds() {
  local token_output token_username token_password token_name

  token_name="argocd-$(date +%s)"
  token_output="$(kubectl -n gitlab exec -i deploy/gitlab-toolbox -- sh -lc 'gitlab-rails runner -' <<RUBY
project = Project.find_by_full_path('root/iot-bonus')
token = project.deploy_tokens.create!(name: '${token_name}', username: '${token_name}', read_repository: true)
puts token.username
puts token.token
RUBY
)"

  token_username="$(printf '%s\n' "${token_output}" | sed -n '1p')"
  token_password="$(printf '%s\n' "${token_output}" | sed -n '2p')"

  kubectl -n argocd delete secret gitlab-repo-creds --ignore-not-found >/dev/null

  kubectl -n argocd create secret generic gitlab-repo-creds \
    --from-literal=url="http://gitlab-webservice-default.gitlab.svc.cluster.local:8181" \
    --from-literal=username="${token_username}" \
    --from-literal=password="${token_password}" >/dev/null

  kubectl -n argocd label secret gitlab-repo-creds \
    argocd.argoproj.io/secret-type=repo-creds \
    --overwrite >/dev/null
}

echo "==> Deploying app via ArgoCD"

ensure_gitlab_repo_creds

kubectl apply -f "${REPO_ROOT}/confs/app.yaml"

kubectl -n argocd annotate application wil-app \
  argocd.argoproj.io/refresh=hard \
  --overwrite >/dev/null

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

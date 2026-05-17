#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="gitlab"
PROJECT="${1:-root/iot-bonus}"
LOCAL_REPO="${2:-$ROOT_DIR}"

echo "==> Using local repo: $LOCAL_REPO"

if [[ ! -d "$LOCAL_REPO" ]]; then
  echo "Local repo path not found: $LOCAL_REPO" >&2
  exit 1
fi

echo "==> Waiting for toolbox pod"
kubectl -n "$NS" wait --for=condition=available deployment/gitlab-toolbox --timeout=300s

echo "==> Ensure project exists and create deploy token"
tmp_rb=$(mktemp)
cat > "$tmp_rb" <<'RUBY'
project_path = ENV['PROJECT_PATH']
user = User.find_by_username('root')
raise 'root user not found' unless user

project = Project.find_by_full_path(project_path)
if project.nil?
  project = Projects::CreateService.new(
    user,
    {
      name: project_path.split('/').last,
      path: project_path.split('/').last,
      namespace_id: User.find_by_username('root').namespace.id,
      visibility_level: Gitlab::VisibilityLevel::PUBLIC,
      initialize_with_readme: true
    }
  ).execute
end

# If main is protected, remove protection so we can push
begin
  project.protected_branches.where(name: 'main').each { |b| b.destroy }
rescue StandardError
  # ignore if model/association not present
end

token_name = "argocd-#{Time.now.to_i}"
tok = project.deploy_tokens.create!(name: token_name, username: token_name, read_repository: true)
pat = PersonalAccessToken.new(
  user: user,
  name: "auto-push-#{Time.now.to_i}",
  scopes: ['write_repository'],
  expires_at: 30.days.from_now
)
pat.save!
puts "DEPLOY_USER=#{tok.username}"
puts "DEPLOY_TOKEN=#{tok.token}"
puts "PUSH_USER=root"
puts "PUSH_TOKEN=#{pat.token}"
RUBY

TOOLBOX_POD=$(kubectl -n "$NS" get pod -l app=toolbox -o jsonpath='{.items[0].metadata.name}')
kubectl -n "$NS" cp "$tmp_rb" "$TOOLBOX_POD:/tmp/auto.rb" -c toolbox >/dev/null
raw_token_out=$(kubectl -n "$NS" exec -c toolbox "$TOOLBOX_POD" -- env PROJECT_PATH="${PROJECT}" gitlab-rails runner /tmp/auto.rb)
rm -f "$tmp_rb" || true

DEPLOY_USER="$(printf '%s' "$raw_token_out" | sed -n 's/^DEPLOY_USER=//p' | tail -n1)"
DEPLOY_TOKEN="$(printf '%s' "$raw_token_out" | sed -n 's/^DEPLOY_TOKEN=//p' | tail -n1)"
PUSH_USER="$(printf '%s' "$raw_token_out" | sed -n 's/^PUSH_USER=//p' | tail -n1)"
PUSH_TOKEN="$(printf '%s' "$raw_token_out" | sed -n 's/^PUSH_TOKEN=//p' | tail -n1)"

if [[ -z "$DEPLOY_USER" || -z "$DEPLOY_TOKEN" || -z "$PUSH_USER" || -z "$PUSH_TOKEN" ]]; then
  echo "Failed to obtain tokens" >&2
  printf '%s\n' "raw output:" "$raw_token_out" >&2
  exit 1
fi

echo "Deploy token created: $DEPLOY_USER"

url_host="localhost:8181"
project_path_escaped="${PROJECT}.git"

urlenc(){ python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"; }
PUSH_USER_ENC="$(urlenc "$PUSH_USER")"
PUSH_TOKEN_ENC="$(urlenc "$PUSH_TOKEN")"
push_url="http://${PUSH_USER_ENC}:${PUSH_TOKEN_ENC}@${url_host}/${PROJECT}.git"

echo "==> Preparing git repo"
pushd "$LOCAL_REPO" >/dev/null
if [[ ! -d .git ]]; then
  git init
  git add .
  git commit -m "initial" || true
fi

git remote remove origin 2>/dev/null || true
git remote add origin "$push_url"

echo "==> Pushing current branch to a new remote branch (avoid protected-main issues)"
local_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
remote_branch="auto-push-$(date +%s)"
echo "Local branch: $local_branch -> Remote branch: $remote_branch"
GIT_TERMINAL_PROMPT=0 git push origin "$local_branch:refs/heads/$remote_branch" || {
  echo "Push failed; attempting force push to $remote_branch"
  GIT_TERMINAL_PROMPT=0 git push --force origin "$local_branch:refs/heads/$remote_branch"
}

echo "==> Pushing tags (best-effort)"
GIT_TERMINAL_PROMPT=0 git push origin --tags || true
DEPLOY_BRANCH="$remote_branch"
popd >/dev/null

echo "==> Registering repo in ArgoCD as secret"
kubectl -n argocd delete secret gitlab-repo-creds --ignore-not-found >/dev/null || true
kubectl -n argocd create secret generic gitlab-repo-creds \
  --from-literal=url="http://gitlab-webservice-default.gitlab.svc.cluster.local:8181" \
  --from-literal=username="$DEPLOY_USER" \
  --from-literal=password="$DEPLOY_TOKEN" >/dev/null
kubectl -n argocd label secret gitlab-repo-creds argocd.argoproj.io/secret-type=repo-creds --overwrite >/dev/null

echo "==> Done. Repo pushed and ArgoCD secret created."
echo "Repo URL: http://$url_host/${PROJECT}.git"
echo "Deploy user: $DEPLOY_USER"

# If we pushed to a branch other than main, update ArgoCD application to track it
if [[ -n "${DEPLOY_BRANCH:-}" ]]; then
  echo "==> Updating ArgoCD application to use branch: $DEPLOY_BRANCH"
  kubectl -n argocd patch application wil-app --type merge -p "{\"spec\":{\"source\":{\"targetRevision\":\"${DEPLOY_BRANCH}\"}}}"
  kubectl -n argocd annotate application wil-app argocd.argoproj.io/refresh=hard --overwrite >/dev/null
fi

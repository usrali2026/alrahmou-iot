#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOKEN="${GITLAB_BOOTSTRAP_TOKEN:-glpat-iot-bonus-token-424242}"

echo "==> Creating local GitLab project root/iot-bonus"

DEPLOYMENT_CONTENT="$(sed 's/\\/\\\\/g; s/"/\\"/g' "${REPO_ROOT}/gitlab-seed/deployment.yaml")"
SERVICE_CONTENT="$(sed 's/\\/\\\\/g; s/"/\\"/g' "${REPO_ROOT}/gitlab-seed/service.yaml")"

kubectl -n gitlab exec -i deployment/gitlab-toolbox -- gitlab-rails runner - <<RUBY
user = User.find_by_username!("root")

project = Project.find_by_full_path("root/iot-bonus")
unless project
  project = Projects::CreateService.new(
    user,
    {
    name: "iot-bonus",
    path: "iot-bonus",
    namespace_id: user.namespace.id,
    visibility_level: Gitlab::VisibilityLevel::PUBLIC,
    initialize_with_readme: false
    }
  ).execute
  raise project.errors.full_messages.join(", ") unless project.persisted?
end

unless project.repository_exists?
  actions = [
    {
      action: "create",
      file_path: "confs/deployment.yaml",
      content: "${DEPLOYMENT_CONTENT}"
    },
    {
      action: "create",
      file_path: "confs/service.yaml",
      content: "${SERVICE_CONTENT}"
    }
  ]

  params = {
    branch_name: "main",
    start_branch: nil,
    commit_message: "Initial local GitOps manifests",
    actions: actions
  }

  result = Commits::CreateService.new(project, user, params).execute

  raise result[:message].to_s unless result[:status] == :success
end

PersonalAccessToken.active.where(user: user, name: "iot-bonus-token").find_each(&:revoke!)
token = user.personal_access_tokens.build(
  name: "iot-bonus-token",
  scopes: [:api, :read_repository],
  expires_at: 1.year.from_now
)
token.set_token("${TOKEN}")
token.save!
RUBY

echo "==> Registering local GitLab repository in Argo CD"
kubectl -n argocd create secret generic repo-local-gitlab-iot-bonus \
  --from-literal=type=git \
  --from-literal=url=http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/root/iot-bonus.git \
  --from-literal=username=root \
  --from-literal=password="${TOKEN}" \
  --dry-run=client -o yaml |
  kubectl label -f - --local argocd.argoproj.io/secret-type=repository -o yaml |
  kubectl apply -f -

echo "==> Local GitLab project is ready"

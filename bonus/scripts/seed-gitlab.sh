#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Waiting for GitLab toolbox"
kubectl -n gitlab wait --for=condition=available deployment/gitlab-toolbox --timeout=900s

echo "==> Copying manifests into toolbox"
kubectl -n gitlab exec deploy/gitlab-toolbox -- sh -lc 'mkdir -p /tmp/iot-confs'
kubectl -n gitlab exec -i deploy/gitlab-toolbox -- sh -lc 'cat > /tmp/iot-confs/deployment.yaml' < "${REPO_ROOT}/confs/deployment.yaml"
kubectl -n gitlab exec -i deploy/gitlab-toolbox -- sh -lc 'cat > /tmp/iot-confs/service.yaml' < "${REPO_ROOT}/confs/service.yaml"

echo "==> Seeding root/iot-bonus project (idempotent)"
kubectl -n gitlab exec -i deploy/gitlab-toolbox -- sh -lc 'gitlab-rails runner -' <<'RUBY'
user = User.find_by_username('root')
raise 'root user not found' unless user

project = Project.find_by_full_path('root/iot-bonus')
if project.nil?
  project = Projects::CreateService.new(
    user,
    {
      name: 'iot-bonus',
      path: 'iot-bonus',
      namespace_id: user.namespace.id,
      visibility_level: Gitlab::VisibilityLevel::PUBLIC,
      initialize_with_readme: true
    }
  ).execute

  if project.nil? || project.errors.any?
    raise "project creation failed: #{project&.errors&.full_messages&.join(', ')}"
  end
end

branch = project.default_branch.presence || 'main'

def upsert_file(project, user, branch, path, content, message)
  blob = project.repository.blob_at_branch(branch, path)

  if blob
    project.repository.update_file(
      user,
      path,
      content,
      branch_name: branch,
      message: message
    )
  else
    project.repository.create_file(
      user,
      path,
      content,
      branch_name: branch,
      message: message
    )
  end
end

deployment_yaml = File.read('/tmp/iot-confs/deployment.yaml')
service_yaml = File.read('/tmp/iot-confs/service.yaml')

upsert_file(project, user, branch, 'confs/deployment.yaml', deployment_yaml, 'chore: sync deployment manifest')
upsert_file(project, user, branch, 'confs/service.yaml', service_yaml, 'chore: sync service manifest')

puts "Seeded project #{project.full_path} on branch #{branch}"
RUBY

echo "==> Seed complete"

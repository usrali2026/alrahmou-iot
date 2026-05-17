#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="gitlab"
TOOLBOX="deploy/gitlab-toolbox"

PROJECT="${1:-root/iot-bonus}"
LOCAL_DIR="${2:-$ROOT_DIR/confs}"

if [[ ! -d "$LOCAL_DIR" ]]; then
  echo "Local directory not found: $LOCAL_DIR" >&2
  exit 1
fi

echo "==> Waiting for toolbox pod"
kubectl -n "$NS" wait --for=condition=available deployment/gitlab-toolbox --timeout=300s

echo "==> Copying files from $LOCAL_DIR to toolbox"
kubectl -n "$NS" exec -c toolbox deploy/gitlab-toolbox -- sh -lc 'mkdir -p /tmp/repo-confs'
tar -C "$LOCAL_DIR" -czf - . | kubectl -n "$NS" exec -i -c toolbox deploy/gitlab-toolbox -- tar -C /tmp/repo-confs -xzf -

echo "==> Creating/updating project ${PROJECT} and syncing files"

kubectl -n "$NS" exec -i -c toolbox deploy/gitlab-toolbox -- gitlab-rails runner - <<RUBY
project_path = "${PROJECT}"
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

files = Dir.glob('/tmp/repo-confs/**', File::FNM_DOTMATCH).select { |f| File.file?(f) }
files.each do |f|
  rel = f.sub(%r{^/tmp/repo-confs/?}, '')
  content = File.read(f)
  upsert_file(project, user, branch, rel, content, "chore: sync #{rel}")
end

puts "Synced #{files.length} files to #{project.full_path}"
RUBY

echo "==> Done"

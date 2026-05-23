#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  gitlab_init.sh
#
#  Run after GitLab Helm install. Does:
#    1. Wait for GitLab to fully respond
#    2. Retrieve the initial root password
#    3. Create a Personal Access Token via rails runner
#    4. Create the 'iot' project via GitLab API
#    5. Push deployment.yaml into the project
#    6. Create the ArgoCD repository credential secret
#    7. Apply the ArgoCD Application manifest
#
#  Internal GitLab URL (used by ArgoCD within the cluster):
#    http://gitlab-webservice-default.gitlab.svc.cluster.local:8181
#  External GitLab URL (used by browsers / git on the host):
#    http://gitlab.local:8181
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFS_DIR="${SCRIPT_DIR}/../confs"

# Accessible from within the K3d cluster (ArgoCD, pods)
GITLAB_INTERNAL="http://gitlab-webservice-default.gitlab.svc.cluster.local:8181"
# Accessible from the host machine
GITLAB_EXTERNAL="http://gitlab.local:8181"

PROJECT_NAME="iot"
PROJECT_PATH="root%2F${PROJECT_NAME}"   # URL-encoded "root/iot"
ARGOCD_NS="argocd"
DEV_NS="dev"

# ── Helper: wait for GitLab web to respond ────────────────────────────────────
wait_for_gitlab() {
  echo "[gitlab_init] Waiting for GitLab to become responsive (fast checks)..."
  # First, wait for internal endpoints to appear (fast, avoids host DNS issues)
  local max_checks=40
  local delay=5
  local i=0

  while ! kubectl get endpoints gitlab-webservice-default -n gitlab -o jsonpath='{.subsets}' 2>/dev/null | grep -q .; do
    i=$((i+1))
    if [ "${i}" -ge "${max_checks}" ]; then
      echo "[gitlab_init] INFO: internal endpoints not ready after $((max_checks*delay))s, falling back to external health check"
      break
    fi
    echo "[gitlab_init] Waiting for internal endpoints... (${i}/${max_checks})"
    sleep ${delay}
  done

  # If endpoints exist, try curling the internal URL from a temporary pod (fast and reliable)
  if kubectl get endpoints gitlab-webservice-default -n gitlab -o jsonpath='{.subsets}' 2>/dev/null | grep -q .; then
    echo "[gitlab_init] Internal endpoints present — probing internal health endpoint..."
    if kubectl run --rm --attach --restart=Never -n gitlab gitlab-curl --image=curlimages/curl --command -- sh -c "curl -sf --max-time 5 '${GITLAB_INTERNAL}/-/health'" >/dev/null 2>&1; then
      echo "[gitlab_init] GitLab internal health OK."
      return 0
    else
      echo "[gitlab_init] Internal probe failed; will try external host check as fallback."
    fi
  fi

  # Fallback to external host health check (shorter sleep to speed up)
  i=0
  max_checks=40
  delay=5
  until curl -sf --max-time 5 "${GITLAB_EXTERNAL}/-/health" >/dev/null 2>&1; do
    i=$((i+1))
    if [ "${i}" -ge "${max_checks}" ]; then
      echo "[gitlab_init] ERROR: GitLab did not respond after $((max_checks*delay))s (external check)."
      exit 1
    fi
    echo "[gitlab_init] External attempt ${i}/${max_checks} — retrying in ${delay}s..."
    sleep ${delay}
  done
  echo "[gitlab_init] GitLab is up (external check)."
}

# ── Step 1: Initial root password ─────────────────────────────────────────────
get_root_password() {
  echo "[gitlab_init] Fetching initial root password..."
  ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
    -n gitlab \
    -o jsonpath='{.data.password}' | base64 -d)
  echo "[gitlab_init] Root password retrieved."
}

# ── Step 2: Personal Access Token via Rails console ───────────────────────────
create_pat() {
  echo "[gitlab_init] Creating Personal Access Token via gitlab-rails runner..."
  echo "[gitlab_init] (This may take 60–90 seconds while Rails loads.)"
  # Ensure the toolbox deployment is available before exec (faster than retrying exec failures)
  echo "[gitlab_init] Waiting for gitlab-toolbox deployment to be available..."
  kubectl wait --for=condition=available --timeout=300s deployment/gitlab-toolbox -n gitlab || true

  PAT=$(kubectl exec -n gitlab deploy/gitlab-toolbox -- \
    gitlab-rails runner \
    "
      user = User.find_by_username('root')
      existing = user.personal_access_tokens.find_by_name('argocd-token')
      existing.revoke! if existing
      token = user.personal_access_tokens.create!(
        name: 'argocd-token',
        scopes: [:api, :read_repository, :write_repository],
        expires_at: 1.year.from_now
      )
      puts token.token
    " 2>/dev/null | tail -1)

  if [ -z "${PAT}" ]; then
    echo "[gitlab_init] ERROR: Failed to create PAT."
    exit 1
  fi
  echo "[gitlab_init] PAT created."
}

# ── Step 3: Create the GitLab project ────────────────────────────────────────
create_project() {
  echo "[gitlab_init] Creating GitLab project '${PROJECT_NAME}'..."

  RESPONSE=$(curl -sf --request POST \
    "${GITLAB_EXTERNAL}/api/v4/projects" \
    --header "PRIVATE-TOKEN: ${PAT}" \
    --header "Content-Type: application/json" \
    --data "{
      \"name\": \"${PROJECT_NAME}\",
      \"path\": \"${PROJECT_NAME}\",
      \"visibility\": \"public\",
      \"default_branch\": \"main\",
      \"initialize_with_readme\": false
    }" 2>/dev/null || true)

  # Ignore "already exists" (409)
  if echo "${RESPONSE}" | grep -q '"id"'; then
    echo "[gitlab_init] Project '${PROJECT_NAME}' created."
  elif echo "${RESPONSE}" | grep -q "has already been taken"; then
    echo "[gitlab_init] Project '${PROJECT_NAME}' already exists."
  else
    echo "[gitlab_init] WARNING: Unexpected project creation response:"
    echo "${RESPONSE}"
  fi
}

# ── Step 4: Push deployment.yaml to the project ───────────────────────────────
push_deployment() {
  echo "[gitlab_init] Pushing deployment.yaml to GitLab project..."
  # Prefer pushing via internal cluster endpoint using a temporary pod (bypasses host networking)
  if kubectl get svc gitlab-webservice-default -n gitlab >/dev/null 2>&1; then
    echo "[gitlab_init] Using internal GitLab endpoint (${GITLAB_INTERNAL}) to push file from cluster pod..."
    ENCODED=$(base64 -w 0 "${CONFS_DIR}/deployment.yaml")

    kubectl run --rm --attach --restart=Never -n gitlab gitlab-curl --image=curlimages/curl --command -- sh -c \
      "curl -sS --header \"PRIVATE-TOKEN: ${PAT}\" --header \"Content-Type: application/json\" --request POST \\\
        '${GITLAB_INTERNAL}/api/v4/projects/${PROJECT_PATH}/repository/files/deployment.yaml' \\\
        --data \"{\\\"branch\\\":\\\"main\\\",\\\"content\\\":\\\"${ENCODED}\\\",\\\"encoding\\\":\\\"base64\\\",\\\"commit_message\\\":\\\"Initial commit: wil42/playground:v1\\\"}\" -o /tmp/resp || true; cat /tmp/resp" \
      > /tmp/gitlab_push_out 2>&1 || true

    # If creation failed (e.g., file exists), attempt update
    if grep -q '201' /tmp/gitlab_push_out 2>/dev/null || grep -q '"file_path"' /tmp/gitlab_push_out 2>/dev/null; then
      echo "[gitlab_init] deployment.yaml pushed (created or updated via internal API)."
    else
      echo "[gitlab_init] Internal push didn't return expected response, attempting update via internal API..."
      kubectl run --rm --attach --restart=Never -n gitlab gitlab-curl --image=curlimages/curl --command -- sh -c \
        "curl -sS --header \"PRIVATE-TOKEN: ${PAT}\" --header \"Content-Type: application/json\" --request PUT \\\
          '${GITLAB_INTERNAL}/api/v4/projects/${PROJECT_PATH}/repository/files/deployment.yaml' \\\
          --data \"{\\\"branch\\\":\\\"main\\\",\\\"content\\\":\\\"${ENCODED}\\\",\\\"encoding\\\":\\\"base64\\\",\\\"commit_message\\\":\\\"Update deployment.yaml\\\"}\" -o /tmp/resp || true; cat /tmp/resp" \
        > /tmp/gitlab_push_out2 2>&1 || true
      if grep -q '"file_path"' /tmp/gitlab_push_out2 2>/dev/null; then
        echo "[gitlab_init] deployment.yaml updated via internal API."
      else
        echo "[gitlab_init] WARNING: internal API push/update returned unexpected response."
      fi
    fi
    # cleanup temp files
    rm -f /tmp/gitlab_push_out /tmp/gitlab_push_out2 || true
  else
    echo "[gitlab_init] Internal GitLab service not available; falling back to external API (may be slower or require host networking)."
    ENCODED=$(base64 -w 0 "${CONFS_DIR}/deployment.yaml")
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --request POST \
      "${GITLAB_EXTERNAL}/api/v4/projects/${PROJECT_PATH}/repository/files/deployment.yaml" \
      --header "PRIVATE-TOKEN: ${PAT}" \
      --header "Content-Type: application/json" \
      --data "{\
        \"branch\": \"main\",\
        \"content\": \"${ENCODED}\",\
        \"encoding\": \"base64\",\
        \"commit_message\": \"Initial commit: wil42/playground:v1\"\
      }") || true

    if [ "${HTTP_STATUS}" = "201" ]; then
      echo "[gitlab_init] deployment.yaml pushed (created)."
    elif [ "${HTTP_STATUS}" = "400" ]; then
      curl -sf --request PUT \
        "${GITLAB_EXTERNAL}/api/v4/projects/${PROJECT_PATH}/repository/files/deployment.yaml" \
        --header "PRIVATE-TOKEN: ${PAT}" \
        --header "Content-Type: application/json" \
        --data "{\
          \"branch\": \"main\",\
          \"content\": \"${ENCODED}\",\
          \"encoding\": \"base64\",\
          \"commit_message\": \"Update deployment.yaml\"\
        }" > /dev/null
      echo "[gitlab_init] deployment.yaml updated."
    else
      echo "[gitlab_init] WARNING: Unexpected HTTP ${HTTP_STATUS} when pushing file."
    fi
  fi
}

# ── Step 5: ArgoCD repository credential secret ───────────────────────────────
create_argocd_repo_secret() {
  echo "[gitlab_init] Creating ArgoCD repository credential secret..."

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-iot-repo
  namespace: ${ARGOCD_NS}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: ${GITLAB_INTERNAL}/root/${PROJECT_NAME}.git
  username: root
  password: "${PAT}"
  insecure: "true"
EOF

  echo "[gitlab_init] ArgoCD repo secret applied."
}

# ── Step 6: Harden GitLab instance settings ──────────────────────────────────
apply_security_settings() {
  echo "[gitlab_init] Disabling public sign-ups and Web IDE single-origin fallback..."

  cat > /tmp/gitlab-security-settings.json <<EOF
{
  "signup_enabled": false,
  "vscode_extension_marketplace_single_origin_fallback_enabled": false
}
EOF

  kubectl exec -n gitlab deploy/gitlab-toolbox -- \
    curl -sS --request PUT \
      --header "PRIVATE-TOKEN: ${PAT}" \
      --header "Content-Type: application/json" \
      --data @/tmp/gitlab-security-settings.json \
      "${GITLAB_INTERNAL}/api/v4/application/settings" >/dev/null

  rm -f /tmp/gitlab-security-settings.json

  echo "[gitlab_init] GitLab security settings updated."
}

# ── Step 7: Apply the ArgoCD Application ──────────────────────────────────────
apply_argocd_app() {
  echo "[gitlab_init] Applying ArgoCD Application..."
  kubectl apply -f "${CONFS_DIR}/argocd-app.yaml"
  echo "[gitlab_init] ArgoCD Application applied."
}

# ── Step 8: Summary ───────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo "──────────────────────────────────────────────────────────────────"
  echo " GitLab"
  echo "  URL      : ${GITLAB_EXTERNAL}"
  echo "   User     : root"
  echo "   Password : ${ROOT_PASSWORD}"
  echo "   Repo     : ${GITLAB_EXTERNAL}/root/${PROJECT_NAME}"
  echo ""
  echo " Clone (from host):"
  echo "  git clone http://root:${ROOT_PASSWORD}@gitlab.local:8181/root/${PROJECT_NAME}.git"
  echo ""
  echo " Version bump workflow (evaluation demo):"
  echo "   cd ${PROJECT_NAME}"
  echo "  sed -i 's/playground:v2/playground:v1/' deployment.yaml"
  echo "  git add deployment.yaml && git commit -m 'v1' && git push"
  echo "  # ArgoCD syncs automatically (≤3 min) → curl http://localhost:8888/"
  echo ""
  echo " ArgoCD Application:"
  echo "   kubectl get app playground -n argocd"
  echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "──────────────────────────────────────────────────────────────────"
}

# ── Main ─────────────────────────────────────────────────────────────────────
wait_for_gitlab
get_root_password
create_pat
create_project
push_deployment
create_argocd_repo_secret
apply_security_settings
apply_argocd_app
print_summary

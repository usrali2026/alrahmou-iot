#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Part 3 — install.sh
#  Idempotent: safe to re-run; skips steps that are already done.
#  Run as root (or with sudo).
#
#  Before first run, publish the GitOps manifest:
#    ./p3/scripts/push-gitops.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFS_DIR="${SCRIPT_DIR}/../confs"
CLUSTER_NAME="iot"
GITOPS_REPO="${GITOPS_REPO:-https://github.com/usrali2026/alrahmou-iot.git}"
APP_NAME="playground"

# Use the invoking user's kubeconfig when run via sudo.
setup_kubeconfig() {
  REAL_USER="${SUDO_USER:-${USER}}"
  if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
    export KUBECONFIG="/home/${REAL_USER}/.kube/config"
    mkdir -p "$(dirname "${KUBECONFIG}")"
    chown -R "${REAL_USER}:${REAL_USER}" "$(dirname "${KUBECONFIG}")"
  else
    export KUBECONFIG="${HOME}/.kube/config"
    mkdir -p "${HOME}/.kube"
  fi
}

# ── 1. Docker ─────────────────────────────────────────────────────────────────
install_docker() {
  echo "[install] Installing Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin

  systemctl enable --now docker

  REAL_USER="${SUDO_USER:-${USER}}"
  if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
    usermod -aG docker "${REAL_USER}"
    echo "[install] Added ${REAL_USER} to the docker group (re-login to take effect)."
  fi
}

# ── 2. kubectl ────────────────────────────────────────────────────────────────
install_kubectl() {
  echo "[install] Installing kubectl..."
  KUBE_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
  echo "[install] kubectl $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1 || true)"
}

# ── 3. K3d ───────────────────────────────────────────────────────────────────
install_k3d() {
  echo "[install] Installing K3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  echo "[install] K3d $(k3d version | head -1)"
}

# ── 4. K3d cluster ───────────────────────────────────────────────────────────
create_cluster() {
  echo "[install] Creating K3d cluster '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
    --port "8888:30888@loadbalancer" \
    --wait

  k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default
  echo "[install] Cluster nodes:"
  kubectl get nodes -o wide
}

ensure_cluster() {
  setup_kubeconfig

  if k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
    echo "[install] Cluster '${CLUSTER_NAME}' already exists."
    echo "[install] If curl :8888 fails, recreate: k3d cluster delete ${CLUSTER_NAME}"
    k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default
    return
  fi

  create_cluster
}

# ── 5. ArgoCD + namespaces ───────────────────────────────────────────────────
wait_argocd_ready() {
  echo "[install] Waiting for core Argo CD components (up to 5 min)..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server deployment/argocd-repo-server -n argocd
  kubectl wait --for=condition=ready --timeout=300s \
    pod -l app.kubernetes.io/name=argocd-application-controller -n argocd
}

wait_application_synced() {
  echo "[install] Waiting for Application/${APP_NAME} to sync (up to 5 min)..."
  local i sync health
  for i in $(seq 1 60); do
    sync=$(kubectl get application "${APP_NAME}" -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
    health=$(kubectl get application "${APP_NAME}" -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || true)
    if [ "${sync}" = "Synced" ] && [ "${health}" = "Healthy" ]; then
      echo "[install] Application synced and healthy."
      return 0
    fi
    sleep 5
  done

  echo "[install] WARN: Application not Synced/Healthy yet."
  kubectl get application "${APP_NAME}" -n argocd -o wide 2>/dev/null || true
  echo "[install] Ensure the GitOps repo has deployment.yaml under p3/confs:"
  echo "[install]   ${GITOPS_REPO}"
  echo "[install] Run: ./p3/scripts/push-gitops.sh"
  return 1
}

verify_app() {
  echo "[install] Checking http://localhost:8888/ ..."
  if curl -sf --max-time 10 http://localhost:8888/; then
    echo ""
    echo "[install] App responds on :8888."
    return 0
  fi
  echo "[install] WARN: No response on :8888 yet (pod may still be starting)."
  kubectl get pods -n dev 2>/dev/null || true
  return 1
}

install_argocd() {
  setup_kubeconfig

  echo "[install] Creating namespaces: argocd, dev..."
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace dev    --dry-run=client -o yaml | kubectl apply -f -

  echo "[install] Applying ArgoCD manifests..."
  kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  wait_argocd_ready

  echo "[install] Applying ArgoCD Application..."
  kubectl apply -f "${CONFS_DIR}/application.yaml"

  wait_application_synced || true
  verify_app || true

  REAL_USER="${SUDO_USER:-${USER}}"
  echo ""
  echo "──────────────────────────────────────────────────────"
  echo " KUBECONFIG: ${KUBECONFIG}"
  if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
    echo " (kubectl as ${REAL_USER} uses this file after sudo install)"
  fi
  echo ""
  echo " ArgoCD admin password:"
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo
  echo ""
  echo " App (open in browser — use http, port 8888):"
  echo "   http://localhost:8888/"
  echo "   curl http://127.0.0.1:8888/"
  echo ""
  echo " Argo CD UI is NOT on :8080 until you port-forward:"
  echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "   https://localhost:8080/  (user: admin, accept TLS warning)"
  echo ""
  echo " Or run: ./p3/scripts/access.sh"
  echo ""
  echo " Upgrade demo (in GitOps repo, then push):"
  echo "   sed -i 's/playground:v1/playground:v2/' p3/confs/deployment.yaml"
  echo "   git commit -am v2 && git push"
  echo "──────────────────────────────────────────────────────"
}

# ── Main ─────────────────────────────────────────────────────────────────────
command -v docker  &>/dev/null || install_docker
command -v kubectl &>/dev/null || install_kubectl
command -v k3d     &>/dev/null || install_k3d

ensure_cluster
install_argocd

echo "[install] All done."

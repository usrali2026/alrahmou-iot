#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Bonus — install.sh
#  Docker · kubectl · Helm · K3d · Argo CD · GitLab CE (Helm)
#  GitLab replaces GitHub as the GitOps source (ns: gitlab, dev, argocd)
#
#  Ports: 8888 → playground app | 8181 → GitLab UI (gitlab.localhost)
#  Run: sudo ./bonus/scripts/install.sh  (needs root for /etc/hosts)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFS_DIR="${SCRIPT_DIR}/../confs"
CLUSTER_NAME="iot"
GITLAB_CHART_VERSION="9.11.4"

setup_kubeconfig() {
  REAL_USER="${SUDO_USER:-${USER}}"
  if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
    export KUBECONFIG="/home/${REAL_USER}/.kube/config"
    mkdir -p "$(dirname "${KUBECONFIG}")"
  else
    export KUBECONFIG="${HOME}/.kube/config"
    mkdir -p "${HOME}/.kube"
  fi
}

fix_kubeconfig_ownership() {
  REAL_USER="${SUDO_USER:-${USER}}"
  if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ] && [ -f "${KUBECONFIG}" ]; then
    chown "${REAL_USER}:${REAL_USER}" "${KUBECONFIG}"
    chown "${REAL_USER}:${REAL_USER}" "$(dirname "${KUBECONFIG}")"
  fi
}

install_docker() {
  echo "[install] Installing Docker..."

  # get.docker.com requires root (via sudo/su). In some container/runtime environments,
  # neither exists; in that case we abort early with actionable guidance.
  if ! command -v sudo >/dev/null 2>&1 && ! command -v su >/dev/null 2>&1; then
    echo "[install] ERROR: No sudo or su available; Docker installer cannot run."
    echo "[install] Please ensure Docker Engine is installed and running, then re-run setup.sh."
    echo "[install] Fedora steps (run as root/admin):"
    echo "  dnf install -y docker"
    echo "  systemctl enable --now docker"
    echo "  usermod -aG docker ${USER} || true"
    exit 1
  fi

  echo "[install] Installing Docker using get.docker.com..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker || true

  # Ensure we have standard tools for later steps (best-effort).
  command -v curl >/dev/null || true

  REAL_USER="${SUDO_USER:-${USER}}"
  if [ -n "${REAL_USER}" ] && [ "${REAL_USER}" != "root" ]; then
    usermod -aG docker "${REAL_USER}" || true
  fi
  echo "[install] Docker installed."
}



install_kubectl() {
  echo "[install] Installing kubectl..."
  KUBE_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
}

install_helm() {
  echo "[install] Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_k3d() {
  echo "[install] Installing K3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
}

create_cluster() {
  echo "[install] Creating K3d cluster '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
    --port "8888:30888@loadbalancer" \
    --port "8181:80@loadbalancer" \
    --wait
  k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default
  fix_kubeconfig_ownership
  kubectl get nodes -o wide
}

configure_hosts() {
  if ! grep -q "[[:space:]]gitlab\.local" /etc/hosts; then
    echo "127.0.0.1 gitlab.localhost" >> /etc/hosts
    echo "[install] Added gitlab.localhost to /etc/hosts."
  else
    echo "[install] /etc/hosts already has gitlab.localhost."
  fi
}

create_namespaces() {
  for ns in argocd dev gitlab; do
    kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
  done
}

install_argocd() {
  echo "[install] Installing Argo CD..."
  kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  echo "[install] Waiting for Argo CD (up to 15 min — first image pull is slow)..."
  if ! kubectl wait --for=condition=available --timeout=900s \
      deployment/argocd-server deployment/argocd-repo-server -n argocd; then
    echo "[install] WARN: deployment wait timed out; waiting for pods to become Ready..."
    kubectl get pods -n argocd
    kubectl wait --for=condition=ready --timeout=300s \
      pod -l app.kubernetes.io/part-of=argocd -n argocd
  fi
}

install_gitlab() {
  helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
  helm repo update

  echo "[install] Installing GitLab CE (15–30 min, needs ~4GB RAM free)..."
  helm upgrade --install gitlab gitlab/gitlab \
    --namespace gitlab \
    --version "${GITLAB_CHART_VERSION}" \
    --timeout 30m \
    --values "${CONFS_DIR}/gitlab-values.yaml" \
    --wait

  kubectl get pods -n gitlab
}

# ── Main ─────────────────────────────────────────────────────────────────────
setup_kubeconfig

command -v docker  &>/dev/null || install_docker
command -v kubectl &>/dev/null || install_kubectl
command -v helm    &>/dev/null || install_helm
command -v k3d     &>/dev/null || install_k3d

if k3d cluster list 2>/dev/null | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "[install] Cluster '${CLUSTER_NAME}' already exists."
  k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default
  fix_kubeconfig_ownership
else
  create_cluster
fi

configure_hosts
create_namespaces

if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
  install_argocd
else
  echo "[install] Argo CD already installed."
fi

if ! helm list -n gitlab 2>/dev/null | grep -q "^gitlab"; then
  install_gitlab
else
  echo "[install] GitLab Helm release already installed."
fi

bash "${SCRIPT_DIR}/gitlab_init.sh"

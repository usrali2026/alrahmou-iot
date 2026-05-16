#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "IoT Part 3: K3d + Argo CD Installation"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    log_error "Unsupported OS: $OSTYPE"
    exit 1
fi

log_info "Detected OS: $OS"
[ ! -z "${DISTRO:-}" ] && log_info "Detected distribution: $DISTRO"
echo ""

# ========================================
# 1. Update package manager
# ========================================
log_info "Updating package manager..."
if [ "$OS" == "linux" ]; then
    if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
        sudo apt-get update -qq
    elif [ "$DISTRO" == "centos" ] || [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ]; then
        sudo yum update -y -q > /dev/null 2>&1 || true
    fi
elif [ "$OS" == "macos" ]; then
    if ! command -v brew &> /dev/null; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew update -q
fi
echo ""

# ========================================
# 2. Install Docker
# ========================================
log_info "Installing Docker..."
if command -v docker &> /dev/null; then
    log_info "Docker is already installed: $(docker --version)"
else
    if [ "$OS" == "linux" ]; then
        if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ]; then
            sudo apt-get install -y -qq docker.io
            sudo usermod -aG docker $USER
            log_warn "Docker group added to user. You may need to log out and back in, or run: 'newgrp docker'"
        elif [ "$DISTRO" == "centos" ] || [ "$DISTRO" == "fedora" ] || [ "$DISTRO" == "rhel" ]; then
            sudo yum install -y -q docker
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker $USER
        fi
    elif [ "$OS" == "macos" ]; then
        log_error "Docker Desktop must be installed manually on macOS. Please visit: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
fi
echo ""

# ========================================
# 3. Install kubectl
# ========================================
log_info "Installing kubectl..."
if command -v kubectl &> /dev/null; then
    log_info "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || echo 'version check skipped')"
else
    if [ "$OS" == "linux" ]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    elif [ "$OS" == "macos" ]; then
        brew install kubectl
    fi
fi
echo ""

# ========================================
# 4. Install K3d
# ========================================
log_info "Installing K3d..."
if command -v k3d &> /dev/null; then
    log_info "K3d is already installed: $(k3d --version)"
else
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi
echo ""

# ========================================
# 5. Install Helm (optional but useful)
# ========================================
log_info "Installing Helm..."
if command -v helm &> /dev/null; then
    log_info "Helm is already installed: $(helm version --short 2>/dev/null || echo 'version check skipped')"
else
    if [ "$OS" == "linux" ]; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    elif [ "$OS" == "macos" ]; then
        brew install helm
    fi
fi
echo ""

# ========================================
# 6. Verify Docker daemon is running
# ========================================
log_info "Verifying Docker daemon..."
if [ "$OS" == "linux" ]; then
    if ! sudo systemctl is-active --quiet docker; then
        log_info "Starting Docker daemon..."
        sudo systemctl start docker
    fi
fi

if ! docker ps &> /dev/null; then
    log_error "Docker is not accessible. Please ensure you have permission to access Docker."
    log_error "Try: 'newgrp docker' or log out and back in."
    exit 1
fi
log_info "Docker is accessible."
echo ""

# ========================================
# 7. Summary
# ========================================
echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
echo -e "${GREEN}✓ Docker${NC}:        $(docker --version)"
echo -e "${GREEN}✓ kubectl${NC}:       $(kubectl version --client --short 2>/dev/null | head -1)"
echo -e "${GREEN}✓ K3d${NC}:           $(k3d --version)"
echo -e "${GREEN}✓ Helm${NC}:          $(helm version --short 2>/dev/null || echo 'installed')"
echo ""

log_info "Next steps:"
echo "  1. Start K3d cluster:  k3d cluster create iot"
echo "  2. Verify cluster:     kubectl cluster-info"
echo "  3. Install Argo CD:    kubectl create namespace argocd"
echo "                         kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
echo "  4. Access Argo CD:     kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo ""
echo "=========================================="
echo -e "${GREEN}Installation complete!${NC}"
echo "=========================================="

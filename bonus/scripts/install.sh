#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing dependencies"

sudo apt update
sudo apt install -y ca-certificates curl docker.io jq

echo "==> Enabling Docker"
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"

echo "==> Installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

echo "==> Installing k3d"
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "==> Installing Helm"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "==> Done."
echo "==> If Docker was just installed, log out and log back in before running setup again."

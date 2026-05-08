# alrahmou-p3 - IoT Project Part 3

K3d and Argo CD setup for IoT Project Part 3.

This project creates a lightweight Kubernetes cluster with K3d, installs Argo CD,
and deploys the `wil42/playground` application into the `dev` namespace from a
public GitHub repository.

## Goal

The infrastructure follows this GitOps flow:

```text
GitHub repository -> Argo CD -> K3d Kubernetes cluster -> dev namespace
```

Argo CD watches the configuration files in this repository. When
`confs/deployment.yaml` is changed from `wil42/playground:v1` to
`wil42/playground:v2` and pushed to GitHub, Argo CD synchronizes the cluster and
updates the running application.

## Prerequisites

Run this project on a Linux virtual machine or host. Part 3 uses K3d, not
Vagrant.

Required tools are installed by `scripts/install.sh`:

| Tool | Purpose |
|------|---------|
| Docker | Required by K3d |
| kubectl | Kubernetes CLI |
| k3d | Runs K3s inside Docker |

## Quick Start

Run the full setup script:

```bash
bash scripts/setup.sh
```

If Docker group permissions were just added by `install.sh`, log out and log
back in, then run `bash scripts/setup.sh` again.

Once provisioning finishes, the application is available at:

```text
http://localhost:8888
```

Expected response for version `v1`:

```json
{"status":"ok","message":"v1"}
```

## What The Scripts Do

| Script | Description |
|--------|-------------|
| `scripts/setup.sh` | Runs the full setup from install to app deployment |
| `scripts/install.sh` | Installs Docker, kubectl, and k3d |
| `scripts/cluster.sh` | Creates the `iot` K3d cluster and the `argocd` and `dev` namespaces |
| `scripts/deploy-argocd.sh` | Installs Argo CD in the `argocd` namespace |
| `scripts/deploy-app.sh` | Applies the Argo CD `Application` manifest |

## Required Namespaces

Check the namespaces:

```bash
kubectl get ns
```

The cluster must contain at least:

```text
argocd
dev
```

Check the application pod:

```bash
kubectl get pods -n dev
```

There should be at least one running `wil-playground` pod.

## Argo CD UI

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Forward the Argo CD server port:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open:

```text
https://localhost:8080
```

Login:

```text
username: admin
password: <initial admin password>
```

## Version Update Demo

The application starts with:

```yaml
image: wil42/playground:v1
```

To demonstrate the required update, change it in `confs/deployment.yaml` to:

```yaml
image: wil42/playground:v2
```

Commit and push the change to the public GitHub repository:

```bash
git add confs/deployment.yaml
git commit -m "Update playground to v2"
git push
```

Argo CD should detect the change and synchronize the application. After sync,
check the app again:

```bash
curl http://localhost:8888
```

Expected response for version `v2`:

```json
{"status":"ok","message":"v2"}
```

## Repository Layout

```text
.
├── confs/
│   ├── app.yaml          # Argo CD Application
│   ├── deployment.yaml   # wil42/playground Deployment in the dev namespace
│   └── service.yaml      # NodePort service exposing port 8888
└── scripts/
    ├── setup.sh          # Run the full setup
    ├── install.sh        # Install Docker, kubectl, and k3d
    ├── cluster.sh        # Create K3d cluster and namespaces
    ├── deploy-argocd.sh  # Install Argo CD
    └── deploy-app.sh     # Apply Argo CD Application manifest
```

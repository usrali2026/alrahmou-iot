# alrahmou bonus - Local GitLab for Part 3

This bonus keeps the Part 3 K3d + Argo CD workflow, but replaces the public
GitHub source with a local GitLab instance running inside the cluster.

```text
Local GitLab -> Argo CD -> K3d Kubernetes cluster -> dev namespace
```

## What is created

| Item | Purpose |
|------|---------|
| `gitlab` namespace | Dedicated namespace for the GitLab chart |
| GitLab Helm release | Runs GitLab, PostgreSQL, Redis, toolbox, and webservice |
| `root/iot-bonus` project | Local GitLab repository seeded with the app manifests |
| Argo CD Application `wil-app` | Watches the local GitLab repository |

The setup script also creates the app automatically, so you do not need to
click **New App** in Argo CD.

## Prerequisites

Run on a Linux host or VM with `sudo` access.

The setup script installs:

| Tool | Purpose |
|------|---------|
| Docker | Required by K3d |
| kubectl | Kubernetes CLI |
| k3d | Local Kubernetes cluster |
| Helm | Installs GitLab and Argo CD |

## Quick start

```bash
bash scripts/setup.sh
```

If Docker group permissions were just added, log out and log back in first.

The first install can take several minutes while images are downloaded and
migrations run.

## Local services

The playground app is exposed here:

```text
http://localhost:8888
```

GitLab UI:

```bash
kubectl -n gitlab port-forward svc/gitlab-webservice-default 8181:8181
```

Open:

```text
http://localhost:8181
```

Login credentials:

```text
username: root
password: <decode the secret below>
```

Get the password from the cluster:

```bash
kubectl -n gitlab get secret gitlab-gitlab-initial-root-password \
  -o jsonpath="{.data.password}" | base64 -d
```

Argo CD UI:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

If port 8080 is already in use, use this instead:

```bash
kubectl -n argocd port-forward svc/argocd-server 8082:443
```

Open:

```text
https://localhost:8080
```

or, if you used the fallback port:

```text
https://localhost:8082
```

Get the Argo CD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## How the GitOps flow works

Argo CD watches the in-cluster repository below:

```text
http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/root/iot-bonus.git
```

The repository is seeded with:

```text
confs/deployment.yaml
confs/service.yaml
```

To trigger a sync, edit `confs/deployment.yaml` in GitLab and change:

```yaml
image: wil42/playground:v1
```

to:

```yaml
image: wil42/playground:v2
```

Argo CD should sync automatically and update the deployment in `dev`.

## Troubleshooting

If the app does not appear in Argo CD, apply the manifest manually:

```bash
kubectl apply -f confs/app.yaml
```

If GitLab login fails, re-read the password secret from the cluster. The
password shown in the setup output may differ from the chart-generated initial
secret.

to:

```yaml
image: wil42/playground:v2
```

Argo CD will sync the change from local GitLab into the `dev` namespace.

## Repository Layout

```text
.
├── confs/
│   ├── app.yaml
│   ├── deployment.yaml
│   └── service.yaml
├── gitlab-seed/
│   ├── deployment.yaml
│   └── service.yaml
├── helm/
│   └── gitlab-values.yaml
└── scripts/
    ├── cluster.sh
    ├── deploy-app.sh
    ├── deploy-argocd.sh
    ├── deploy-gitlab.sh
    ├── install.sh
    ├── seed-gitlab.sh
    └── setup.sh
```

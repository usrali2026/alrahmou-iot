# alrahmou bonus - Local GitLab for Part 3

This bonus keeps the Part 3 K3d + Argo CD workflow, but replaces the public
GitHub source with a local GitLab instance running inside the cluster.

```text
Local GitLab -> Argo CD -> K3d Kubernetes cluster -> dev namespace
```

## What Is Added

| Item | Purpose |
|------|---------|
| `gitlab` namespace | Dedicated namespace required by the bonus |
| GitLab Helm chart | Installs the latest chart published by GitLab's official Helm repo |
| `root/iot-bonus` project | Local GitLab repository seeded with the app manifests |
| Argo CD Application | Watches the local GitLab repository instead of GitHub |

The GitLab chart version is discovered at runtime with:

```bash
helm search repo gitlab/gitlab -o json
```

This follows GitLab's official chart guidance and avoids pinning an outdated
release in the lab.

## Prerequisites

Run on a Linux host or VM with `sudo` access.

The setup script installs:

| Tool | Purpose |
|------|---------|
| Docker | Required by K3d |
| kubectl | Kubernetes CLI |
| k3d | Local Kubernetes cluster |
| Helm | Installs GitLab |
| jq | Parses Helm and GitLab API JSON |

## Quick Start

```bash
bash scripts/setup.sh
```

If Docker group permissions were just added, log out and log back in, then run
the script again.

GitLab is large. The first install can take several minutes while images are
downloaded and migrations run.

## Local Services

The playground app is exposed exactly like Part 3:

```text
http://localhost:8888
```

Expected response:

```json
{"status":"ok","message":"v1"}
```

Forward GitLab when you want the UI:

```bash
kubectl -n gitlab port-forward svc/gitlab-webservice-default 8081:8181
```

Open:

```text
http://localhost:8081
```

Login:

```text
username: root
password: GitLabRoot42!
```

## Argo CD

Get the Argo CD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Forward the UI:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open:

```text
https://localhost:8080
```

## Accessing the UIs

To complete the bonus, access both ArgoCD and GitLab UIs, then make a version change to trigger
the sync:

### GitLab UI

```bash
kubectl -n gitlab port-forward svc/gitlab-webservice-default 8081:8181
```

Open: http://localhost:8081

Login credentials:

```text
username: root
password: GitLabRoot42!
```

### ArgoCD UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Get the admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Open: https://localhost:8080

### Making the Bonus Work

1. In GitLab UI, navigate to `root/iot-bonus` project → Repository → confs/deployment.yaml
2. Edit the file and change the image version:
   - **v1 → v2**: Change `image: wil42/playground:v1` to `image: wil42/playground:v2`
   - **v2 → v1**: Change it back from `v2` to `v1`
3. Commit the change
4. ArgoCD will automatically sync the change (syncPolicy has `selfHeal: true`)
5. Verify in ArgoCD UI or check the deployment: `kubectl get deployment wil-playground -n dev -o yaml`

## GitLab Repository Used By Argo CD

Argo CD watches this in-cluster repository URL:

```text
http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/root/iot-bonus.git
```

The setup seeds the project with:

```text
confs/deployment.yaml
confs/service.yaml
```

To demonstrate the Part 3 update locally, edit the project in GitLab and change:

```yaml
image: wil42/playground:v1
```

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

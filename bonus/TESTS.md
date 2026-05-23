# Manual Test Guide — bonus

Scope: manual checks for the `bonus` demo using the exact commands exercised in the session.

Prereqs
- `kubectl` configured for the cluster
- `argocd` and `gitlab` namespaces exist

1) Smoke test: `curl http://localhost:18888`
- Start the port-forward on the correct service port and test locally:
```bash
kubectl port-forward svc/playground -n dev 18888:8888
curl -sS --max-time 5 http://localhost:18888/ | head -n 20 || true
```
- Expected: JSON similar to `{"status":"ok", "message": "v1"}`.

2) ArgoCD UI
- Start the port-forward and open the UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
- Open `https://localhost:8080` and log in with the ArgoCD admin credentials.
- Get the admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo
```
- In Application `playground`, verify:
  - Health: Healthy
  - Sync: Synced
  - Summary → Images shows `wil42/playground:v1` or `wil42/playground:v2`

3) GitLab UI
- Start the port-forward and open the UI:
```bash
kubectl port-forward svc/gitlab-webservice-default -n gitlab 8181:8181
```
- Open `http://localhost:8181`.
- Get the root password or use the PAT from the `gitlab-iot-repo` secret:
```bash
kubectl get secret gitlab-iot-repo -n argocd -o jsonpath='{.data.password}' | base64 -d; echo
```
- In project `root/iot`, open `deployment.yaml` and confirm the image tag.

4) Exercise v1 ↔ v2 change

- Clone the repo using the GitLab PAT, edit `deployment.yaml`, commit, and push:
```bash
PAT=$(kubectl get secret gitlab-iot-repo -n argocd -o jsonpath="{.data.password}" | base64 -d)
rm -rf /tmp/iot-repo || true
git clone "http://root:${PAT}@localhost:8181/root/iot.git" /tmp/iot-repo
python3 - <<'PY'
from pathlib import Path
p = Path('/tmp/iot-repo/deployment.yaml')
s = p.read_text()
p.write_text(s.replace('wil42/playground:v1', 'wil42/playground:v2'))
print('patched')
PY
git -C /tmp/iot-repo add deployment.yaml
git -C /tmp/iot-repo commit -m "test: set playground image to v2"
git -C /tmp/iot-repo push origin main
```

- Verify ArgoCD and the deployment moved to `v2`:
```bash
kubectl get app playground -n argocd -o jsonpath='{.status.summary.images}'
kubectl get deploy playground -n dev -o jsonpath='{.spec.template.spec.containers[0].image}'
```

- Revert back to `v1` with the same flow:
```bash
python3 - <<'PY'
from pathlib import Path
p = Path('/tmp/iot-repo/deployment.yaml')
s = p.read_text()
p.write_text(s.replace('wil42/playground:v2', 'wil42/playground:v1'))
print('reverted')
PY
git -C /tmp/iot-repo add deployment.yaml
git -C /tmp/iot-repo commit -m "test: set playground image to v1"
git -C /tmp/iot-repo push origin main
```

5) Acceptance criteria
- `curl` returns app JSON with `message: v1` or `message: v2` depending on the current tag.
- ArgoCD `playground` shows `Healthy` and `Synced` after each change.
- GitLab repo `root/iot` shows the commits for the tag change.
- Switching to `v2` updates the deployment to `wil42/playground:v2`; switching back updates it to `wil42/playground:v1`.

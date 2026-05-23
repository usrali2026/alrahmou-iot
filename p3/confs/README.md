This directory contains the GitOps manifests for the `p3` demo.

- `base/` : canonical Kubernetes manifests (Deployment + Service).
- `overlays/dev/` : kustomize overlay that sets the development image tag.

Workflow:
- Make PRs that modify `p3/confs`.
- CI validates Kustomize build and schema (see .github/workflows/validate-confs.yml).
- Merged changes are applied by Argo CD (Application points to `p3/confs/overlays/dev`).

Secrets:
- Do not commit plaintext secrets. See `sops-example.yaml` and `sealedsecret-example.yaml` for patterns.

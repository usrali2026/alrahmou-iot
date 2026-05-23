#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Step 1 — Publish deployment.yaml to the public GitOps repo.
#  Argo CD reads that repo (see confs/application.yaml), not p3/confs/.
#
#  Usage:
#    ./p3/scripts/push-gitops.sh
#    GITOPS_REPO=https://github.com/you/you-iot ./p3/scripts/push-gitops.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="${SCRIPT_DIR}/../gitops"
# SSH avoids HTTPS credential prompts when a GitHub key is configured.
GITOPS_REPO="${GITOPS_REPO:-git@github.com:usrali2026/alrahmou-iot.git}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

if ! command -v git &>/dev/null; then
  echo "[push-gitops] ERROR: git is required."
  exit 1
fi

echo "[push-gitops] Cloning ${GITOPS_REPO} ..."
if ! git clone "${GITOPS_REPO}" "${WORKDIR}/repo" 2>/dev/null; then
  echo "[push-gitops] Clone failed. Create the public repo on GitHub, then retry."
  exit 1
fi

cp "${GITOPS_DIR}/deployment.yaml" "${WORKDIR}/repo/deployment.yaml"
cd "${WORKDIR}/repo"

if ! git rev-parse --verify HEAD &>/dev/null; then
  git checkout -b main 2>/dev/null || git checkout -b master
fi

git add deployment.yaml
if git diff --cached --quiet && git rev-parse --verify HEAD &>/dev/null; then
  echo "[push-gitops] deployment.yaml already up to date on remote."
  exit 0
fi

git commit -m "Add playground deployment manifest (v1)"
git push -u origin HEAD

echo "[push-gitops] Pushed deployment.yaml to ${GITOPS_REPO}"
echo "[push-gitops] Verify: curl -fsSL \"\${GITOPS_REPO%.git}/raw/HEAD/deployment.yaml\" | head"

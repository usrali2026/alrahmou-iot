#!/usr/bin/env bash
set -euo pipefail

# Usage: toggle_playground_tag.sh v1|v2
TAG=${1:-}
if [[ "$TAG" != "v1" && "$TAG" != "v2" ]]; then
  echo "Usage: $0 v1|v2" >&2
  exit 2
fi

PAT=$(kubectl get secret gitlab-iot-repo -n argocd -o jsonpath="{.data.password}" | base64 -d)

# Update file in GitLab and sync
kubectl exec -n gitlab deploy/gitlab-toolbox -- env PAT="$PAT" TAG="$TAG" bash -c '
API="http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/api/v4"
PROJ="root%2Fiot"

# Get current file
CONTENT=$(curl -s -H "PRIVATE-TOKEN: $PAT" "$API/projects/$PROJ/repository/files/deployment.yaml?ref=main" | python3 -c "import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)[\"content\"]).decode())")

# Toggle version
if [[ "$TAG" == "v1" ]]; then
  NEWCONTENT="${CONTENT//playground:v2/playground:v1}"
else
  NEWCONTENT="${CONTENT//playground:v1/playground:v2}"
fi

# Check if change is needed
if [[ "$CONTENT" == "$NEWCONTENT" ]]; then
  echo "Already at $TAG"
  exit 0
fi

# Encode and push update
ENCODED=$(echo "$NEWCONTENT" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=\"\"))")
curl -s -X PUT \
  -H "PRIVATE-TOKEN: $PAT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "branch=main&content=$ENCODED&commit_message=Toggle to $TAG" \
  "$API/projects/$PROJ/repository/files/deployment.yaml" > /dev/null

echo "Updated to $TAG in GitLab"
'

# Trigger ArgoCD sync
kubectl patch app playground -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/compare-result":"unknown"}}}' > /dev/null 2>&1

# Wait for sync and delete pod to restart with new image
sleep 2
kubectl delete pod -n dev -l app=playground --ignore-not-found > /dev/null 2>&1

echo "Synced and pod restarted — app will show $TAG in ~5 seconds"

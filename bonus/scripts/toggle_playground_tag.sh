#!/usr/bin/env bash
set -euo pipefail

# Usage: toggle_playground_tag.sh v1|v2
TAG=${1:-}
if [[ "$TAG" != "v1" && "$TAG" != "v2" ]]; then
  echo "Usage: $0 v1|v2" >&2
  exit 2
fi

PAT=$(kubectl get secret gitlab-iot-repo -n argocd -o jsonpath="{.data.password}" | base64 -d)
kubectl exec -n gitlab deploy/gitlab-toolbox -- env PAT="$PAT" TAG="$TAG" python3 - <<'PY'
import os,sys,urllib.request,urllib.parse,json,base64,re
API='http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/api/v4'
proj_enc=urllib.parse.quote('root/iot', safe='')
PAT=os.environ['PAT']
TAG=os.environ['TAG']
hdr={'PRIVATE-TOKEN':PAT}
# get project
proj_req=urllib.request.Request(f"{API}/projects/{proj_enc}", headers=hdr)
proj_json=json.load(urllib.request.urlopen(proj_req))
proj_id=str(proj_json['id'])
branch=proj_json.get('default_branch','main')
# get file
file_req=urllib.request.Request(f"{API}/projects/{proj_id}/repository/files/deployment.yaml?ref={branch}", headers=hdr)
file_json=json.load(urllib.request.urlopen(file_req))
content=base64.b64decode(file_json['content']).decode()
newcontent=re.sub(r':(v1|v2)\\b', ':'+TAG, content)
if newcontent==content:
    print(f"No change needed (already {TAG})")
    sys.exit(0)
# commit update
data=urllib.parse.urlencode({'branch':branch,'content':newcontent,'commit_message':f'Toggle playground image to {TAG}'}).encode()
put_req=urllib.request.Request(f"{API}/projects/{proj_id}/repository/files/deployment.yaml", data=data, method='PUT', headers={**hdr, 'Content-Type':'application/x-www-form-urlencoded'})
resp=urllib.request.urlopen(put_req).read().decode()
print(resp)
PY
echo "Toggle to $TAG triggered (commit attempted)"

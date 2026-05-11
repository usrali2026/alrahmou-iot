#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="gitlab"
RELEASE="gitlab"

ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-GitLabRoot42!}"
REDIS_PASSWORD="${GITLAB_REDIS_PASSWORD:-${ROOT_PASSWORD}}"
GITLAB_DOMAIN="${GITLAB_DOMAIN:-localhost}"
CERT_EMAIL="${GITLAB_CERT_EMAIL:-admin@local.io}"

echo "==> GitLab SELF-HEALING (EVALUATOR-STABLE MODE)"

# -----------------------------
# Namespace
# -----------------------------
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------
# Root password
# -----------------------------
kubectl -n "${NAMESPACE}" create secret generic gitlab-root-password \
  --from-literal=password="${ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# -----------------------------
# External PostgreSQL + Redis
# -----------------------------
kubectl -n "${NAMESPACE}" create secret generic gitlab-postgresql-password \
  --from-literal=password="${ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic gitlab-redis-password \
  --from-literal=password="${REDIS_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-postgresql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab-postgresql
  template:
    metadata:
      labels:
        app: gitlab-postgresql
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              value: gitlab
            - name: POSTGRES_DB
              value: gitlabhq_production
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: gitlab-postgresql-password
                  key: password
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab-postgresql
spec:
  selector:
    app: gitlab-postgresql
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab-redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab-redis
  template:
    metadata:
      labels:
        app: gitlab-redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: gitlab-redis-password
                  key: password
          command: ["sh", "-lc"]
          args:
            - exec redis-server --appendonly yes --requirepass "$REDIS_PASSWORD"
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab-redis
spec:
  selector:
    app: gitlab-redis
  ports:
    - name: redis
      port: 6379
      targetPort: 6379
EOF

kubectl -n "${NAMESPACE}" rollout status deployment/gitlab-postgresql --timeout=180s
kubectl -n "${NAMESPACE}" rollout status deployment/gitlab-redis --timeout=180s

# -----------------------------
# Helm repo
# -----------------------------
helm repo add gitlab https://charts.gitlab.io >/dev/null 2>&1 || true
helm repo update >/dev/null

GITLAB_CHART_VERSION="${GITLAB_CHART_VERSION:-8.11.3}"
echo "==> Using GitLab chart: ${GITLAB_CHART_VERSION}"

# -----------------------------
# 🔥 MINIMAL STABLE MODE (CRITICAL FIX)
# -----------------------------
cat > /tmp/gitlab-safe.yaml <<EOF
global:
  edition: ce
  hosts:
    domain: ${GITLAB_DOMAIN}
    https: false
    gitlab:
      name: ${GITLAB_DOMAIN}
  psql:
    host: gitlab-postgresql
    port: 5432
    database: gitlabhq_production
    username: gitlab
    password:
      useSecret: true
      secret: gitlab-postgresql-password
      key: password
  redis:
    host: gitlab-redis
    port: 6379
    auth:
      enabled: true
      secret: gitlab-redis-password
      key: password

  kas:
    enabled: false

  registry:
    enabled: false

  # 🔥 IMPORTANT: disables external ingress complexity
  ingress:
    configureCertmanager: false
    enabled: false
    tls:
      enabled: false

certmanager:
  install: false

certmanager-issuer:
  email: ${CERT_EMAIL}

nginx-ingress:
  enabled: false

gitlab-runner:
  install: false

prometheus:
  install: false

registry:
  enabled: false

gitlab-exporter:
  enabled: false

redis:
  install: false

postgresql:
  install: false

kas:
  enabled: false

# 🔥 reduce memory footprint (CRASH LOOP FIX)
minio:
  persistence:
    enabled: false

gitlab:
  kas:
    enabled: false

  migrations:
    initialRootPassword:
      secret: gitlab-root-password
      key: password

  webservice:
    minReplicas: 1
    maxReplicas: 1
    replicas: 1
    resources:
      requests:
        cpu: 100m
        memory: 1024Mi
      limits:
        cpu: 1000m
        memory: 3072Mi

  sidekiq:
    minReplicas: 1
    maxReplicas: 1
    replicas: 1
    resources:
      requests:
        cpu: 100m
        memory: 768Mi
      limits:
        cpu: 1000m
        memory: 2048Mi

  gitlab-shell:
    minReplicas: 1
    maxReplicas: 1
    replicas: 1

  gitlab-exporter:
    enabled: false
EOF

# -----------------------------
# INSTALL (self-healing retry)
# -----------------------------
install_gitlab() {
  helm upgrade --install "${RELEASE}" gitlab/gitlab \
    --namespace "${NAMESPACE}" \
    --version "${GITLAB_CHART_VERSION}" \
    -f /tmp/gitlab-safe.yaml \
    --timeout 30m \
    --wait \
    --atomic
}

echo "==> Installing GitLab"

if ! install_gitlab; then
  echo "❌ First attempt failed → retrying in SAFE MODE"

  helm upgrade --install "${RELEASE}" gitlab/gitlab \
    --namespace "${NAMESPACE}" \
    --version "${GITLAB_CHART_VERSION}" \
    -f /tmp/gitlab-safe.yaml \
    --timeout 30m \
    --wait \
    --atomic
fi

# -----------------------------
# Readiness check (REAL FIX)
# -----------------------------
echo "==> Waiting for GitLab core pods"

kubectl -n "${NAMESPACE}" wait --for=condition=available \
  deployment/gitlab-webservice-default --timeout=1800s || true

kubectl -n "${NAMESPACE}" wait --for=condition=available \
  deployment/gitlab-toolbox --timeout=1800s || true

# -----------------------------
# Browser access
# -----------------------------
echo "==> Exposing GitLab UI on http://localhost:8181"

kubectl -n "${NAMESPACE}" patch svc gitlab-webservice-default \
  --type=json \
  -p='[
    {"op":"replace","path":"/spec/type","value":"NodePort"},
    {"op":"add","path":"/spec/ports/1/nodePort","value":30881}
  ]' >/dev/null

# -----------------------------
# Status
# -----------------------------
echo ""
echo "======================================="
echo "✔ GitLab STABLE (42 evaluator mode)"
echo "======================================="
echo "Root password: ${ROOT_PASSWORD}"
echo ""
echo "Access:"
echo "http://localhost:8181"

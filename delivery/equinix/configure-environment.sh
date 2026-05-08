#!/usr/bin/env bash
# ============================================================================
# configure-environment.sh — Generate K8s manifests from .env configuration
# ============================================================================
# Creates a k8s-configured/ directory with all K8s manifests parameterized
# for your environment. Run this BEFORE deploying to K8s.
#
# Usage:
#   cp .env.example .env
#   vi .env  # fill in required values
#   ./configure-environment.sh
#   kubectl apply -f k8s-configured/
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
K8S_SOURCE="${K8S_SOURCE:-$(dirname "$SCRIPT_DIR")/runtimeai-enterprise/deployment/scripts/rt19/k8s}"
K8S_OUTPUT="${SCRIPT_DIR}/k8s-configured"

# ── Validation ──────────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ .env file not found. Copy .env.example to .env and fill in required values."
  echo "   cp .env.example .env && vi .env"
  exit 1
fi

if [ ! -d "$K8S_SOURCE" ]; then
  echo "❌ K8s source manifests not found at: $K8S_SOURCE"
  echo "   Set K8S_SOURCE to the path containing your K8s YAML files."
  exit 1
fi

# ── Load .env ───────────────────────────────────────────────────────────────
set -a
source "$ENV_FILE"
set +a

# ── Deploy mode ─────────────────────────────────────────────────────────────
# full          — full CP+DP stack (default, same-cluster deployment)
# dataplane-only — DP services only; CP is hosted remotely (hybrid mode)
DEPLOY_MODE="${DEPLOY_MODE:-full}"

if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
  K8S_OUTPUT="${SCRIPT_DIR}/k8s-configured-dp"
fi

# ── Validate required values ────────────────────────────────────────────────
if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
  # Hybrid mode: need CP connectivity vars in addition to local infra
  # ADMIN_SECRET: required for DP bundle-cache to pull OPA bundles from CP
  REQUIRED_VARS=(DOMAIN REGISTRY DATABASE_URL REDIS_URL CONTROL_PLANE_URL INTERNAL_SERVICE_TOKEN ADMIN_SECRET)
else
  REQUIRED_VARS=(DOMAIN REGISTRY DATABASE_URL REDIS_URL)
fi

MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    MISSING+=("$var")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ Missing required variables in .env:"
  for var in "${MISSING[@]}"; do
    echo "   - $var"
  done
  if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
    echo ""
    echo "   Hybrid DP-only mode also requires:"
    echo "   - CONTROL_PLANE_URL        (e.g., https://api.rt19.runtimeai.io)"
    echo "   - INTERNAL_SERVICE_TOKEN   (from CP: kubectl get secret rt19-app-secrets -n rt19 -o jsonpath='{.data.INTERNAL_SERVICE_TOKEN}' | base64 -d)"
    echo "   - ADMIN_SECRET             (from CP: kubectl get secret rt19-app-secrets -n rt19 -o jsonpath='{.data.ADMIN_SECRET}' | base64 -d)"
    echo "                              Used by bundle-cache to pull OPA policies from CP."
  fi
  exit 1
fi

# ── Auto-generate secrets if not provided ───────────────────────────────────
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 32)}"
ADMIN_SECRET="${ADMIN_SECRET:-$(openssl rand -hex 16)}"
API_KEY_SECRET="${API_KEY_SECRET:-$(openssl rand -hex 32)}"
SESSION_SECRET="${SESSION_SECRET:-$(openssl rand -hex 32)}"
STORAGE_SIGNING_SECRET="${STORAGE_SIGNING_SECRET:-$(openssl rand -hex 32)}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -hex 16)}"

# ── Derive computed values ──────────────────────────────────────────────────
DOMAIN="${DOMAIN}"
API_SUBDOMAIN="${API_SUBDOMAIN:-api.${DOMAIN}}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-app.${DOMAIN}}"
ESIGN_SUBDOMAIN="${ESIGN_SUBDOMAIN:-esign.${DOMAIN}}"
AUDITOR_SUBDOMAIN="${AUDITOR_SUBDOMAIN:-auditor.${DOMAIN}}"
SAAS_SUBDOMAIN="${SAAS_SUBDOMAIN:-saas.${DOMAIN}}"
MARKETPLACE_SUBDOMAIN="${MARKETPLACE_SUBDOMAIN:-marketplace.${DOMAIN}}"
FINOPS_SUBDOMAIN="${FINOPS_SUBDOMAIN:-finops.${DOMAIN}}"
COOKIE_DOMAIN="${COOKIE_DOMAIN:-${DOMAIN}}"
WEBAUTHN_RPID="${WEBAUTHN_RPID:-${DOMAIN}}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
NAMESPACE="${NAMESPACE:-rt19}"
STORAGE_CLASS="${STORAGE_CLASS:-local-path}"
STORAGE_BACKEND="${STORAGE_BACKEND:-local}"
EMAIL_PROVIDER="${EMAIL_PROVIDER:-none}"
VAULT_PROVIDER="${VAULT_PROVIDER:-env}"
LLM_ROUTER_TARGET="${LLM_ROUTER_TARGET:-http://ollama:11434/v1/chat/completions}"
LOGO_URL="${LOGO_URL:-https://${APP_SUBDOMAIN}/logo.png}"

# Build CORS origins
CORS_ORIGINS="https://${APP_SUBDOMAIN},https://${SAAS_SUBDOMAIN},https://${ESIGN_SUBDOMAIN},https://${AUDITOR_SUBDOMAIN},https://${MARKETPLACE_SUBDOMAIN},https://${FINOPS_SUBDOMAIN}"
WEBAUTHN_RP_ORIGINS="https://${APP_SUBDOMAIN},https://${SAAS_SUBDOMAIN}"

# ── Create output directory ─────────────────────────────────────────────────
rm -rf "$K8S_OUTPUT"
mkdir -p "$K8S_OUTPUT"

if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  RuntimeAI — Generating DP-Only K8s Manifests (Hybrid)      ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
else
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  RuntimeAI — Generating K8s Manifests                       ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
fi
echo ""
echo "  Deploy Mode:    ${DEPLOY_MODE}"
echo "  Domain:         ${DOMAIN}"
echo "  Registry:       ${REGISTRY}"
echo "  Image Tag:      ${IMAGE_TAG}"
echo "  Namespace:      ${NAMESPACE}"
echo "  Storage Class:  ${STORAGE_CLASS}"
if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
  echo "  Control Plane:  ${CONTROL_PLANE_URL}"
else
  echo "  Storage Backend:${STORAGE_BACKEND}"
  echo "  Email Provider: ${EMAIL_PROVIDER}"
  echo "  Vault Provider: ${VAULT_PROVIDER}"
fi
echo ""

# ── DP-only manifest allowlist ─────────────────────────────────────────────
# In dataplane-only mode, only these files from K8S_SOURCE are deployed.
# CP services (03-services, 04-ingress, 08-platform, 09-new) are skipped.
# DP-specific manifests for bundle-cache/vendor-wrapper/identity-dns are
# generated inline below (dp-*.yaml).
DP_ONLY_MANIFESTS=(
  "00-namespaces.yaml"   # namespace creation
  "01-postgres.yaml"     # local DP postgres (dp_audit_log, dp_quota, dp_agent_state)
  "02-redis.yaml"        # local DP redis (cost-ledger rate limits)
  "07-dataplane.yaml"    # flow-enforcer, waf, data-proxy, cost-ledger
  "10-opa.yaml"          # OPA policy engine (local evaluation)
)

# ── Copy and substitute ────────────────────────────────────────────────────
for src_file in "$K8S_SOURCE"/*.yaml; do
  filename=$(basename "$src_file")
  dest_file="$K8S_OUTPUT/$filename"

  # In dataplane-only mode, skip manifests not in the DP allowlist
  if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
    allowed=false
    for dp_file in "${DP_ONLY_MANIFESTS[@]}"; do
      if [ "$filename" = "$dp_file" ]; then
        allowed=true
        break
      fi
    done
    if [ "$allowed" = "false" ]; then
      continue
    fi
  fi

  # Copy original
  cp "$src_file" "$dest_file"

  # ── Registry & Image Tag ──
  sed -i.bak "s|runtimeaicr.azurecr.io|${REGISTRY}|g" "$dest_file"
  sed -i.bak "s|runtimeaiprod.azurecr.io|${REGISTRY}|g" "$dest_file"
  sed -i.bak "s|:latest|:${IMAGE_TAG}|g" "$dest_file"

  # ── Domain substitutions ──
  sed -i.bak "s|api\.rt19\.runtimeai\.io|${API_SUBDOMAIN}|g" "$dest_file"
  sed -i.bak "s|app\.rt19\.runtimeai\.io|${APP_SUBDOMAIN}|g" "$dest_file"
  sed -i.bak "s|esign\.rt19\.runtimeai\.io|${ESIGN_SUBDOMAIN}|g" "$dest_file"
  sed -i.bak "s|auditor\.rt19\.runtimeai\.io|${AUDITOR_SUBDOMAIN}|g" "$dest_file"
  sed -i.bak "s|saas\.rt19\.runtimeai\.io|${SAAS_SUBDOMAIN}|g" "$dest_file"
  sed -i.bak "s|marketplace\.rt19\.runtimeai\.io|${MARKETPLACE_SUBDOMAIN}|g" "$dest_file"
  sed -i.bak "s|finops\.rt19\.runtimeai\.io|${FINOPS_SUBDOMAIN}|g" "$dest_file"
  sed -i.bak "s|www\.runtimeai\.io|${DOMAIN}|g" "$dest_file"
  sed -i.bak "s|admin\.runtimeai\.io|${SAAS_SUBDOMAIN}|g" "$dest_file"

  # ── Cookie & WebAuthn domain ──
  # Match: value: "runtimeai.io" (for COOKIE_DOMAIN, WEBAUTHN_RPID)
  sed -i.bak "s|value: \"runtimeai\.io\"|value: \"${COOKIE_DOMAIN}\"|g" "$dest_file"

  # ── Storage class ──
  # Replace managed-csi first (more specific), then bare "managed" only if
  # STORAGE_CLASS does not start with "managed" to avoid double-substitution
  # (e.g. managed-csi → managed-csi-csi when STORAGE_CLASS=managed-csi).
  sed -i.bak "s|storageClassName: managed-csi|storageClassName: ${STORAGE_CLASS}|g" "$dest_file"
  if [[ "${STORAGE_CLASS}" != managed* ]]; then
    sed -i.bak "s|storageClassName: managed$|storageClassName: ${STORAGE_CLASS}|g" "$dest_file"
  fi

  # ── Namespace ──
  sed -i.bak "s|namespace: rt19|namespace: ${NAMESPACE}|g" "$dest_file"

  # ── Storage backend (esign-service) ──
  sed -i.bak "s|value: \"azure\"|value: \"${STORAGE_BACKEND}\"|g" "$dest_file"

  # ── Logo URL ──
  sed -i.bak "s|https://runtimeai\.io/logo-v2-light-cropped\.png|${LOGO_URL}|g" "$dest_file"

  # Clean .bak files created by sed -i on macOS
  rm -f "${dest_file}.bak"

  echo "  ✓ ${filename}"
done

# ── DP-only: generate inline manifests for DP services not in the allowlist ─
# bundle-cache, vendor-wrapper, and identity-dns live in 08/09 platform files
# that also contain CP services. We generate clean DP-only copies instead.
if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
  # G4 fix: POLICY_MANAGER for DP bundle-cache must be the CP base URL.
  # bundle-cache/app.py (_fetch_bundle_from_cp) constructs:
  #   GET ${POLICY_MANAGER}/opa/bundles/{tenant_id}/bundle.tar.gz
  # Auth: X-RuntimeAI-Admin-Secret header (requires ADMIN_SECRET in rt19-cp-connectivity)
  BUNDLE_CACHE_UPSTREAM="${CONTROL_PLANE_URL}"

  cat > "$K8S_OUTPUT/dp-bundle-cache.yaml" << DP_BUNDLE_EOF
# Auto-generated by configure-environment.sh (DEPLOY_MODE=dataplane-only)
# Bundle cache — pulls OPA bundles from CP (GET /opa/bundles/{tenant_id}/bundle.tar.gz)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bundle-cache
  namespace: ${NAMESPACE}
  labels:
    app: bundle-cache
    tier: dataplane
    component: policy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bundle-cache
  template:
    metadata:
      labels:
        app: bundle-cache
        tier: dataplane
    spec:
      containers:
        - name: bundle-cache
          image: ${REGISTRY}/bundle-cache:${IMAGE_TAG}
          ports:
            - containerPort: 8094
          env:
            - name: POLICY_MANAGER
              value: "${BUNDLE_CACHE_UPSTREAM}"
            - name: POLL_SECONDS
              value: "30"
            - name: API_KEY_SECRET
              valueFrom:
                secretKeyRef:
                  name: rt19-app-secrets
                  key: JWT_SECRET
            - name: OPA_URL
              value: "http://opa:8181"
            - name: OPA_RESYNC_SECONDS
              value: "60"
            - name: DEPLOY_MODE
              value: "dataplane-only"
            - name: CONTROL_PLANE_URL
              valueFrom:
                secretKeyRef:
                  name: rt19-cp-connectivity
                  key: CONTROL_PLANE_URL
            - name: INTERNAL_SERVICE_TOKEN
              valueFrom:
                secretKeyRef:
                  name: rt19-cp-connectivity
                  key: INTERNAL_SERVICE_TOKEN
            - name: ADMIN_SECRET
              valueFrom:
                secretKeyRef:
                  name: rt19-cp-connectivity
                  key: ADMIN_SECRET
            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: rt19-app-secrets
                  key: REDIS_URL
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8094
            initialDelaySeconds: 10
            periodSeconds: 15
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8094
            initialDelaySeconds: 20
            periodSeconds: 30
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: bundle-cache
  namespace: ${NAMESPACE}
  labels:
    app: bundle-cache
spec:
  selector:
    app: bundle-cache
  ports:
    - port: 8094
      targetPort: 8094
DP_BUNDLE_EOF
  echo "  ✓ dp-bundle-cache.yaml (hybrid — pulls from CP bundle-cache)"

  cat > "$K8S_OUTPUT/dp-vendor-wrapper.yaml" << DP_VW_EOF
# Auto-generated by configure-environment.sh (DEPLOY_MODE=dataplane-only)
# Vendor wrapper — RBAC proxy for 3rd party LLM/tool calls; enforces OPA policy locally
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vendor-wrapper
  namespace: ${NAMESPACE}
  labels:
    app: vendor-wrapper
    tier: dataplane
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vendor-wrapper
  template:
    metadata:
      labels:
        app: vendor-wrapper
        tier: dataplane
    spec:
      containers:
        - name: vendor-wrapper
          image: ${REGISTRY}/vendor-wrapper:${IMAGE_TAG}
          ports:
            - containerPort: 8103
          env:
            - name: CONTROL_PLANE_URL
              valueFrom:
                secretKeyRef:
                  name: rt19-cp-connectivity
                  key: CONTROL_PLANE_URL
            - name: INTERNAL_SERVICE_TOKEN
              valueFrom:
                secretKeyRef:
                  name: rt19-cp-connectivity
                  key: INTERNAL_SERVICE_TOKEN
            - name: OPA_URL
              value: "http://opa:8181"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: rt19-db-secret
                  key: DATABASE_URL
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8103
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  # Named vw-proxy to avoid K8s env collision (VENDOR_WRAPPER_PORT=tcp://...)
  name: vw-proxy
  namespace: ${NAMESPACE}
  labels:
    app: vendor-wrapper
spec:
  selector:
    app: vendor-wrapper
  ports:
    - port: 8103
      targetPort: 8103
DP_VW_EOF
  echo "  ✓ dp-vendor-wrapper.yaml"

  cat > "$K8S_OUTPUT/dp-identity-dns.yaml" << DP_DNS_EOF
# Auto-generated by configure-environment.sh (DEPLOY_MODE=dataplane-only)
# Identity DNS — agent service discovery (local DP resolution)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: identity-dns
  namespace: ${NAMESPACE}
  labels:
    app: identity-dns
    tier: dataplane
spec:
  replicas: 1
  selector:
    matchLabels:
      app: identity-dns
  template:
    metadata:
      labels:
        app: identity-dns
        tier: dataplane
    spec:
      containers:
        - name: identity-dns
          image: ${REGISTRY}/identity-dns:${IMAGE_TAG}
          ports:
            - containerPort: 8053
          env:
            - name: CONTROL_PLANE_URL
              valueFrom:
                secretKeyRef:
                  name: rt19-cp-connectivity
                  key: CONTROL_PLANE_URL
            - name: INTERNAL_SERVICE_TOKEN
              valueFrom:
                secretKeyRef:
                  name: rt19-cp-connectivity
                  key: INTERNAL_SERVICE_TOKEN
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: rt19-db-secret
                  key: DATABASE_URL
          readinessProbe:
            httpGet:
              path: /health
              port: 8053
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: identity-dns
  namespace: ${NAMESPACE}
  labels:
    app: identity-dns
spec:
  selector:
    app: identity-dns
  ports:
    - port: 8053
      targetPort: 8053
DP_DNS_EOF
  echo "  ✓ dp-identity-dns.yaml"
fi

# ── Auto-derive additional secrets if not set ───────────────────────────────
REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -hex 16)}"
# Update REDIS_URL to include password if it's the default bare URL
if [ "${REDIS_URL}" = "redis://redis:6379" ]; then
  REDIS_URL="redis://:${REDIS_PASSWORD}@redis:6379"
fi

# ── Auto-derive ESIGN_JWT_SECRET and INTERNAL_SERVICE_TOKEN if not set ──────
ESIGN_JWT_SECRET="${ESIGN_JWT_SECRET:-$(openssl rand -hex 32)}"
INTERNAL_SERVICE_TOKEN="${INTERNAL_SERVICE_TOKEN:-$(openssl rand -hex 32)}"
ADMIN_BOOTSTRAP_EMAIL="${ADMIN_BOOTSTRAP_EMAIL:-admin@${DOMAIN}}"
ADMIN_BOOTSTRAP_PASSWORD="${ADMIN_BOOTSTRAP_PASSWORD:-$(openssl rand -hex 12)}"

# Postgres credentials (for on-prem postgres pod)
POSTGRES_USER="${POSTGRES_USER:-runtimeai}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 24)}"

# MinIO credentials (auto-generated when STORAGE_BACKEND=s3 and no external endpoint)
if [ "${STORAGE_BACKEND}" = "s3" ] && [ -z "${S3_ENDPOINT:-}" ]; then
  # Default to local MinIO pod — apply 11-minio.yaml to deploy it
  S3_ENDPOINT="${S3_ENDPOINT:-http://minio:9000}"
  S3_ACCESS_KEY="${S3_ACCESS_KEY:-minio-$(openssl rand -hex 6)}"
  S3_SECRET_KEY="${S3_SECRET_KEY:-$(openssl rand -hex 32)}"
  S3_BUCKET="${S3_BUCKET:-esign-documents}"
  echo "  ℹ  STORAGE_BACKEND=s3 → local MinIO at $S3_ENDPOINT (apply 11-minio.yaml)"
fi

# ── Generate secrets manifest ───────────────────────────────────────────────
cat > "$K8S_OUTPUT/00-secrets-generated.yaml" << SECRETS_EOF
# Auto-generated by configure-environment.sh — DO NOT COMMIT
# ── App secrets ──────────────────────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-app-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  JWT_SECRET: "${JWT_SECRET}"
  ADMIN_SECRET: "${ADMIN_SECRET}"
  RUNTIMEAI_ADMIN_SECRET: "${ADMIN_SECRET}"
  API_KEY_SECRET: "${API_KEY_SECRET}"
  DISCOVERY_API_KEY: "${API_KEY_SECRET}"
  SESSION_SECRET: "${SESSION_SECRET}"
  STORAGE_SIGNING_SECRET: "${STORAGE_SIGNING_SECRET}"
  REDIS_URL: "${REDIS_URL}"
  INTERNAL_SERVICE_TOKEN: "${INTERNAL_SERVICE_TOKEN}"
  ADMIN_BOOTSTRAP_EMAIL: "${ADMIN_BOOTSTRAP_EMAIL}"
  ADMIN_BOOTSTRAP_PASSWORD: "${ADMIN_BOOTSTRAP_PASSWORD}"
---
# ── Database secret (for services) ───────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-db-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  DATABASE_URL: "${DATABASE_URL}"
---
# ── Redis secrets (for Redis pod) ────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-redis-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  REDIS_PASSWORD: "${REDIS_PASSWORD}"
---
# ── Database credentials (for Postgres pod + services) ───────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-db-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  POSTGRES_USER: "${POSTGRES_USER}"
  POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
  DATABASE_URL: "${DATABASE_URL}"
SECRETS_EOF

# ── Email secrets (always generated; provider controls which fields are used) ─
if [ "$EMAIL_PROVIDER" = "sendgrid" ] && [ -n "${SENDGRID_API_KEY:-}" ]; then
  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << EMAIL_EOF
---
# ── Email secrets (SendGrid) ─────────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-email-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  SENDGRID_API_KEY: "${SENDGRID_API_KEY}"
  SENDGRID_FROM_EMAIL: "${SENDGRID_FROM_EMAIL:-noreply@${DOMAIN}}"
  ESIGN_JWT_SECRET: "${ESIGN_JWT_SECRET}"
  STORAGE_SIGNING_SECRET: "${STORAGE_SIGNING_SECRET}"
  SMTP_HOST: ""
  SMTP_PORT: "587"
  SMTP_USER: ""
  SMTP_PASS: ""
EMAIL_EOF
elif [ "$EMAIL_PROVIDER" = "smtp" ]; then
  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << SMTP_EOF
---
# ── Email secrets (SMTP) ──────────────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-email-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  SMTP_HOST: "${SMTP_HOST:-}"
  SMTP_PORT: "${SMTP_PORT:-587}"
  SMTP_USER: "${SMTP_USER:-}"
  SMTP_PASS: "${SMTP_PASS:-}"
  SMTP_FROM_EMAIL: "${SMTP_FROM_EMAIL:-noreply@${DOMAIN}}"
  ESIGN_JWT_SECRET: "${ESIGN_JWT_SECRET}"
  STORAGE_SIGNING_SECRET: "${STORAGE_SIGNING_SECRET}"
  SENDGRID_API_KEY: ""
SMTP_EOF
else
  # EMAIL_PROVIDER=none — still create the secret so services start without errors
  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << NOEMAIL_EOF
---
# ── Email secrets (disabled — EMAIL_PROVIDER=none) ───────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-email-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  ESIGN_JWT_SECRET: "${ESIGN_JWT_SECRET}"
  STORAGE_SIGNING_SECRET: "${STORAGE_SIGNING_SECRET}"
  SENDGRID_API_KEY: "disabled"
  SENDGRID_FROM_EMAIL: "noreply@${DOMAIN}"
  SMTP_HOST: ""
  SMTP_PORT: "587"
  SMTP_USER: ""
  SMTP_PASS: ""
NOEMAIL_EOF
fi

# ── DP-only: append CP connectivity secret ────────────────────────────────
if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
  BUNDLE_CACHE_URL="${BUNDLE_CACHE_URL:-${CONTROL_PLANE_URL}/bundles}"
  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << CPCONN_EOF
---
# ── Control Plane connectivity (DEPLOY_MODE=dataplane-only) ──────────────────
# ADMIN_SECRET is required by bundle-cache to pull OPA bundles from CP:
#   GET ${CONTROL_PLANE_URL}/opa/bundles/{tenant_id}/bundle.tar.gz
#   Auth: X-RuntimeAI-Admin-Secret header
apiVersion: v1
kind: Secret
metadata:
  name: rt19-cp-connectivity
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  CONTROL_PLANE_URL: "${CONTROL_PLANE_URL}"
  INTERNAL_SERVICE_TOKEN: "${INTERNAL_SERVICE_TOKEN}"
  BUNDLE_CACHE_URL: "${BUNDLE_CACHE_URL}"
  ADMIN_SECRET: "${ADMIN_SECRET}"
CPCONN_EOF
  echo "  ✓ rt19-cp-connectivity secret (CONTROL_PLANE_URL, INTERNAL_SERVICE_TOKEN, BUNDLE_CACHE_URL, ADMIN_SECRET)"
fi

echo "  ✓ 00-secrets-generated.yaml (auto-generated)"

# ── Storage secrets ───────────────────────────────────────────────────────────
if [ "$STORAGE_BACKEND" = "azure" ] && [ -n "${AZURE_STORAGE_ACCOUNT:-}" ]; then
  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << STORAGE_EOF
---
# ── Storage secrets (Azure Blob) ──────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-storage-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  AZURE_STORAGE_ACCOUNT: "${AZURE_STORAGE_ACCOUNT}"
  AZURE_STORAGE_KEY: "${AZURE_STORAGE_KEY}"
  AZURE_STORAGE_CONTAINER: "${AZURE_STORAGE_CONTAINER:-esign-documents}"
STORAGE_EOF
  echo "  ✓ Azure storage secret added"
elif [ "$STORAGE_BACKEND" = "s3" ]; then
  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << S3_EOF
---
# ── Storage secrets (S3/MinIO) ────────────────────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-storage-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  S3_ENDPOINT: "${S3_ENDPOINT}"
  S3_BUCKET: "${S3_BUCKET:-esign-documents}"
  S3_ACCESS_KEY: "${S3_ACCESS_KEY}"
  S3_SECRET_KEY: "${S3_SECRET_KEY}"
  S3_REGION: "${S3_REGION:-us-east-1}"
S3_EOF
  echo "  ✓ S3/MinIO storage secret added"
else
  # STORAGE_BACKEND=local — still create placeholder so services referencing it start cleanly
  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << LOCALSTORAGE_EOF
---
# ── Storage secrets (local PVC — placeholders) ────────────────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: rt19-storage-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  AZURE_STORAGE_ACCOUNT: ""
  AZURE_STORAGE_KEY: ""
LOCALSTORAGE_EOF
  echo "  ✓ Local storage (PVC) — placeholder storage secret created"
fi

# ── Scenario A: imagePullSecret (for non-AKS clusters pulling from ACR) ──────
# When REGISTRY_TOKEN is set, generate an imagePullSecret and inject
# imagePullSecrets into all Deployment pod specs so bare-metal clusters
# (Equinix Metal, kind, k3d) can pull from runtimeaicr.azurecr.io.
REGISTRY_TOKEN="${REGISTRY_TOKEN:-}"
# REGISTRY_USER: username for the registry pull token.
# - ACR tokens (az acr token create): use the token name (e.g. "dp-pull-token")
# - ACR service principals: use "00000000-0000-0000-0000-000000000000"
# Defaults to "00000000-0000-0000-0000-000000000000" for backwards compatibility.
REGISTRY_USER="${REGISTRY_USER:-00000000-0000-0000-0000-000000000000}"
if [ -n "$REGISTRY_TOKEN" ]; then
  # G3 fix: use standard base64-encoded docker config JSON that all K8s distros accept.
  # This matches what `kubectl create secret docker-registry` produces.
  AUTH_B64=$(printf '%s:%s' "${REGISTRY_USER}" "${REGISTRY_TOKEN}" | base64 | tr -d '\n')
  DOCKER_CONFIG_JSON=$(printf '{"auths":{"%s":{"username":"%s","password":"%s","auth":"%s"}}}' \
    "${REGISTRY}" "${REGISTRY_USER}" "${REGISTRY_TOKEN}" "${AUTH_B64}")
  DOCKER_CONFIG=$(printf '%s' "${DOCKER_CONFIG_JSON}" | base64 | tr -d '\n')

  cat >> "$K8S_OUTPUT/00-secrets-generated.yaml" << PULLSECRET_EOF
---
# ── Registry pull secret (Scenario A: bare-metal clusters) ───────────────────
# Allows non-AKS clusters to pull from ${REGISTRY}
# Generated with REGISTRY_USER=${REGISTRY_USER}
# For ACR tokens: set REGISTRY_USER=<token-name> (e.g. dp-pull-token)
# For ACR service principals: REGISTRY_USER=00000000-0000-0000-0000-000000000000
apiVersion: v1
kind: Secret
metadata:
  name: rt19-registry-secret
  namespace: ${NAMESPACE}
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: ${DOCKER_CONFIG}
PULLSECRET_EOF
  echo "  ✓ rt19-registry-secret generated (Scenario A: ACR pull — user=${REGISTRY_USER})"

  # Inject imagePullSecrets into all Deployment pod specs in k8s-configured/
  K8S_OUTPUT="$K8S_OUTPUT" NAMESPACE="$NAMESPACE" python3 - << 'INJECT_EOF'
import os, re

kube_dir = os.environ['K8S_OUTPUT']
for fname in sorted(os.listdir(kube_dir)):
    if not fname.endswith('.yaml'):
        continue
    fpath = os.path.join(kube_dir, fname)
    with open(fpath) as f:
        content = f.read()
    if 'kind: Deployment' not in content or 'imagePullSecrets' in content:
        continue
    updated = re.sub(
        r'(      containers:\n)',
        r'      imagePullSecrets:\n        - name: rt19-registry-secret\n\1',
        content
    )
    if updated != content:
        with open(fpath, 'w') as f:
            f.write(updated)
        print(f'  ✓ imagePullSecrets injected → {fname}')
INJECT_EOF
else
  echo "  ℹ  REGISTRY_TOKEN not set — skipping imagePullSecret (AKS managed identity handles ACR pull)"
fi

# ── A5: NodePort services for ingress-less clusters ───────────────────────
# When SERVICE_TYPE=NodePort, generate a NodePort overlay for the two
# externally-accessible services (control-plane and dashboard).
# Equinix can then reach them at http://<node-ip>:<nodeport>/ without needing
# an ingress controller or cloud load balancer.
SERVICE_TYPE="${SERVICE_TYPE:-ClusterIP}"
if [ "${SERVICE_TYPE}" = "NodePort" ]; then
  cat > "$K8S_OUTPUT/04-nodeport-services.yaml" << NODEPORT_EOF
# Auto-generated by configure-environment.sh (SERVICE_TYPE=NodePort)
# Apply this file INSTEAD of 04-ingress-tls.yaml on clusters without ingress.
# Access the platform at:
#   Control Plane API: http://<node-ip>:30080
#   Dashboard:         http://<node-ip>:30400
---
apiVersion: v1
kind: Service
metadata:
  name: control-plane-nodeport
  namespace: ${NAMESPACE}
  labels:
    app: control-plane
    tier: external-access
spec:
  type: NodePort
  selector:
    app: control-plane
  ports:
    - name: http
      protocol: TCP
      port: 8080
      targetPort: 8080
      nodePort: 30080
---
apiVersion: v1
kind: Service
metadata:
  name: dashboard-nodeport
  namespace: ${NAMESPACE}
  labels:
    app: dashboard
    tier: external-access
spec:
  type: NodePort
  selector:
    app: dashboard
  ports:
    - name: http
      protocol: TCP
      port: 4000
      targetPort: 4000
      nodePort: 30400
NODEPORT_EOF
  echo "  ✓ 04-nodeport-services.yaml generated (SERVICE_TYPE=NodePort)"
  echo "    → Control Plane API: http://<node-ip>:30080"
  echo "    → Dashboard:         http://<node-ip>:30400"
  echo "    ⚠  Skip 04-ingress-tls.yaml — no ingress controller required"
fi

# ── Print summary ──────────────────────────────────────────────────────────
echo ""
if [ "$DEPLOY_MODE" = "dataplane-only" ]; then
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  ✅  DP-Only Manifests generated in: k8s-configured-dp/     ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Hybrid mode — Data Plane only"
  echo "  CP (Control Plane): ${CONTROL_PLANE_URL}"
  echo "  DP namespace:       ${NAMESPACE}"
  echo ""
  echo "  Next steps:"
  echo "  1. Review manifests:  ls ${K8S_OUTPUT}/"
  echo "  2. Create namespace:  kubectl create namespace ${NAMESPACE}"
  echo "  3. Apply secrets:     kubectl apply -f ${K8S_OUTPUT}/00-secrets-generated.yaml"
  echo "  4. Apply DP manifests: kubectl apply -f ${K8S_OUTPUT}/"
  echo "  5. Verify pods:       kubectl get pods -n ${NAMESPACE} -w"
  echo ""
  echo "  DP services deployed:"
  echo "    • flow-enforcer  (Envoy + Wasm — runtime traffic enforcement)"
  echo "    • opa            (Open Policy Agent — local policy evaluation)"
  echo "    • bundle-cache   (OPA bundle cache — syncs from CP at ${CONTROL_PLANE_URL})"
  echo "    • data-proxy     (PII masking / redaction)"
  echo "    • cost-ledger    (budget caps and token tracking)"
  echo "    • waf            (bot mitigation)"
  echo "    • vendor-wrapper (RBAC proxy for 3rd party tools)"
  echo "    • identity-dns   (agent service discovery)"
  echo "    • postgres       (local DP database: dp_audit_log, dp_quota)"
  echo "    • redis          (local DP cache: rate limits)"
else
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  ✅  Manifests generated in: k8s-configured/                ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Next steps:"
  echo "  1. Review generated manifests:  ls ${K8S_OUTPUT}/"
  echo "  2. Create namespace:            kubectl create namespace ${NAMESPACE}"
  echo "  3. Apply secrets first:         kubectl apply -f ${K8S_OUTPUT}/00-secrets-generated.yaml"
  if [ "${SERVICE_TYPE:-ClusterIP}" = "NodePort" ]; then
    echo "  4. Apply manifests (skip ingress): kubectl apply -f ${K8S_OUTPUT}/ --selector='!networking.k8s.io/ingress'"
    echo "     (OR: apply each file except 04-ingress-tls.yaml)"
  else
    echo "  4. Apply all manifests:         kubectl apply -f ${K8S_OUTPUT}/"
  fi
  echo "  5. Verify pods:                 kubectl get pods -n ${NAMESPACE} -w"
fi
echo ""
echo "  ⚠️  00-secrets-generated.yaml contains sensitive values."
echo "     DO NOT commit this file to version control."
echo ""

# Save generated secrets to a secure .env file for reference
SECRETS_LOG="${SCRIPT_DIR}/.env.generated"
cat > "$SECRETS_LOG" << LOG_EOF
# Auto-generated secrets — $(date)
# ⚠️ DO NOT COMMIT THIS FILE — store these in your secrets manager
JWT_SECRET=${JWT_SECRET}
ADMIN_SECRET=${ADMIN_SECRET}
API_KEY_SECRET=${API_KEY_SECRET}
SESSION_SECRET=${SESSION_SECRET}
STORAGE_SIGNING_SECRET=${STORAGE_SIGNING_SECRET}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
LOG_EOF
chmod 600 "$SECRETS_LOG"
echo "  📝 Generated secrets saved to: .env.generated (chmod 600)"

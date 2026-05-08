#!/usr/bin/env bash
# OPER_RT19-087g/p — Multi-cloud install script for partner-operated
# RuntimeAI white-label deployments (Model B).
#
# Usage:
#   ./install.sh --cloud [gcp|aws|azure|quickstart] [--namespace runtimeai] [--license license.jwt]
#
# Cloud-specific managed-service expectations:
#   gcp        : Cloud SQL (Postgres 15+), Memorystore (Redis 7), GCS bucket
#   aws        : RDS Postgres, ElastiCache, S3
#   azure      : Azure Database for PostgreSQL, Azure Cache for Redis, Blob
#   quickstart : single-node Postgres + Redis as in-cluster StatefulSets.
#                NEVER for production; intended for partner POC + dev.
#
# Required env vars in CSV file at ./env (or set in shell before run):
#   DATABASE_URL              postgres://...
#   REDIS_URL                 redis://...
#   BLOB_BUCKET               name of object-store bucket
#   PARTNER_CLIENT_ID         from RuntimeAI Partner Admin Portal
#   PARTNER_CLIENT_SECRET     from RuntimeAI Partner Admin Portal
#   RUNTIMEAI_DOMAIN          e.g. platform.scorpius.com
#   RUNTIMEAI_INSTANCE_TYPE   "cp" | "dp"
#   RUNTIMEAI_INSTANCE_ID     human label, e.g. cp-us-east

set -euo pipefail

CLOUD=""
NAMESPACE="runtimeai"
LICENSE="license.jwt"
HELM_DIR="$(cd "$(dirname "$0")"/helm && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 --cloud [gcp|aws|azure|quickstart] [--namespace ns] [--license path]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)     CLOUD="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --license)   LICENSE="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "unknown arg: $1"; usage ;;
  esac
done

[[ -z "$CLOUD" ]] && usage

case "$CLOUD" in
  gcp|aws|azure|quickstart) ;;
  *) echo "ERROR: --cloud must be gcp, aws, azure, or quickstart"; exit 2 ;;
esac

if [[ ! -f "$LICENSE" ]]; then
  echo "ERROR: license file not found at $LICENSE"; exit 2
fi

# Verify tarball SHA256 (Gap 24 — supply-chain integrity).
# P0-I fix: macOS uses `shasum`, Linux containers use `sha256sum`. Probe both.
sha256_check() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$1"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "$1"
  else
    echo "ERROR: neither sha256sum nor shasum found in PATH"
    return 1
  fi
}
if [[ -f "$SCRIPT_DIR/../sha256.txt" && -f "$SCRIPT_DIR/../runtimeai-whitelabel-"*.tar.gz ]]; then
  echo "→ verifying tarball checksum"
  (cd "$SCRIPT_DIR/.." && sha256_check sha256.txt) || {
    echo "ERROR: checksum verification failed"; exit 1
  }
fi

# Pre-flight env vars.
required=(DATABASE_URL REDIS_URL PARTNER_CLIENT_ID PARTNER_CLIENT_SECRET \
          RUNTIMEAI_DOMAIN RUNTIMEAI_INSTANCE_TYPE RUNTIMEAI_INSTANCE_ID)
missing=0
for v in "${required[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "missing env var: $v"
    missing=1
  fi
done
[[ "$missing" -eq 1 ]] && { echo "set required vars then re-run"; exit 2; }

# Cluster UID (used in fingerprint).
RUNTIMEAI_CLUSTER_UID="$(kubectl get ns kube-system -o jsonpath='{.metadata.uid}')"
[[ -z "$RUNTIMEAI_CLUSTER_UID" ]] && { echo "ERROR: cannot read cluster UID"; exit 2; }

kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

# License Secret.
kubectl -n "$NAMESPACE" create secret generic runtimeai-license \
  --from-file=license.jwt="$LICENSE" \
  --dry-run=client -o yaml | kubectl apply -f -

# Partner credentials Secret.
kubectl -n "$NAMESPACE" create secret generic runtimeai-partner-creds \
  --from-literal=PARTNER_CLIENT_ID="$PARTNER_CLIENT_ID" \
  --from-literal=PARTNER_CLIENT_SECRET="$PARTNER_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# Database/Redis/Blob URLs.
kubectl -n "$NAMESPACE" create secret generic runtimeai-config \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=REDIS_URL="$REDIS_URL" \
  --from-literal=BLOB_BUCKET="${BLOB_BUCKET:-}" \
  --from-literal=RUNTIMEAI_DOMAIN="$RUNTIMEAI_DOMAIN" \
  --from-literal=RUNTIMEAI_INSTANCE_TYPE="$RUNTIMEAI_INSTANCE_TYPE" \
  --from-literal=RUNTIMEAI_INSTANCE_ID="$RUNTIMEAI_INSTANCE_ID" \
  --from-literal=RUNTIMEAI_CLUSTER_UID="$RUNTIMEAI_CLUSTER_UID" \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply the cloud-specific Helm overlay.
VALUES="$HELM_DIR/values.yaml"
case "$CLOUD" in
  gcp)        VALUES="$VALUES,$HELM_DIR/values-gcp.yaml" ;;
  aws)        VALUES="$VALUES,$HELM_DIR/values-aws.yaml" ;;
  azure)      VALUES="$VALUES,$HELM_DIR/values-azure.yaml" ;;
  quickstart)
    echo "⚠ quickstart mode — deploying single-node Postgres + Redis StatefulSets"
    echo "⚠ NOT for production"
    VALUES="$VALUES,$HELM_DIR/values-quickstart.yaml"
    ;;
esac

helm upgrade --install runtimeai "$HELM_DIR" \
  --namespace "$NAMESPACE" \
  --values "$(echo "$VALUES" | tr ',' '\n' | head -1)" \
  $(echo "$VALUES" | tr ',' '\n' | tail -n +2 | sed 's/^/--values /')

echo
echo "✓ install complete on cloud=$CLOUD ns=$NAMESPACE"
echo "  Verify CP: kubectl -n $NAMESPACE get pods -l app=control-plane"
echo "  Verify call-home: kubectl -n $NAMESPACE logs -l app=control-plane | grep callhome"
echo
echo "  After ~2min, the Partner Admin Portal at https://admin.runtimeai.io/partner-admin"
echo "  Customers tab should show this deployment under your partner row."

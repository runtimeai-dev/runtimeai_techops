#!/usr/bin/env bash
# F9-C — rotate the mcp_readonly Postgres password.
#
# Generates a new password, updates Azure Key Vault, ALTERs the role in
# Postgres, refreshes the K8s Secret, then rolls the postgresql server
# pod so it picks up the new DATABASE_URL_READONLY.
set -euo pipefail

KV_NAME="${KV_NAME:-runtimeai-rt19-kv}"
KV_KEY="MCP-READONLY-PASSWORD"
NS="${NS:-rt19}"
SECRET_NAME="mcp-server-postgresql-secrets"
PG_POD="${PG_POD:-postgres-0}"
PG_SUPERUSER="${PG_SUPERUSER:-runtimeai}"
DB_HOST="postgres.${NS}.svc.cluster.local"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-authzion}"

NEW_PWD="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-24)"
echo "[F9-C] generated new mcp_readonly password (len=${#NEW_PWD})"

az keyvault secret set --vault-name "$KV_NAME" --name "$KV_KEY" --value "$NEW_PWD" >/dev/null
echo "[F9-C] stored in Key Vault: ${KV_NAME}/${KV_KEY}"

kubectl exec -n "$NS" "$PG_POD" -- psql -U "$PG_SUPERUSER" -d "$DB_NAME" -c \
  "ALTER USER mcp_readonly WITH PASSWORD '${NEW_PWD}';" >/dev/null
echo "[F9-C] ALTER USER applied"

NEW_DSN="postgresql://mcp_readonly:${NEW_PWD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=disable"
kubectl create secret generic "$SECRET_NAME" -n "$NS" \
  --from-literal=DATABASE_URL_READONLY="$NEW_DSN" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "[F9-C] K8s Secret refreshed"

kubectl rollout restart deployment/mcp-server-postgresql -n "$NS"
kubectl rollout status  deployment/mcp-server-postgresql -n "$NS" --timeout=120s
echo "[F9-C] mcp-server-postgresql rolled with new credential"

echo "[F9-C] verifying connectivity..."
POD="$(kubectl -n "$NS" get pod -l app=mcp-server-postgresql -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$NS" exec "$POD" -- wget -qO- http://localhost:7401/healthz | head -2 || true
echo "[F9-C] done."

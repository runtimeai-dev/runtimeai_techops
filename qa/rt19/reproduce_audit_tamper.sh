#!/bin/bash
API_URL="http://localhost:8080"
API_KEY="${AUDITOR_API_KEY:-runtimeai-auditor-dev-key-2026}"
TENANT_ID="acme-corp"

echo "Verifying Audit Chain for $TENANT_ID..."

curl -s "${API_URL}/api/audit/verify?tenant_id=${TENANT_ID}" \
  -H "X-API-Key: ${API_KEY}" | jq .

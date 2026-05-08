#!/bin/bash
source "$(dirname "$0")/common.sh"

echo -e "${GREEN}=== Supply Chain Security Verification ===${NC}"

AGENT_NAME="sc-agent-v1"
TENANT_ID="${TENANT_ID:-bank-a}"

log "Ensuring Agent '$AGENT_NAME' exists..."
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "INSERT INTO agents (agent_id, name, tenant_id, status, owner, environment, skills) VALUES ('$AGENT_NAME', '$AGENT_NAME', '$TENANT_ID', 'REGISTERED', 'admin', 'production', '[]') ON CONFLICT (tenant_id, agent_id) DO NOTHING;"

# Login first
login

log "1. Testing Image Verification (Expect Success for signed image)..."
# Using publicly signed image
SIGNED_IMAGE="gcr.io/projectsigstore/cosign:v2.2.3"

RESP=$(auth_curl -X POST "${CONTROL_PLANE_URL}/api/agents/$AGENT_NAME/verify-image" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d "{\"image_ref\": \"$SIGNED_IMAGE\"}")

echo "Verify Response: $RESP"
if echo "$RESP" | grep -q "true"; then
  log "[PASS] Verification Succeeded"
else
  log "[FAIL] Verification Failed (Check container logs/network)"
fi

log "2. Testing SBOM Ingestion..."
SBOM_DATA='{"SPDXID": "SPDXRef-DOCUMENT", "spdxVersion": "SPDX-2.3", "creationInfo": { "created": "2023-11-02T12:00:00Z", "creators": ["Tool: Syft"] }}'

RESP=$(auth_curl -X POST "${CONTROL_PLANE_URL}/api/agents/$AGENT_NAME/sbom" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d "$SBOM_DATA")

echo "SBOM Response: $RESP"
if echo "$RESP" | grep -q "ingested"; then
    log "[PASS] SBOM Ingested"
else
    log "[FAIL] SBOM Ingestion Failed"
fi

log "3. Checking Status..."
RESP=$(auth_curl -X GET "${CONTROL_PLANE_URL}/api/agents/$AGENT_NAME/supply-chain" \
    -H "Content-Type: application/json" \
    -H "X-Tenant-ID: $TENANT_ID")

echo "Status Response: $RESP"

if echo "$RESP" | grep -q "active"; then
    echo "OK"
fi

echo -e "${GREEN}=== Verification Complete ===${NC}"

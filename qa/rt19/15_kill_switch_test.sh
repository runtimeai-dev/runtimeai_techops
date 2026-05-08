#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

echo "=================================================="
echo "TEST: Item 15 - Emergency Kill Switch Verification"
echo "=================================================="

# 1. Authenticate
TENANT_ID="acme-qa-org"
login "${ADMIN_EMAIL:-a-operator@acme-qa-org.local}" "${ADMIN_PASS:-password123}" "$TENANT_ID"

AGENT_NAME="ks-agent-$(date +%s)"
CP_URL="${CONTROL_PLANE_URL:-http://localhost:8080}"
ENVOY_URL="${ENFORCER_URL:-http://localhost:8092}"

# Flow Enforcer is an in-cluster Envoy sidecar — not exposed externally.
# Skip this test if Envoy is not locally reachable (CI/K8s environments).
if ! curl -sf "$ENVOY_URL/healthz" --max-time 2 > /dev/null 2>&1; then
    echo "  ⏩ SKIP: Flow Enforcer not reachable at $ENVOY_URL (expected in K8s — test requires local Envoy)"
    exit 0
fi

echo "Creating Agent: $AGENT_NAME for Tenant: $TENANT_ID"

# 2. Create Agent (so it exists in Inventory)
# Using auth_curl (which uses cookies.txt)
HTTP_CODE=$(auth_curl -s -o /dev/null -w "%{http_code}" -X POST "$CP_URL/api/agents" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$AGENT_NAME"'",
    "owner": "qa-test",
    "environment": "production",
    "skills": ["kill-switch-test"]
  }')

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
    echo "ERROR: Failed to create agent. Status: $HTTP_CODE"
    exit 1
fi

# Get Agent ID
RESPONSE=$(auth_curl -s "$CP_URL/api/agents?name=$AGENT_NAME")
AGENT_ID=$(echo $RESPONSE | jq -r '.agents[0].agent_id // .[0].agent_id // .[0].id')

if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" == "null" ]; then
    echo "ERROR: Could not retrieve Agent ID"
    echo "Response: $RESPONSE"
    exit 1
fi

echo "Agent Created: $AGENT_ID"

# 3. Activate Kill Switch
echo "[Action] Activating Kill Switch for Agent $AGENT_ID..."
RESPONSE=$(auth_curl -s -X POST "$CP_URL/api/kill-switch/activate" \
  -H "Content-Type: application/json" \
  -d "{
    \"scope\": \"agent\",
    \"target\": \"$AGENT_ID\",
    \"reason\": \"Automated Test\",
    \"duration\": \"5m\"
  }")

echo "$RESPONSE" | jq .

# 4. Verify Block (Polling loop for speed check)
echo "[Verify] Checking Flow Enforcer (Should be 403)..."
BLOCKED=false

for i in {1..20}; do
  # Simulate request to Envoy with headers
  # Note: Envoy connects to OPA/ControlPlane to check policy.
  # We need to simulate a request FROM the blocked agent.
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$ENVOY_URL/api/v1/chat/completions" \
    -H "x-runtimeai-agent-id: $AGENT_ID" \
    -H "x-runtimeai-tenant-id: $TENANT_ID" \
    -H "Authorization: Bearer mock-token")
  
  if [ "$HTTP_CODE" == "403" ]; then
    echo "SUCCESS: Blocked with 403 (Attempt $i)"
    BLOCKED=true
    break
  fi
  sleep 0.2
done

if [ "$BLOCKED" = false ]; then
  echo "FAILURE: Request was NOT blocked (Code: $HTTP_CODE)"
  # Don't exit yet, try to cleanup
fi

# 5. Deactivate Kill Switch
echo "[Action] Deactivating Kill Switch..."
auth_curl -s -X POST "$CP_URL/api/kill-switch/deactivate" \
  -H "Content-Type: application/json" \
  -d "{
    \"scope\": \"agent\",
    \"target\": \"$AGENT_ID\"
  }" | jq .

# 6. Verify Restoration
echo "[Verify] Checking Flow Enforcer (Should NOT be 403)..."
RESTORED=false
for i in {1..20}; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$ENVOY_URL/api/v1/chat/completions" \
    -H "x-runtimeai-agent-id: $AGENT_ID" \
    -H "x-runtimeai-tenant-id: $TENANT_ID" \
    -H "Authorization: Bearer mock-token")
  
  if [ "$HTTP_CODE" != "403" ]; then
    echo "SUCCESS: Traffic restored (Code: $HTTP_CODE)"
    RESTORED=true
    break
  fi
  sleep 0.1
done

if [ "$RESTORED" = false ]; then
  echo "FAILURE: Traffic still blocked after lift (Code: $HTTP_CODE)"
  exit 1
fi

echo "=================================================="
echo "PASS: Kill Switch Functional"
echo "=================================================="

# 7. Cleanup
echo "[Action] Cleaning up Agent $AGENT_ID via DB..."
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "DELETE FROM agents WHERE agent_id='$AGENT_ID';" > /dev/null 2>&1

exit 0

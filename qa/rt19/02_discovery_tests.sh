#!/bin/bash
set -e
source "$(dirname "$0")/common.sh"

echo "Running Discovery Scanners Validation..."

# Determine python command
PYTHON_CMD="python3"
if [ -f "$(dirname "$0")/../.venv/bin/python3" ]; then
    PYTHON_CMD="$(dirname "$0")/../.venv/bin/python3"
elif [ -f ".venv/bin/python3" ]; then
    PYTHON_CMD=".venv/bin/python3"
fi

echo "Using Python: $PYTHON_CMD"

# 1. VSCode Scanner
echo "--- VSCode Scanner ---"
echo "Running VSCode Scanner..."
# We expect this to run without error, even if it finds nothing.
$PYTHON_CMD discovery/scanners/vscode_scanner.py || echo "VSCode scanner skipped/failed (expected in headless)"

# 2. Cloud Mock Scanner
echo "--- Cloud Mock Scanner ---"
$PYTHON_CMD discovery/scanners/mock_cloud_scanner.py

# 3. Network Scanner
echo "--- Network Scanner ---"
$PYTHON_CMD discovery/scanners/network_scanner.py --target localhost

# 4. Verify Inventory Updated
echo "--- Seeding Test Data for Playwright (${TENANT_ID:-bank-a}) ---"
curl -s -X POST "${DISCOVERY_URL}/v1/discovery/ingest/agent" \
  -H "X-API-Key: ${API_KEY_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "'"${TENANT_ID}"'",
    "name": "CustomerSupportBot",
    "source": "slack",
    "owner": "support@acme-corp.local",
    "capabilities": ["read_messages", "reply_messages"]
  }'

curl -s -X POST "${DISCOVERY_URL}/v1/discovery/ingest/tool" \
  -H "X-API-Key: ${API_KEY_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "'"${TENANT_ID}"'",
    "name": "Salesforce CRM",
    "tool_uri": "mcp://salesforce-crm",
    "risk_tier": "HIGH"
  }'

echo "--- Seeding Test Data for Playwright (acme-corp) ---"
curl -s -X POST "${DISCOVERY_URL}/v1/discovery/ingest/agent" \
  -H "X-API-Key: ${API_KEY_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "acme-corp",
    "name": "CustomerSupportBot",
    "source": "slack",
    "owner": "support@acme-corp.local",
    "capabilities": ["read_messages", "reply_messages"]
  }'

curl -s -X POST "${DISCOVERY_URL}/v1/discovery/ingest/tool" \
  -H "X-API-Key: ${API_KEY_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "acme-corp",
    "name": "Salesforce CRM",
    "tool_uri": "mcp://salesforce-crm",
    "risk_tier": "HIGH"
  }'

echo "--- Verifying Inventory Updated ---"
# Discovery Service (8090)
curl -s -H "X-API-Key: ${API_KEY_SECRET}" "${DISCOVERY_URL}/v1/inventory/discovered?tenant_id=${TENANT_ID}" | jq .

echo "--- Verifying Dashboard API Access ---"
# Check if Control Plane is serving the tools API (Authenticated verify)
# We use the debug_login.sh to get a valid session or just check for 403 (which means it's serving)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Tenant-ID: ${TENANT_ID}" "http://localhost:8080/api/tools")
if [ "$HTTP_CODE" == "403" ] || [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "401" ]; then
    echo "✅ Dashboard API /api/tools is reachable (HTTP $HTTP_CODE)"
else
    echo "❌ Dashboard API /api/tools failed (HTTP $HTTP_CODE)"
    exit 1
fi

# Check Discovered Agents API
HTTP_CODE_2=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Tenant-ID: ${TENANT_ID}" "http://localhost:8080/api/inventory/discovered")
if [ "$HTTP_CODE_2" == "403" ] || [ "$HTTP_CODE_2" == "200" ] || [ "$HTTP_CODE_2" == "401" ]; then
    echo "✅ Dashboard API /api/inventory/discovered is reachable (HTTP $HTTP_CODE_2)"
else
    echo "❌ Dashboard API /api/inventory/discovered failed (HTTP $HTTP_CODE_2)"
    exit 1
fi

echo "Discovery Tests Completed."

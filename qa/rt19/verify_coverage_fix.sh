#!/bin/bash
echo "Testing Kill Switch Audit..."
curl -s -X POST http://localhost:8080/api/kill-switch/activate \
  -H "Content-Type: application/json" \
  -H "X-API-Key: runtimeai-dev-secret-2026" \
  -H "X-Tenant-ID: acme-corp" \
  -d '{"scope":"agent","target":"TestBot","reason":"Audit Test","duration":"1h"}'

echo ""
echo "Testing Tools Creation Audit..."
curl -s -X POST http://localhost:8080/api/tools \
  -H "Content-Type: application/json" \
  -H "X-API-Key: acme-operator-key" \
  -H "X-Tenant-ID: acme-corp" \
  -d '{"tool_id":"audit-test-tool-4","uri":"mcp://audit-test-4","tenant_id":"acme-corp","risk_tier":"LOW"}'

echo ""
echo "Checking Audit Logs for new events..."
sleep 2
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "SELECT actor, action, target, created_at FROM audit_logs WHERE action IN ('activate_kill_switch', 'create_tool') ORDER BY created_at DESC;"

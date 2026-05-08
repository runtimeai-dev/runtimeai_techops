#!/bin/bash
echo "Setting Budget..."
curl -s -X POST http://localhost:8080/api/budgets -H "X-API-Key: runtimeai-dev-secret-2026" -H "Content-Type: application/json" -d '{"tenant_id": "acme-corp", "agent_id": "CustomerSupportBot", "max_tokens_per_day": 1000000}'
echo ""
echo "Decommissioning Agent..."
curl -s -X POST http://localhost:8080/api/lifecycle/decommission -H "X-API-Key: runtimeai-dev-secret-2026" -H "Content-Type: application/json" -d '{"tenant_id": "acme-corp", "agent_id": "DataAnalystBot"}'
echo ""
echo "Checking Audit Logs..."
sleep 2 # Wait for write
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "SELECT actor, action, target, created_at FROM audit_logs WHERE action IN ('set_budget', 'decommission_agent') ORDER BY created_at DESC;"

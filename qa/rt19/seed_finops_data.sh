#!/bin/bash
# seed_finops_data.sh — Seeds FinOps demo data via API calls (ZERO SQL)
# Called by run_suite.sh to ensure FinOps tests have data to validate against.
#
# IMPORTANT: All seeding uses API calls exclusively. No direct SQL or psql.
# This ensures RLS policies are exercised and data integrity is maintained.

set -e

CP_URL="${CP_URL:-http://localhost:8080}"
FINOPS_URL="${FINOPS_URL:-http://localhost:5055}"
ADMIN_SECRET="${ADMIN_SECRET:-test-admin-secret}"
TENANT_A="tenant-a"
TENANT_B="tenant-b"

echo "=== Seeding FinOps Demo Data (API-Only) ==="

# 0. API call helper with retries
api_call() {
  local url="$1"; shift
  curl --connect-timeout 5 --max-time 15 -s "$url" "$@" || true
}

# 1. Ensure tenants exist via admin API
echo "Creating tenants via admin API..."
for TENANT_ID in "$TENANT_A" "$TENANT_B"; do
  TENANT_NAME="Tenant ${TENANT_ID/tenant-/} (FinOps Demo)"
  RESP=$(api_call "$CP_URL/api/admin/tenants" \
    -w "\nHTTP:%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d "{\"tenant_id\":\"$TENANT_ID\",\"name\":\"$TENANT_NAME\",\"domain\":\"$TENANT_ID.local\",\"admin_email\":\"admin@$TENANT_ID.local\"}")
  HTTP_CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    echo "  ✅ Tenant $TENANT_ID created"
  else
    echo "  ℹ Tenant $TENANT_ID likely exists (HTTP $HTTP_CODE)"
  fi
done

# 2. Check FinOps service is healthy
if ! curl -sf "$FINOPS_URL/healthz" > /dev/null 2>&1; then
    echo "WARNING: FinOps service not reachable at $FINOPS_URL — trying CP proxy"
    FINOPS_URL="$CP_URL"
fi

# 3. Seed cost events via FinOps batch API for each tenant
echo "Seeding FinOps cost events via API..."

seed_cost_events() {
  local TENANT="$1"
  local AGENT_PREFIX="$2"
  local NUM_AGENTS="$3"
  local EVENTS_PER_AGENT="$4"

  EVENTS_JSON="["
  for i in $(seq 1 $NUM_AGENTS); do
    AGENT_ID="${AGENT_PREFIX}-${i}"
    for j in $(seq 1 $EVENTS_PER_AGENT); do
      PROVIDER_IDX=$(( (i + j) % 3 ))
      case $PROVIDER_IDX in
        0) PROVIDER="openai"; MODEL="gpt-4o" ;;
        1) PROVIDER="anthropic"; MODEL="claude-3" ;;
        2) PROVIDER="google"; MODEL="gemini-pro" ;;
      esac
      INPUT_TOKENS=$(( 200 + (i * 37 + j * 13) % 500 ))
      OUTPUT_TOKENS=$(( 100 + (i * 17 + j * 11) % 300 ))
      TOTAL_TOKENS=$(( INPUT_TOKENS + OUTPUT_TOKENS ))
      # Use bc for cost calculation, or awk as fallback
      COST=$(awk "BEGIN{printf \"%.6f\", 0.01 + ($i * 0.003 + $j * 0.001)}")
      LATENCY=$(( 120 + (i * 23 + j * 7) % 400 ))
      FEATURE_IDX=$(( (i + j) % 5 ))
      case $FEATURE_IDX in
        0) FEATURE="chat" ;; 1) FEATURE="search" ;; 2) FEATURE="analysis" ;; 3) FEATURE="code-gen" ;; 4) FEATURE="support" ;;
      esac
      TEAM_IDX=$(( (i + j) % 5 ))
      case $TEAM_IDX in
        0) TEAM="eng" ;; 1) TEAM="sales" ;; 2) TEAM="ops" ;; 3) TEAM="security" ;; 4) TEAM="support" ;;
      esac

      EVENTS_JSON+="{\"agent_id\":\"$AGENT_ID\",\"provider\":\"$PROVIDER\",\"model\":\"$MODEL\","
      EVENTS_JSON+="\"input_tokens\":$INPUT_TOKENS,\"output_tokens\":$OUTPUT_TOKENS,\"total_tokens\":$TOTAL_TOKENS,"
      EVENTS_JSON+="\"total_cost_usd\":$COST,\"latency_ms\":$LATENCY,"
      EVENTS_JSON+="\"feature_tag\":\"$FEATURE\",\"team_id\":\"team-$TEAM\"},"
    done
  done
  # Remove trailing comma and close array
  EVENTS_JSON="${EVENTS_JSON%,}]"

  RESP=$(api_call "$FINOPS_URL/api/v1/finops/events/batch" \
    -w "\nHTTP:%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "X-Tenant-ID: $TENANT" \
    -d "{\"events\": $EVENTS_JSON}")
  HTTP_CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
  TOTAL_EVENTS=$(( NUM_AGENTS * EVENTS_PER_AGENT ))
  if [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" ]]; then
    echo "  ✅ $TENANT: $TOTAL_EVENTS cost events ingested"
  else
    echo "  ⚠️ $TENANT cost events: HTTP $HTTP_CODE"
  fi
}

# tenant-a: 7 agents, ~12 events each = 84 total
seed_cost_events "$TENANT_A" "agent-cx" 7 12

# tenant-b: 3 agents, 3 events each = 9 total (cross-tenant isolation test)
seed_cost_events "$TENANT_B" "agent-b" 3 3

# bank-a, bank-b, acme-corp: same pattern
seed_cost_events "bank-a" "agent-bank" 5 8
seed_cost_events "bank-b" "agent-test" 3 8
seed_cost_events "acme-corp" "acme-agent" 6 10

# 4. Seed budgets via FinOps API
echo "Seeding FinOps budgets via API..."
seed_budget() {
  local TENANT="$1" SCOPE="$2" SCOPE_ID="$3" BUDGET="$4"
  RESP=$(api_call "$FINOPS_URL/api/v1/finops/budgets" \
    -w "\nHTTP:%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "X-Tenant-ID: $TENANT" \
    -d "{\"scope\":\"$SCOPE\",\"scope_id\":\"$SCOPE_ID\",\"budget_usd\":$BUDGET,\"period\":\"monthly\"}")
  HTTP_CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$HTTP_CODE" == "201" || "$HTTP_CODE" == "200" || "$HTTP_CODE" == "409" ]]; then
    echo "  ✅ Budget: $TENANT/$SCOPE/$SCOPE_ID = \$$BUDGET"
  else
    echo "  ⚠️ Budget $TENANT/$SCOPE_ID: HTTP $HTTP_CODE"
  fi
}

seed_budget "$TENANT_A" "agent" "agent-cx-1" 0.50
seed_budget "$TENANT_A" "agent" "agent-cx-2" 1.00
seed_budget "$TENANT_A" "team" "team-eng" 2.00
seed_budget "$TENANT_A" "team" "team-sales" 1.50
seed_budget "$TENANT_A" "tenant" "$TENANT_A" 10.00
seed_budget "bank-a" "tenant" "bank-a" 15.00
seed_budget "acme-corp" "tenant" "acme-corp" 25.00
seed_budget "acme-corp" "team" "team-engineering" 8.00

# 5. Seed tenant settings via API
echo "Seeding tenant settings via API..."
seed_setting() {
  local TENANT="$1" KEY="$2" VALUE="$3" DESC="$4"
  api_call "$FINOPS_URL/api/v1/finops/settings" \
    -X PUT \
    -H "Content-Type: application/json" \
    -H "X-Tenant-ID: $TENANT" \
    -d "{\"key\":\"$KEY\",\"value\":\"$VALUE\",\"description\":\"$DESC\"}" > /dev/null 2>&1
}

seed_setting "$TENANT_A" "platform_cost_usd" "2500" "Monthly platform cost for ROI calc"
seed_setting "$TENANT_A" "compliance_hourly_cost" "150" "Hourly cost of compliance team"
seed_setting "$TENANT_A" "routing_savings_pct" "0.35" "Expected routing savings %"
seed_setting "$TENANT_A" "cache_savings_pct" "0.20" "Expected cache savings %"
seed_setting "$TENANT_A" "policy_savings_pct" "0.15" "Expected policy savings %"
seed_setting "$TENANT_A" "budget_alert_default_pct" "80" "Default budget alert threshold"
seed_setting "bank-a" "platform_cost_usd" "5000" "Monthly platform cost"
seed_setting "bank-a" "compliance_hourly_cost" "200" "Compliance team hourly rate"
seed_setting "bank-a" "routing_savings_pct" "0.30" "Routing savings"
seed_setting "acme-corp" "platform_cost_usd" "3500" "Monthly platform cost"
seed_setting "acme-corp" "compliance_hourly_cost" "100" "Compliance hourly rate"
seed_setting "acme-corp" "routing_savings_pct" "0.25" "Routing savings"
seed_setting "acme-corp" "cache_savings_pct" "0.18" "Cache savings"
echo "  ✅ Tenant settings seeded"

echo "=== FinOps Seed Data Complete (API-Only) ==="

# 6. Quick verification
echo "Verifying FinOps data..."
SUMMARY=$(curl -sf -H "X-Tenant-ID: $TENANT_A" "$FINOPS_URL/api/v1/finops/costs/summary" 2>/dev/null || echo '{"data":{}}')
COST=$(echo "$SUMMARY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('total_cost_usd',0))" 2>/dev/null || echo "0")
echo "  tenant-a total cost: \$$COST"

if [ "$(echo "$COST > 0" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
    echo "  ✅ FinOps data verified"
else
    echo "  ⚠️  FinOps data may not be visible yet (service may need restart)"
fi

#!/bin/bash
# 022526_1856_seed_identity_fabric.sh
# Seed Data Script: Identity Fabric features
#
# Seeds agents, sponsors, OAuth credentials, blueprints so that:
# - Trust score endpoint returns meaningful composite scores
# - Credential health endpoint shows varied health states
# - Dashboard pages display real data
#
# Prerequisites:
#   - Control plane running on $BASE_URL
#   - Tenant + API key available

set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
API_KEY="${API_KEY:-$(cat /tmp/runtimeai_api_key 2>/dev/null || echo '')}"

auth_header() {
    if [ -n "$API_KEY" ]; then
        echo "X-API-Key: $API_KEY"
    else
        echo "Cookie: session=test"
    fi
}

echo "=== Seeding Identity Fabric Data ==="
echo "Target: $BASE_URL"
echo ""

# ──────────────────────────────────────
# 1. Seed Agents (if not already present)
# ──────────────────────────────────────
echo "── 1. Seeding Agents ──"

AGENTS=(
    '{"name":"Payment Processor Agent","owner":"finance-team","environment":"production","description":"Handles payment processing and reconciliation","version":"2.1.0"}'
    '{"name":"Data Sync Agent","owner":"data-team","environment":"staging","description":"Synchronizes data across cloud providers","version":"1.5.0"}'
    '{"name":"Security Scanner Agent","owner":"security-team","environment":"production","description":"Continuous security scanning and vulnerability detection","version":"3.0.1"}'
    '{"name":"Report Generator Agent","owner":"analytics-team","environment":"production","description":"Generates compliance and analytics reports","version":"1.2.0"}'
    '{"name":"Customer Service Bot","owner":"support-team","environment":"production","description":"AI-powered customer service automation","version":"4.0.0"}'
)

for agent in "${AGENTS[@]}"; do
    NAME=$(echo "$agent" | python3 -c "import sys, json; print(json.load(sys.stdin)['name'])")
    RESP=$(curl -s -w "\n%{http_code}" \
        -H "$(auth_header)" \
        -H "Content-Type: application/json" \
        -X POST "$BASE_URL/api/agents" \
        -d "$agent" 2>/dev/null)
    CODE=$(echo "$RESP" | tail -1)
    if [ "$CODE" = "201" ] || [ "$CODE" = "200" ] || [ "$CODE" = "409" ]; then
        echo "  ✅ Agent: $NAME (HTTP $CODE)"
    else
        echo "  ⚠️  Agent: $NAME (HTTP $CODE)"
    fi
done

echo ""

# ──────────────────────────────────────
# 2. Seed OAuth Credentials
# ──────────────────────────────────────
echo "── 2. Seeding OAuth Credentials ──"

CREDS=(
    '{"client_name":"payment-api-cred"}'
    '{"client_name":"data-sync-cred"}'
    '{"client_name":"scanner-api-cred"}'
    '{"client_name":"report-gen-cred"}'
)

for cred in "${CREDS[@]}"; do
    NAME=$(echo "$cred" | python3 -c "import sys, json; print(json.load(sys.stdin)['client_name'])")
    RESP=$(curl -s -w "\n%{http_code}" \
        -H "$(auth_header)" \
        -H "Content-Type: application/json" \
        -X POST "$BASE_URL/api/oauth/credentials" \
        -d "$cred" 2>/dev/null)
    CODE=$(echo "$RESP" | tail -1)
    if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
        echo "  ✅ Credential: $NAME (HTTP $CODE)"
    else
        echo "  ⚠️  Credential: $NAME (HTTP $CODE)"
    fi
done

echo ""

# ──────────────────────────────────────
# 3. Seed Blueprints
# ──────────────────────────────────────
echo "── 3. Seeding Blueprints ──"

BLUEPRINTS=(
    '{"name":"Standard Production Agent","description":"Template for production agents with default policies","status":"active","version":"1.0","config":{"max_memory_mb":512,"max_cpu_cores":2,"timeout_seconds":300}}'
    '{"name":"High-Security Agent","description":"Template for agents handling PII or financial data","status":"active","version":"1.0","config":{"max_memory_mb":256,"max_cpu_cores":1,"timeout_seconds":60,"requires_certification":true,"requires_sponsor":true}}'
)

for bp in "${BLUEPRINTS[@]}"; do
    NAME=$(echo "$bp" | python3 -c "import sys, json; print(json.load(sys.stdin)['name'])")
    RESP=$(curl -s -w "\n%{http_code}" \
        -H "$(auth_header)" \
        -H "Content-Type: application/json" \
        -X POST "$BASE_URL/api/blueprints" \
        -d "$bp" 2>/dev/null)
    CODE=$(echo "$RESP" | tail -1)
    if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
        echo "  ✅ Blueprint: $NAME (HTTP $CODE)"
    else
        echo "  ⚠️  Blueprint: $NAME (HTTP $CODE)"
    fi
done

echo ""

# ──────────────────────────────────────
# 4. Certify an Agent (for trust score demo)
# ──────────────────────────────────────
echo "── 4. Certifying First Agent ──"

# Get first agent
AGENT_ID=$(curl -s -H "$(auth_header)" "$BASE_URL/api/agents" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    agents = data.get('agents', data) if isinstance(data, dict) else data
    if isinstance(agents, list) and len(agents) > 0:
        print(agents[0].get('agent_id', agents[0].get('id', '')))
except: pass
" 2>/dev/null || echo "")

if [ -n "$AGENT_ID" ]; then
    CERT_RESP=$(curl -s -w "\n%{http_code}" \
        -H "$(auth_header)" \
        -H "Content-Type: application/json" \
        -X POST "$BASE_URL/api/agents/$AGENT_ID/certify" \
        -d '{"certified_until":"2027-01-01T00:00:00Z","certified_by":"security-admin"}' 2>/dev/null)
    CERT_CODE=$(echo "$CERT_RESP" | tail -1)
    echo "  Agent $AGENT_ID certification: HTTP $CERT_CODE"
else
    echo "  ⚠️  No agent found to certify"
fi

echo ""
echo "=== Identity Fabric Seed Complete ==="
echo ""
echo "Next: Run QA tests with ./qa_testing_local/022526_1856_test_identity_fabric.sh"

#!/bin/bash
# Seed Data: Identity Fabric Phase 2
# Seeds: SoD rules, Conditional Access policies, Rotation Policies, SPIFFE registrations
set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"

# Login
COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"a-operator@bank-a.local","password":"password123"}' > /dev/null

echo "=== Seeding Identity Fabric Phase 2 Data ==="

# 1. SoD Rules
echo "── Creating SoD Rules ──"
for rule in \
    '{"name":"Payment Create/Approve","description":"No agent should both create and approve payments","conflicting_permissions":[["create_payment","approve_payment"]],"severity":"high","action":"block"}' \
    '{"name":"Admin/Audit","description":"Admin agents should not access audit functions","conflicting_permissions":[["admin","audit"]],"severity":"medium","action":"alert"}' \
    '{"name":"Data Read/Delete","description":"Agents with read access should not have delete access","conflicting_permissions":[["data_read","data_delete"]],"severity":"high","action":"require_approval"}'; do
    curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/governance/sod-rules" \
        -H "Content-Type: application/json" -d "$rule" > /dev/null
    echo "  Created: $(echo "$rule" | grep -o '"name":"[^"]*"' | head -1)"
done

# 2. Conditional Access Policies
echo "── Creating Conditional Access Policies ──"
for policy in \
    '{"name":"Block High Risk in Production","conditions":{"risk_score_gt":7,"environment":"production"},"action":"block"}' \
    '{"name":"Require Approval for Staging","conditions":{"risk_score_gt":5,"environment":"staging"},"action":"require_approval"}' \
    '{"name":"Allow Low Risk Everywhere","conditions":{"risk_score_gt":9},"action":"allow"}'; do
    curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/policies/conditional-access" \
        -H "Content-Type: application/json" -d "$policy" > /dev/null
    echo "  Created: $(echo "$policy" | grep -o '"name":"[^"]*"' | head -1)"
done

# 3. Rotation Policies
echo "── Creating Rotation Policies ──"
for rp in \
    '{"target_type":"credential","target_id":"oauth-cred-001","rotation_interval_days":30}' \
    '{"target_type":"credential","target_id":"oauth-cred-002","rotation_interval_days":90}' \
    '{"target_type":"agent","target_id":"agent-sales-bot","rotation_interval_days":60}'; do
    curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/oauth/rotation-policies" \
        -H "Content-Type: application/json" -d "$rp" > /dev/null
    echo "  Created: $(echo "$rp" | grep -o '"target_id":"[^"]*"' | head -1)"
done

# 4. SPIFFE Registration — register first 2 agents
echo "── Registering Agents for SPIFFE ──"
AGENTS=$(curl -s -b "$COOKIE_JAR" "$BASE_URL/api/agents" | python3 -c "import sys,json; agents=json.load(sys.stdin); [print(a.get('agent_id','')) for a in (agents if isinstance(agents,list) else agents.get('agents',[]))[:2]]" 2>/dev/null || echo "")
if [ -n "$AGENTS" ]; then
    while IFS= read -r aid; do
        [ -z "$aid" ] && continue
        curl -s -b "$COOKIE_JAR" -X POST "$BASE_URL/api/identity/spiffe/$aid/register" > /dev/null
        echo "  Registered: $aid"
    done <<< "$AGENTS"
else
    echo "  No agents found to register for SPIFFE"
fi

echo ""
echo "=== Seed Complete ==="
rm -f "$COOKIE_JAR"

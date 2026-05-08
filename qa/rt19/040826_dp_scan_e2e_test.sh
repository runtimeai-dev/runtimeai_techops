#!/usr/bin/env bash
# OPER-042: E2E QA — DP Process Scan → Shadow AI Inbox
#
# Validates the full data-plane scan submission flow:
#   1. Operator triggers a dp_local process scan
#   2. DP submits scan results (simulated via INTERNAL_SERVICE_TOKEN)
#   3. Discovered agents appear in Shadow AI Inbox (status=pending)
#   4. Findings are written and queryable
#   5. Tenant isolation: another tenant cannot see these agents
#
# Usage:
#   BASE_URL=https://api.rt19.runtimeai.io ./040826_dp_scan_e2e_test.sh
#   BASE_URL=http://localhost:4000 INTERNAL_SERVICE_TOKEN=devtoken ./040826_dp_scan_e2e_test.sh

set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
TENANT_ID="${TENANT_ID:-bank-a}"
EMAIL="${EMAIL:-a-operator@bank-a.local}"
PASSWORD="${PASSWORD:-password123}"
INTERNAL_SERVICE_TOKEN="${INTERNAL_SERVICE_TOKEN:-}"

# Second tenant for isolation test
TENANT2_ID="${TENANT2_ID:-acme-corp}"
EMAIL2="${EMAIL2:-support@acme-corp.local}"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ FAIL: $1${2:+ — $2}"; }

COOKIE1=/tmp/qa_dp_scan_cookie1.txt
COOKIE2=/tmp/qa_dp_scan_cookie2.txt

echo "═══════════════════════════════════════════════════════════════"
echo "  OPER-042: E2E DP Process Scan → Shadow AI Inbox"
echo "  $(date)"
echo "  Target: $BASE_URL | Tenant: $TENANT_ID"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── Auth ─────────────────────────────────────────────────────────────
echo "── Step 1: Authenticate ──"

curl -sf -c "$COOKIE1" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" > /dev/null
[ -s "$COOKIE1" ] && pass "Login as $EMAIL" || { fail "Login failed"; exit 1; }

curl -sf -c "$COOKIE2" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\":\"$TENANT2_ID\",\"email\":\"$EMAIL2\",\"password\":\"$PASSWORD\"}" > /dev/null
[ -s "$COOKIE2" ] && pass "Login as $EMAIL2 (isolation tenant)" || fail "Isolation tenant login failed (skipping isolation test)"

# ── If no token supplied, try to derive one from admin secret ─────────
if [ -z "$INTERNAL_SERVICE_TOKEN" ]; then
    INTERNAL_SERVICE_TOKEN=$(curl -sf -b "$COOKIE1" "$BASE_URL/api/admin/internal-token" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")
fi
# Final fallback: some dev setups expose ADMIN_SECRET as the token
if [ -z "$INTERNAL_SERVICE_TOKEN" ]; then
    INTERNAL_SERVICE_TOKEN="${ADMIN_SECRET:-devtoken}"
fi

# ── Step 2: Trigger DP process scan ──────────────────────────────────
echo ""
echo "── Step 2: Trigger dp_local process scan ──"

TRIGGER_RESP=$(curl -sf -b "$COOKIE1" \
    -X POST "$BASE_URL/api/discovery/scan-runs/trigger" \
    -H "Content-Type: application/json" \
    -d '{"scanner_id":"process"}')
RUN_ID=$(echo "$TRIGGER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('run_id',''))" 2>/dev/null || echo "")
EXEC_TIER=$(echo "$TRIGGER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('execution_tier',''))" 2>/dev/null || echo "")

if [ -n "$RUN_ID" ]; then
    pass "Trigger process scan → run_id: ${RUN_ID:0:8}..."
else
    fail "No run_id returned from trigger" "$TRIGGER_RESP"
    exit 1
fi

# dp_local tier means the DP is responsible — verify execution_tier
if [ "$EXEC_TIER" = "dp_local" ]; then
    pass "execution_tier=dp_local (correct for process scanner)"
else
    fail "Expected execution_tier=dp_local, got '$EXEC_TIER'"
fi

# ── Step 3: Simulate DP submitting scan results ───────────────────────
echo ""
echo "── Step 3: Simulate DP POST /api/discovery/scan-results ──"

# Unique fingerprints so re-runs don't conflict
TS=$(date +%s)
FP1="dp-test-langchain-${TS}"
FP2="dp-test-openai-${TS}"

SCAN_RESULTS_PAYLOAD=$(cat <<EOF
{
  "scan_run_id": "$RUN_ID",
  "command_id": "cmd-test-$TS",
  "data_plane_id": "dp-qa-test",
  "scanner_id": "process",
  "tenant_id": "$TENANT_ID",
  "status": "completed",
  "agents_found": [
    {
      "fingerprint": "$FP1",
      "name": "LangChain Agent (qa-process-test)",
      "owner": "eng-team@$TENANT_ID",
      "risk_score": 85,
      "source_details": {
        "process_name": "python3",
        "cmdline": "python3 -m langchain_agent --prod",
        "pid": 12345,
        "scanner": "process"
      },
      "capabilities": ["text-generation", "tool-use"]
    },
    {
      "fingerprint": "$FP2",
      "name": "OpenAI Direct SDK (qa-process-test)",
      "owner": "ml-team@$TENANT_ID",
      "risk_score": 92,
      "source_details": {
        "process_name": "python3",
        "cmdline": "python3 openai_script.py --model gpt-4",
        "pid": 12346,
        "scanner": "process"
      },
      "capabilities": ["text-generation"]
    }
  ],
  "findings": [
    {
      "agent_fingerprint": "$FP1",
      "finding_type": "ungoverned_ai_tool",
      "severity": "high",
      "details": {
        "reason": "LangChain process detected without policy enforcement",
        "process": "python3",
        "framework": "langchain"
      }
    },
    {
      "agent_fingerprint": "$FP2",
      "finding_type": "ungoverned_ai_tool",
      "severity": "critical",
      "details": {
        "reason": "Direct OpenAI API usage without flow enforcer",
        "process": "python3",
        "framework": "openai"
      }
    }
  ]
}
EOF
)

INGEST_RESP=$(curl -sf \
    -X POST "$BASE_URL/api/discovery/scan-results" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $INTERNAL_SERVICE_TOKEN" \
    -H "X-Tenant-ID: $TENANT_ID" \
    -d "$SCAN_RESULTS_PAYLOAD")

AGENTS_WRITTEN=$(echo "$INGEST_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agents_written',0))" 2>/dev/null || echo "0")
FINDINGS_WRITTEN=$(echo "$INGEST_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('findings_written',0))" 2>/dev/null || echo "0")
INGEST_STATUS=$(echo "$INGEST_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")

if [ "$AGENTS_WRITTEN" = "2" ]; then
    pass "DP scan-results accepted: agents_written=2"
else
    fail "Expected agents_written=2, got '$AGENTS_WRITTEN'" "$INGEST_RESP"
fi

if [ "$FINDINGS_WRITTEN" = "2" ]; then
    pass "Findings ingested: findings_written=2"
else
    fail "Expected findings_written=2, got '$FINDINGS_WRITTEN'"
fi

if [ "$INGEST_STATUS" = "completed" ]; then
    pass "Scan run marked completed"
else
    fail "Expected status=completed, got '$INGEST_STATUS'"
fi

# ── Step 4: Verify scan_run updated ──────────────────────────────────
echo ""
echo "── Step 4: Verify scan_run status updated ──"

RUN_DETAIL=$(curl -sf -b "$COOKIE1" "$BASE_URL/api/discovery/scan-runs/$RUN_ID" 2>/dev/null || echo "{}")
RUN_STATUS=$(echo "$RUN_DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('run',d); print(r.get('status',''))" 2>/dev/null || echo "")
RUN_AGENTS=$(echo "$RUN_DETAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('run',d); print(r.get('agents_found',-1))" 2>/dev/null || echo "-1")

if [ "$RUN_STATUS" = "completed" ]; then
    pass "scan_run.status=completed"
else
    fail "Expected scan_run status=completed, got '$RUN_STATUS'"
fi

if [ "$RUN_AGENTS" = "2" ]; then
    pass "scan_run.agents_found=2"
else
    fail "Expected agents_found=2, got '$RUN_AGENTS'"
fi

# ── Step 5: Verify agents appear in Shadow AI Inbox ───────────────────
echo ""
echo "── Step 5: Shadow AI Inbox — discovered agents visible ──"

DISCOVERED=$(curl -sf -b "$COOKIE1" "$BASE_URL/api/inventory/discovered" 2>/dev/null \
    || curl -sf -b "$COOKIE1" "$BASE_URL/api/discovery/agents" 2>/dev/null || echo "{}")

FP1_FOUND=$(echo "$DISCOVERED" | python3 -c "
import sys,json
d=json.load(sys.stdin)
agents = d.get('agents', d.get('discovered_agents', d if isinstance(d,list) else []))
fps = [a.get('fingerprint','') for a in agents]
print('yes' if '$FP1' in fps else 'no')
" 2>/dev/null || echo "no")

FP2_FOUND=$(echo "$DISCOVERED" | python3 -c "
import sys,json
d=json.load(sys.stdin)
agents = d.get('agents', d.get('discovered_agents', d if isinstance(d,list) else []))
fps = [a.get('fingerprint','') for a in agents]
print('yes' if '$FP2' in fps else 'no')
" 2>/dev/null || echo "no")

FP1_STATUS=$(echo "$DISCOVERED" | python3 -c "
import sys,json
d=json.load(sys.stdin)
agents = d.get('agents', d.get('discovered_agents', d if isinstance(d,list) else []))
match = [a for a in agents if a.get('fingerprint','')=='$FP1']
print(match[0].get('status','') if match else '')
" 2>/dev/null || echo "")

if [ "$FP1_FOUND" = "yes" ]; then
    pass "LangChain agent ($FP1) visible in Shadow AI Inbox"
else
    fail "LangChain agent not found in Shadow AI Inbox"
fi

if [ "$FP2_FOUND" = "yes" ]; then
    pass "OpenAI agent ($FP2) visible in Shadow AI Inbox"
else
    fail "OpenAI agent not found in Shadow AI Inbox"
fi

if [ "$FP1_STATUS" = "pending" ]; then
    pass "Agent status=pending (correctly awaiting triage)"
else
    fail "Expected status=pending, got '$FP1_STATUS'"
fi

# ── Step 6: Verify findings queryable ────────────────────────────────
echo ""
echo "── Step 6: Discovery findings visible ──"

FINDINGS_RESP=$(curl -sf -b "$COOKIE1" "$BASE_URL/api/discovery/findings" 2>/dev/null || echo "{}")
FINDINGS_COUNT=$(echo "$FINDINGS_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
findings = d.get('findings', d if isinstance(d,list) else [])
print(len(findings))
" 2>/dev/null || echo "0")

if [ "$FINDINGS_COUNT" -ge "1" ]; then
    pass "Findings endpoint returns $FINDINGS_COUNT findings (≥1)"
else
    fail "Expected ≥1 finding, got $FINDINGS_COUNT"
fi

# ── Step 7: Tenant isolation ─────────────────────────────────────────
echo ""
echo "── Step 7: Tenant isolation — $TENANT2_ID cannot see $TENANT_ID agents ──"

if [ -s "$COOKIE2" ]; then
    DISCOVERED2=$(curl -sf -b "$COOKIE2" "$BASE_URL/api/inventory/discovered" 2>/dev/null \
        || curl -sf -b "$COOKIE2" "$BASE_URL/api/discovery/agents" 2>/dev/null || echo "{}")

    FP1_LEAKED=$(echo "$DISCOVERED2" | python3 -c "
import sys,json
d=json.load(sys.stdin)
agents = d.get('agents', d.get('discovered_agents', d if isinstance(d,list) else []))
fps = [a.get('fingerprint','') for a in agents]
print('yes' if '$FP1' in fps else 'no')
" 2>/dev/null || echo "no")

    if [ "$FP1_LEAKED" = "no" ]; then
        pass "Tenant isolation: $TENANT2_ID cannot see $TENANT_ID agents"
    else
        fail "ISOLATION BREACH: $TENANT2_ID can see $TENANT_ID agent $FP1"
    fi
else
    echo "  ⚠️  SKIP: Isolation tenant login failed — skipping isolation test"
fi

# ── Step 8: Auth guard — no token → 401 ─────────────────────────────
echo ""
echo "── Step 8: Auth guard on scan-results endpoint ──"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$BASE_URL/api/discovery/scan-results" \
    -H "Content-Type: application/json" \
    -d '{"scan_run_id":"x","scanner_id":"process","tenant_id":"bank-a","status":"completed"}')
if [ "$HTTP_CODE" = "401" ]; then
    pass "No token → 401"
else
    fail "Expected 401 without token, got $HTTP_CODE"
fi

# ── Cleanup ───────────────────────────────────────────────────────────
rm -f "$COOKIE1" "$COOKIE2"

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
echo "All tests passed! ✅"

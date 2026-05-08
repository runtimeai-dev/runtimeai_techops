#!/bin/bash
# ============================================================
# RuntimeAI Discovery Scanner — Automated Seed & Test Script
# Tests all discovery scanners against a tenant and validates results
# ============================================================
# Usage: ./seed_discovery_test.sh [DISCOVERY_URL] [API_KEY] [TENANT_ID]

set -uo pipefail

DISC="${1:-http://localhost:18090}"
KEY="${2:-dev-secret-key}"
TID="${3:-equinix-test}"
PASS=0
FAIL=0

pass() { echo -e "  \033[0;32m✅ PASS\033[0m  $1"; PASS=$((PASS+1)); }
fail() { echo -e "  \033[0;31m❌ FAIL\033[0m  $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo "Discovery Scanner Test — $(date)"
echo "Target: $DISC"
echo "Tenant: $TID"
echo "========================================"
echo ""

# ─── Health ─────────────────────────────────────────────────
echo "--- Discovery Health ---"
RESULT=$(curl -s "$DISC/health" 2>&1)
echo "$RESULT" | grep -q '"status":"ok"' && pass "Discovery /health" || fail "Discovery /health: $RESULT"
echo ""

# ─── GitHub Sim ─────────────────────────────────────────────
echo "--- GitHub Simulation (5 agents) ---"
RESULT=$(curl -s -X POST "$DISC/simulate/github_scan?tenant_id=$TID&count=5" -H "X-API-Key: $KEY" 2>&1)
echo "$RESULT" | grep -q '"status":"ingested"' && pass "GitHub Scanner (5 agents)" || fail "GitHub: $RESULT"

# ─── Slack Sim ──────────────────────────────────────────────
echo "--- Slack Simulation ---"
RESULT=$(curl -s -X POST "$DISC/simulate/slack_scan?tenant_id=$TID" -H "X-API-Key: $KEY" 2>&1)
echo "$RESULT" | grep -q '"status":"ingested"' && pass "Slack Scanner (3 agents)" || fail "Slack: $RESULT"

# ─── Network Traffic ────────────────────────────────────────
echo "--- Network Traffic (Shadow AI) ---"
RESULT=$(curl -s -X POST "$DISC/simulate/network_traffic?tenant_id=$TID" \
  -H "X-API-Key: $KEY" -H "Content-Type: application/json" \
  -d '[{"domain":"api.openai.com","path":"/v1/chat/completions","method":"POST"},{"domain":"api.anthropic.com","path":"/v1/messages","method":"POST"}]' 2>&1)
echo "$RESULT" | grep -q '"status"' && pass "Network Scanner" || fail "Network: $RESULT"

# ─── Advanced Scan ──────────────────────────────────────────
echo "--- Advanced Scan (DNS+Process+OAuth) ---"
RESULT=$(curl -s -X POST "$DISC/v1/discovery/scan/advanced?tenant_id=$TID" -H "X-API-Key: $KEY" 2>&1)
echo "$RESULT" | grep -q '"status":"completed"' && pass "Advanced Scan" || fail "Advanced: $RESULT"

# ─── Manual Agent Ingestion ─────────────────────────────────
echo "--- Manual Agent Ingestion ---"
for AGENT in \
  '{"tenant_id":"'"$TID"'","name":"Ollama Local LLM","source":"process","description":"Local LLM","capabilities":["text-generation"],"agent_type":"local_llm","environment":"dev"}' \
  '{"tenant_id":"'"$TID"'","name":"VS Code Copilot","source":"vscode","description":"GitHub Copilot","capabilities":["code-completion"],"agent_type":"ide","environment":"dev"}' \
  '{"tenant_id":"'"$TID"'","name":"Salesforce Einstein GPT","source":"salesforce","description":"AI in CRM","capabilities":["lead-scoring"],"agent_type":"saas_ai","environment":"prod"}'; do
  NAME=$(echo "$AGENT" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])" 2>/dev/null)
  RESULT=$(curl -s -X POST "$DISC/v1/discovery/ingest/agent" \
    -H "X-API-Key: $KEY" -H "Content-Type: application/json" -d "$AGENT" 2>&1)
  echo "$RESULT" | grep -q '"status":"ingested"' && pass "Ingest: $NAME" || fail "Ingest $NAME: $RESULT"
done

# ─── Tool Ingestion ─────────────────────────────────────────
echo "--- Tool Ingestion ---"
RESULT=$(curl -s -X POST "$DISC/v1/discovery/ingest/tool" \
  -H "X-API-Key: $KEY" -H "Content-Type: application/json" \
  -d '{"tenant_id":"'"$TID"'","tool_uri":"https://api.openai.com/v1","name":"OpenAI API","capabilities":["chat"],"risk_tier":"HIGH","owner":"data-team","prod_ok":false}' 2>&1)
echo "$RESULT" | grep -q '"status":"ingested"' && pass "Tool Ingestion" || fail "Tool: $RESULT"
echo ""

# ─── Validation ─────────────────────────────────────────────
echo "--- Validation: Agent Count ---"
AGENTS=$(curl -s "$DISC/v1/inventory/discovered?tenant_id=$TID" -H "X-API-Key: $KEY" 2>&1)
COUNT=$(echo "$AGENTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('agents',[])))" 2>/dev/null)
echo "  Discovered agents: $COUNT"
[ "${COUNT:-0}" -gt 0 ] && pass "Agents in DB ($COUNT)" || fail "No agents in DB"

TOOLS=$(curl -s "$DISC/v1/inventory/tools?tenant_id=$TID" -H "X-API-Key: $KEY" 2>&1)
TOOL_COUNT=$(echo "$TOOLS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('tools',[])))" 2>/dev/null)
echo "  Tools in DB: $TOOL_COUNT"
echo ""

# ─── Summary ─────────────────────────────────────────────────
TOTAL=$((PASS+FAIL))
echo "========================================"
echo "RESULTS: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] && echo "🎉 ALL TESTS PASSED" || echo "⚠️  Some tests failed — review above"

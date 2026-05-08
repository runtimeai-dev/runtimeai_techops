#!/usr/bin/env bash
# =============================================================================
# seed_equinix_mcp.sh — Seed MCP Servers and Tools for equinix-demo tenant
#
# SoW Requirement: #7 — MCP Gateway with governed tool access pipeline
# Run this before the SoW evaluation to ensure equinix-demo has MCP data.
#
# Usage:
#   ./seed_equinix_mcp.sh [--rt19]
#
# Environment:
#   CP_URL       Control plane base URL (default: https://api.rt19.runtimeai.io)
#   ADMIN_EMAIL  Admin email for equinix-demo
#   ADMIN_PASS   Admin password (fetched from Azure KV if not set)
# =============================================================================

set -euo pipefail

CP_URL="${CP_URL:-https://api.rt19.runtimeai.io}"
TENANT_ID="equinix-demo"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@equinix-demo.runtimeai.io}"
COOKIE_FILE="/tmp/equinix_mcp_seed_cookies.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✅${NC} $1"; }
fail() { echo -e "  ${RED}❌${NC} $1"; exit 1; }
info() { echo -e "  ${YELLOW}ℹ️${NC}  $1"; }

echo ""
echo "═══════════════════════════════════════════════════"
echo " RuntimeAI — MCP Seed for equinix-demo"
echo " Target: $CP_URL"
echo " Tenant: $TENANT_ID"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── Authenticate ─────────────────────────────────────────────────────────────
info "Authenticating as $ADMIN_EMAIL..."

if [ -z "${ADMIN_PASS:-}" ]; then
  ADMIN_PASS=$(az keyvault secret show \
    --vault-name runtimeai-rt19-kv \
    --name equinix-demo-admin-password \
    --query value -o tsv 2>/dev/null) || true
fi

if [ -z "${ADMIN_PASS:-}" ]; then
  echo "ERROR: ADMIN_PASS not set and could not fetch from Azure Key Vault."
  echo "       Set ADMIN_PASS env var or ensure 'az' CLI is authenticated."
  exit 1
fi

LOGIN_RESP=$(curl -s -c "$COOKIE_FILE" -X POST "$CP_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$TENANT_ID\",\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}")

if ! echo "$LOGIN_RESP" | grep -q "user\|tenant"; then
  fail "Login failed: $LOGIN_RESP"
fi
pass "Authenticated as $ADMIN_EMAIL"

# Helper: authenticated POST
api_post() {
  local path="$1"
  local body="$2"
  curl -s -b "$COOKIE_FILE" -X POST "$CP_URL$path" \
    -H "Content-Type: application/json" \
    -d "$body"
}

# Helper: authenticated GET
api_get() {
  curl -s -b "$COOKIE_FILE" "$CP_URL$1"
}

# ─── Check existing MCP data ───────────────────────────────────────────────────
info "Checking existing MCP connections for $TENANT_ID..."
EXISTING=$(api_get "/api/mcp/connections" 2>/dev/null || echo "[]")
CONN_COUNT=$(echo "$EXISTING" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else len(d.get("connections",[])))' 2>/dev/null || echo "0")
info "Existing connections: $CONN_COUNT"

# ─── Register MCP Servers ──────────────────────────────────────────────────────
echo ""
echo "── Registering MCP Servers ──────────────────────────────────────────────"

# MCP Server 1: Slack Integration
info "Registering Slack MCP server..."
SLACK_RESP=$(api_post "/api/mcp/connections" '{
  "name": "Slack Workspace Integration",
  "server_url": "https://slack-mcp.equinix.internal",
  "transport": "http",
  "auth_type": "bearer",
  "description": "Slack MCP server for Equinix workspace — channels, messages, and workflows",
  "tags": ["communication", "collaboration", "equinix"],
  "governance": {
    "require_approval": false,
    "audit_enabled": true,
    "dlp_scan": true
  }
}')
if echo "$SLACK_RESP" | grep -q '"id"\|"connection_id"\|"name"'; then
  SLACK_ID=$(echo "$SLACK_RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("id",d.get("connection_id","")))' 2>/dev/null || echo "")
  pass "Slack MCP server registered (id: ${SLACK_ID:-unknown})"
else
  info "Slack server may already exist or error: $(echo "$SLACK_RESP" | head -c 200)"
fi

# MCP Server 2: GitHub Integration
info "Registering GitHub MCP server..."
GITHUB_RESP=$(api_post "/api/mcp/connections" '{
  "name": "GitHub Enterprise MCP",
  "server_url": "https://github-mcp.equinix.internal",
  "transport": "http",
  "auth_type": "token",
  "description": "GitHub MCP server — repository access, code search, issue management",
  "tags": ["development", "vcs", "equinix"],
  "governance": {
    "require_approval": true,
    "audit_enabled": true,
    "dlp_scan": true,
    "allowed_tools": ["search_code", "list_repos", "get_file", "create_issue"]
  }
}')
if echo "$GITHUB_RESP" | grep -q '"id"\|"connection_id"\|"name"'; then
  GITHUB_ID=$(echo "$GITHUB_RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("id",d.get("connection_id","")))' 2>/dev/null || echo "")
  pass "GitHub MCP server registered (id: ${GITHUB_ID:-unknown})"
else
  info "GitHub server may already exist or error: $(echo "$GITHUB_RESP" | head -c 200)"
fi

# MCP Server 3: Jira Integration
info "Registering Jira MCP server..."
JIRA_RESP=$(api_post "/api/mcp/connections" '{
  "name": "Jira Project Management MCP",
  "server_url": "https://jira-mcp.equinix.internal",
  "transport": "http",
  "auth_type": "basic",
  "description": "Jira MCP server — ticket creation, sprint management, backlog",
  "tags": ["project-management", "ticketing", "equinix"],
  "governance": {
    "require_approval": false,
    "audit_enabled": true,
    "dlp_scan": false,
    "allowed_tools": ["create_ticket", "list_issues", "get_sprint", "update_status"]
  }
}')
if echo "$JIRA_RESP" | grep -q '"id"\|"connection_id"\|"name"'; then
  pass "Jira MCP server registered"
else
  info "Jira server may already exist: $(echo "$JIRA_RESP" | head -c 200)"
fi

# MCP Server 4: Database Query MCP
info "Registering Database MCP server..."
DB_RESP=$(api_post "/api/mcp/connections" '{
  "name": "Equinix Data Warehouse MCP",
  "server_url": "https://db-mcp.equinix.internal",
  "transport": "http",
  "auth_type": "bearer",
  "description": "Read-only data warehouse access for analytics agents",
  "tags": ["database", "analytics", "read-only", "equinix"],
  "governance": {
    "require_approval": true,
    "audit_enabled": true,
    "dlp_scan": true,
    "blocked_tools": ["drop_table", "delete_rows", "truncate"],
    "allowed_tools": ["query", "describe_table", "list_tables", "export_csv"]
  }
}')
if echo "$DB_RESP" | grep -q '"id"\|"connection_id"\|"name"'; then
  pass "Database MCP server registered"
else
  info "DB server may already exist: $(echo "$DB_RESP" | head -c 200)"
fi

# ─── Register MCP Tools (via mcp_inventory if direct API exists) ──────────────
echo ""
echo "── Seeding MCP Tool Inventory ───────────────────────────────────────────"

# Try discovery endpoint to register tools
TOOLS_TO_SEED=(
  '{"name":"send_message","server":"slack-mcp","description":"Send a message to a Slack channel","category":"communication","risk_score":2}'
  '{"name":"list_channels","server":"slack-mcp","description":"List available Slack channels","category":"communication","risk_score":1}'
  '{"name":"search_messages","server":"slack-mcp","description":"Search Slack message history","category":"communication","risk_score":3}'
  '{"name":"search_code","server":"github-mcp","description":"Search code across repositories","category":"development","risk_score":2}'
  '{"name":"create_issue","server":"github-mcp","description":"Create a GitHub issue","category":"development","risk_score":3}'
  '{"name":"get_file","server":"github-mcp","description":"Retrieve file content from a repository","category":"development","risk_score":2}'
  '{"name":"create_ticket","server":"jira-mcp","description":"Create a Jira ticket","category":"project-management","risk_score":2}'
  '{"name":"list_issues","server":"jira-mcp","description":"List Jira issues in a project","category":"project-management","risk_score":1}'
  '{"name":"query","server":"db-mcp","description":"Execute a read-only SQL query","category":"database","risk_score":4}'
  '{"name":"list_tables","server":"db-mcp","description":"List available database tables","category":"database","risk_score":2}'
)

for TOOL in "${TOOLS_TO_SEED[@]}"; do
  TOOL_NAME=$(echo "$TOOL" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["name"])' 2>/dev/null || echo "unknown")
  TOOL_RESP=$(api_post "/api/discovery/mcp/servers" "$TOOL" 2>/dev/null || echo '{"error":"skipped"}')
  if echo "$TOOL_RESP" | grep -q '"id"\|"name"\|exists'; then
    pass "Tool registered: $TOOL_NAME"
  else
    info "Tool $TOOL_NAME: $(echo "$TOOL_RESP" | head -c 100)"
  fi
done

# ─── Verify seeded data ────────────────────────────────────────────────────────
echo ""
echo "── Verification ─────────────────────────────────────────────────────────"

FINAL_CONNS=$(api_get "/api/mcp/connections" 2>/dev/null || echo "[]")
FINAL_COUNT=$(echo "$FINAL_CONNS" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else len(d.get("connections",[])))' 2>/dev/null || echo "unknown")
pass "MCP connections for $TENANT_ID: $FINAL_COUNT"

FINAL_HEALTH=$(api_get "/api/mcp/health" 2>/dev/null || echo "{}")
if echo "$FINAL_HEALTH" | grep -q "ok\|healthy\|status"; then
  pass "MCP Gateway health: OK"
else
  info "MCP Gateway health response: $(echo "$FINAL_HEALTH" | head -c 200)"
fi

# ─── Seed MCP Governance: Policy Rules ────────────────────────────────────────
echo ""
echo "── Seeding MCP Governance — Policy Rules ──────────────────────────────"

POLICY_RULES=(
  '{"name":"Block all delete operations","tool_pattern":"delete_*","action":"deny","priority":1}'
  '{"name":"Block destructive SQL","tool_pattern":"*_drop","action":"deny","priority":1}'
  '{"name":"Allow read operations","tool_pattern":"*_list","action":"allow","priority":10}'
  '{"name":"Review create operations by AI agents","tool_pattern":"*_create","action":"review","priority":5,"conditions":{"invoker_type":"ai_agent"}}'
)

for RULE in "${POLICY_RULES[@]}"; do
  RULE_NAME=$(echo "$RULE" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["name"])' 2>/dev/null || echo "unknown")
  RESP=$(api_post "/api/mcp/policy/rules" "$RULE" 2>/dev/null || echo '{"error":"skipped"}')
  if echo "$RESP" | grep -q '"id"\|"status"'; then
    pass "Policy rule: $RULE_NAME"
  else
    info "Policy rule $RULE_NAME: $(echo "$RESP" | head -c 100)"
  fi
done

# ─── Seed MCP Governance: Agent Profiles ──────────────────────────────────────
echo ""
echo "── Seeding MCP Governance — Agent Profiles ────────────────────────────"

PROFILES=(
  '{"agent_name":"equinix-copilot","allowed_tools":["github_*","jira_*","slack_send_message"],"denied_tools":["*_delete","exec_*"],"max_calls_per_hour":500}'
  '{"agent_name":"read-only-analyst","allowed_tools":["*_list","*_search","*_query","*_describe"],"denied_tools":["*_create","*_update","*_delete"],"max_calls_per_hour":1000}'
  '{"agent_name":"admin-agent","allowed_tools":["*"],"denied_tools":[],"max_calls_per_hour":200,"require_approval":true}'
)

for PROFILE in "${PROFILES[@]}"; do
  AGENT=$(echo "$PROFILE" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["agent_name"])' 2>/dev/null || echo "unknown")
  RESP=$(api_post "/api/mcp/governance/profiles" "$PROFILE" 2>/dev/null || echo '{"error":"skipped"}')
  if echo "$RESP" | grep -q '"id"\|"status"'; then
    pass "Agent profile: $AGENT"
  else
    info "Agent profile $AGENT: $(echo "$RESP" | head -c 100)"
  fi
done

# ─── Seed MCP Governance: Guardrail Rules ─────────────────────────────────────
echo ""
echo "── Seeding MCP Governance — Guardrail Rules ───────────────────────────"

GUARDRAILS=(
  '{"name":"GitHub API rate limit","tool_pattern":"github_*","rule_type":"rate_limit","max_calls":100,"window_seconds":3600}'
  '{"name":"Business hours for Salesforce","tool_pattern":"sf_*","rule_type":"time_based","allowed_hours_min":8,"allowed_hours_max":18}'
  '{"name":"Daily cost cap","tool_pattern":"*","rule_type":"cost_limit","cost_limit_usd":100.00}'
  '{"name":"Approval for exec tools","tool_pattern":"exec_*","rule_type":"require_approval"}'
)

for GUARD in "${GUARDRAILS[@]}"; do
  GUARD_NAME=$(echo "$GUARD" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["name"])' 2>/dev/null || echo "unknown")
  RESP=$(api_post "/api/mcp/guardrails/rules" "$GUARD" 2>/dev/null || echo '{"error":"skipped"}')
  if echo "$RESP" | grep -q '"id"\|"status"'; then
    pass "Guardrail: $GUARD_NAME"
  else
    info "Guardrail $GUARD_NAME: $(echo "$RESP" | head -c 100)"
  fi
done

# ─── Verify governance seed ───────────────────────────────────────────────────
echo ""
echo "── Governance Verification ────────────────────────────────────────────"

GOV_RULES=$(api_get "/api/mcp/policy/rules" 2>/dev/null || echo '{"count":0}')
GOV_COUNT=$(echo "$GOV_RULES" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("count",0))' 2>/dev/null || echo "0")
pass "Policy rules: $GOV_COUNT"

GOV_PROFILES=$(api_get "/api/mcp/governance/profiles" 2>/dev/null || echo '{"count":0}')
PROF_COUNT=$(echo "$GOV_PROFILES" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("count",0))' 2>/dev/null || echo "0")
pass "Agent profiles: $PROF_COUNT"

GOV_GUARDS=$(api_get "/api/mcp/guardrails/rules" 2>/dev/null || echo '{"count":0}')
GUARD_COUNT=$(echo "$GOV_GUARDS" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("count",0))' 2>/dev/null || echo "0")
pass "Guardrail rules: $GUARD_COUNT"

echo ""
echo "═══════════════════════════════════════════════════"
echo " Seed complete. Run sow_test_suite.sh to verify."
echo "═══════════════════════════════════════════════════"
echo ""

# Cleanup
rm -f "$COOKIE_FILE"

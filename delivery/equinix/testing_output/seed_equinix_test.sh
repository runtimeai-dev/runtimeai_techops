#!/bin/bash
# ============================================================
# RuntimeAI Equinix Test — Seed Script
# Creates a fresh equinix tenant with demo data for verification
#
# Updated: 2026-04-07
# Changes:
#   - Fixed access review campaign frequency (must be one_time|monthly|quarterly|annually)
#   - Added MCP server + tool seed for equinix-demo (P1 gap fix)
#   - Added AAIC framework enrollment + controls verification
#   - Added ImagePullBackOff guard (REGISTRY_TOKEN check)
#   - MinIO skip handled gracefully
# ============================================================
# Usage: ./seed_equinix_test.sh [BASE_URL] [ADMIN_SECRET]
# Example: ./seed_equinix_test.sh https://rt19.runtimeai.io <admin_secret>
#
# Environment variables (override positional args):
#   CP_URL        — control plane base URL
#   ADMIN_SECRET  — RuntimeAI admin secret
#   TENANT_ID     — tenant ID to create/use (default: equinix-onprem)
#   ADMIN_EMAIL   — admin email for the tenant
#   REGISTRY_TOKEN — ACR pull token (optional; skips image-pull check if absent)

set -uo pipefail

BASE="${CP_URL:-${1:-https://rt19.runtimeai.io}}"
ADMIN_SECRET="${ADMIN_SECRET:-${2:-}}"
TID="${TENANT_ID:-equinix-onprem}"
ADMIN_EMAIL_DEFAULT="admin@${TID}.com"
ADMIN_EMAIL="${ADMIN_EMAIL:-${ADMIN_EMAIL_DEFAULT}}"
COOKIE="/tmp/eqx_seed_${TID}_cookies.txt"
K8S_NAMESPACE="${K8S_NAMESPACE:-rt19}"
AAIC_URL="${AAIC_URL:-$BASE}"   # AAIC proxied through CP at /api/aaic/*

info()  { echo -e "\033[0;36m[INFO]\033[0m  $1"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $1"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $1"; }
err()   { echo -e "\033[0;31m[FAIL]\033[0m  $1"; }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  RuntimeAI Equinix — Seed Script  (2026-04-07)          ║"
echo "║  Tenant: $TID                                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── Guard: ImagePullBackOff warning ─────────────────────────
if [ -z "${REGISTRY_TOKEN:-}" ]; then
  warn "REGISTRY_TOKEN not set — ACR images will ImagePullBackOff in eqix-rt19 namespace."
  warn "Infra pods (postgres, redis) will still start. Set REGISTRY_TOKEN=<acr-pull-token> to pull app images."
else
  ok "REGISTRY_TOKEN set — ACR images should pull successfully"
fi

# ─── Step 1: Create Tenant ────────────────────────────────────
info "Step 1: Creating tenant: $TID"
RESULT=$(curl -sk -X POST "$BASE/api/admin/tenants" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TID\", \"name\": \"Equinix On-Prem\", \"admin_email\": \"$ADMIN_EMAIL\"}" 2>&1)

if echo "$RESULT" | grep -q '"status":"created"'; then
  PASSWORD=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('password',''))" 2>/dev/null)
  API_KEY=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_key',''))" 2>/dev/null)
  ok "Tenant created: $TID (password: $PASSWORD)"
elif echo "$RESULT" | grep -q "already exists"; then
  warn "Tenant $TID already exists — will authenticate"
  PASSWORD="${ADMIN_PASS:-}"
else
  err "Tenant creation failed: $RESULT"
  exit 1
fi

# ─── Step 2: Authenticate ────────────────────────────────────
info "Step 2: Authenticating..."
AUTH_OK=false
SESSION_COOKIE=""

_extract_session() {
  echo "$1" | grep -i "set-cookie" | grep -oE 'runtimeai_session=[^;]+' | head -1
}

if [ -n "${ADMIN_SECRET:-}" ]; then
  IMP_HEADERS=$(curl -sk -D - -X POST "$BASE/api/admin/impersonate" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d "{\"tenant_id\": \"$TID\"}" 2>&1)
  SESSION_COOKIE=$(_extract_session "$IMP_HEADERS")
  IMP_RESULT=$(echo "$IMP_HEADERS" | tail -1)
  if echo "$IMP_RESULT" | grep -q "impersonating"; then
    ok "Authenticated via admin impersonation"
    AUTH_OK=true
  fi
fi

if [ "$AUTH_OK" = false ] && [ -n "${PASSWORD:-}" ]; then
  LOGIN_HEADERS=$(curl -sk -D - -X POST "$BASE/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TID\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$PASSWORD\"}" 2>&1)
  SESSION_COOKIE=$(_extract_session "$LOGIN_HEADERS")
  LOGIN_RESULT=$(echo "$LOGIN_HEADERS" | tail -1)
  if echo "$LOGIN_RESULT" | grep -q "user_id"; then
    ok "Login successful (direct)"
    AUTH_OK=true
  else
    err "Login failed: $LOGIN_RESULT"
    exit 1
  fi
fi

[ "$AUTH_OK" = false ] && warn "No auth available — some operations may fail"

_curl_auth() {
  [ -n "$SESSION_COOKIE" ] \
    && curl -sk -H "Cookie: $SESSION_COOKIE" "$@" \
    || curl -sk "$@"
}

# ─── Step 3: Register Agents ─────────────────────────────────
info "Step 3: Registering agents..."
for AGENT_JSON in \
  '{"name":"eqx-payment-agent","type":"autonomous","owner":"fintech-team","environment":"production","model":"gpt-4","capabilities":["payment-processing","fraud-detection"],"risk_tier":"HIGH","tenant_id":"'"$TID"'"}' \
  '{"name":"eqx-data-analyst","type":"supervised","owner":"data-team","environment":"staging","model":"claude-3","capabilities":["data-analysis","reporting"],"risk_tier":"LIMITED","tenant_id":"'"$TID"'"}' \
  '{"name":"eqx-security-scanner","type":"autonomous","owner":"security-team","environment":"production","model":"gpt-4o","capabilities":["vulnerability-scanning","threat-detection"],"risk_tier":"UNACCEPTABLE","tenant_id":"'"$TID"'"}' \
  '{"name":"eqx-network-vnf-agent","type":"autonomous","owner":"network-team","environment":"production","model":"gpt-4","capabilities":["network-config","vnf-management"],"risk_tier":"HIGH","tenant_id":"'"$TID"'"}'; do
  NAME=$(echo "$AGENT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])" 2>/dev/null)
  RESULT=$(_curl_auth -X POST "$BASE/api/agents" -H "Content-Type: application/json" -d "$AGENT_JSON" 2>&1)
  if echo "$RESULT" | grep -q "agent_id"; then
    AGENT_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_id',''))" 2>/dev/null)
    ok "Agent: $NAME → $AGENT_ID"
  else
    warn "Agent $NAME: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',d.get('message','already exists?')))" 2>/dev/null)"
  fi
done

# ─── Step 4: Egress Policies ─────────────────────────────────
info "Step 4: Creating egress policies..."
for POLICY_JSON in \
  '{"destination":"*.openai.com","action":"block","category":"ai-vendor","tenant_id":"'"$TID"'"}' \
  '{"destination":"*.anthropic.com","action":"allow","category":"ai-vendor","tenant_id":"'"$TID"'"}' \
  '{"destination":"*.internal.equinix.com","action":"allow","category":"internal","tenant_id":"'"$TID"'"}' \
  '{"destination":"*.unauthorized-vendor.com","action":"block","category":"vnf-governance","tenant_id":"'"$TID"'"}'; do
  DEST=$(echo "$POLICY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['destination'])" 2>/dev/null)
  RESULT=$(_curl_auth -X POST "$BASE/api/policies/egress" -H "Content-Type: application/json" -d "$POLICY_JSON" 2>&1)
  echo "$RESULT" | grep -q '"id"' \
    && ok "Egress: $DEST → $(echo "$POLICY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['action'])" 2>/dev/null)" \
    || warn "Egress $DEST: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error','?'))" 2>/dev/null)"
done

# ─── Step 5: MCP Server + Tool seed for equinix-demo (P1 fix) ──
# Previously: 0 MCP tools/servers for equinix-demo tenant
# Fix: POST /api/mcp/connections (inserts into mcp_inventory)
# Correct field names: name + server_url (not url)
info "Step 5: Seeding MCP servers and tools..."
for MCP_JSON in \
  '{"name":"equinix-network-mcp","server_url":"https://mcp.network.equinix.com","transport":"http","description":"Equinix Network Edge MCP Server"}' \
  '{"name":"equinix-security-mcp","server_url":"https://mcp.security.equinix.com","transport":"http","description":"Equinix Security Operations MCP Server"}' \
  '{"name":"equinix-internal-tools","server_url":"https://mcp.internal.equinix.com","transport":"http","description":"Internal IT AI Tooling"}'; do
  NAME=$(echo "$MCP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])" 2>/dev/null)
  RESULT=$(_curl_auth -X POST "$BASE/api/mcp/connections" \
    -H "Content-Type: application/json" -d "$MCP_JSON" 2>&1)
  if echo "$RESULT" | grep -q '"instance_id"\|"status":"connected"\|already'; then
    ok "MCP Server: $NAME → $(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('instance_id','registered'))" 2>/dev/null)"
  else
    warn "MCP Server $NAME: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error','?'))" 2>/dev/null)"
  fi
done

# ─── Step 6: Access Review — frequency fix (P1 fix) ──────────
# Previously: "Q2-2026" frequency → violated chk_campaign_frequency constraint
# Fix: use valid values: one_time | monthly | quarterly | annually
info "Step 6: Creating access review campaign..."
AR_RESULT=$(_curl_auth -X POST "$BASE/api/access-reviews" \
  -H "Content-Type: application/json" \
  -d '{
    "name":"Q2-2026 Equinix AI Agent Review",
    "description":"Quarterly review of all AI agents for Equinix on-prem deployment",
    "scope":"all_agents",
    "reviewer_type":"manager",
    "frequency":"quarterly",
    "duration_days":30,
    "tenant_id":"'"$TID"'"
  }' 2>&1)
if echo "$AR_RESULT" | grep -q '"id"'; then
  AR_ID=$(echo "$AR_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  ok "Access review created: Q2-2026 → $AR_ID"
elif echo "$AR_RESULT" | grep -q "already exists\|duplicate"; then
  warn "Access review already exists (skip)"
else
  warn "Access review: $(echo "$AR_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',d.get('detail','?')))" 2>/dev/null)"
fi

# ─── Step 7: AAIC Framework Controls Verification ────────────
# AAIC does not have an explicit "enroll" endpoint — frameworks are catalog-based.
# Controls are accessible per-tenant at GET /api/aaic/enterprise/frameworks/{id}/controls
# Bundles available at GET /api/aaic/frameworks/bundles
info "Step 7: Verifying AAIC compliance framework catalog..."

# 7a: Bundles catalog
BUNDLES=$(_curl_auth "$BASE/api/aaic/frameworks/bundles" 2>&1)
if echo "$BUNDLES" | grep -q '"bundles"'; then
  BUNDLE_COUNT=$(echo "$BUNDLES" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('bundles',[])))" 2>/dev/null)
  ok "AAIC compliance bundles available: $BUNDLE_COUNT bundles"
else
  warn "AAIC bundles: $(echo "$BUNDLES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error','?'))" 2>/dev/null)"
fi

# 7b: Per-tenant controls (verify EU AI Act controls are accessible)
info "Step 7b: Verifying per-tenant framework controls..."
for FW_ID in "EU_AI_ACT" "SOC2_TYPE2" "FEDRAMP_MODERATE"; do
  CTRL_RESULT=$(_curl_auth "$BASE/api/aaic/enterprise/frameworks/$FW_ID/controls" 2>&1)
  if echo "$CTRL_RESULT" | grep -q '"total"\|"controls"'; then
    CTRL_COUNT=$(echo "$CTRL_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',len(json.load(sys.stdin).get('controls',[]))))" 2>/dev/null)
    ok "AAIC $FW_ID controls: $CTRL_COUNT controls"
  else
    warn "AAIC $FW_ID: $(echo "$CTRL_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error','?'))" 2>/dev/null)"
  fi
done

# ─── Step 8: Verify ──────────────────────────────────────────
info "Step 8: Verifying seed..."
echo ""

AGENTS=$(_curl_auth "$BASE/api/agents?tenant_id=$TID" 2>&1)
AGENT_COUNT=$(echo "$AGENTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('agents',[])))" 2>/dev/null)
info "Agents registered: $AGENT_COUNT"

CHAIN=$(_curl_auth "$BASE/api/audit/verify?tenant_id=$TID" 2>&1)
echo "$CHAIN" | grep -q '"valid":true' && ok "Audit chain: INTACT ✅" || warn "Audit chain: $CHAIN"

FRAMEWORKS=$(_curl_auth "$BASE/api/compliance/frameworks?tenant_id=$TID" 2>&1)
FW_COUNT=$(echo "$FRAMEWORKS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('frameworks',[])))" 2>/dev/null)
info "Compliance frameworks enrolled: $FW_COUNT"

MCP_SERVERS=$(_curl_auth "$BASE/api/mcp/servers?tenant_id=$TID" 2>&1)
MCP_COUNT=$(echo "$MCP_SERVERS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('servers',d.get('items',[]))))" 2>/dev/null)
info "MCP servers: $MCP_COUNT"

echo ""
ok "Seed complete for tenant: $TID"
echo ""
echo "  Agents:              $AGENT_COUNT"
echo "  Frameworks:          $FW_COUNT"
echo "  MCP Servers:         $MCP_COUNT"
echo ""

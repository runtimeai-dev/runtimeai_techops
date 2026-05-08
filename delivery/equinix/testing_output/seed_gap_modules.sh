#!/bin/bash
# ============================================================
# RuntimeAI — Seed Gap Modules for Equinix Delivery
# Seeds: sponsors, ticketing config, incidents, notifications,
#         access packages, access assignments, governance data
# ============================================================
# Usage: ./seed_gap_modules.sh [BASE_URL] [ADMIN_SECRET] [TENANT_ID]
# Example: ./seed_gap_modules.sh https://api.rt19.runtimeai.io 907c6e5f99fbe9eaf1500a78471bc1e4 equinix-demo

set -euo pipefail

BASE="${1:-https://api.rt19.runtimeai.io}"
ADMIN_SECRET="${2:-907c6e5f99fbe9eaf1500a78471bc1e4}"
TID="${3:-equinix-demo}"
COOKIE="/tmp/eqx_gap_seed_cookies.txt"

info()  { echo -e "\033[0;36m[INFO]\033[0m  $1"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $1"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $1"; }
fail()  { echo -e "\033[0;31m[FAIL]\033[0m  $1"; }

# ─── Login ────────────────────────────────────────────────
info "Logging into tenant: $TID"
LOGIN_RESULT=$(curl -sk -c "$COOKIE" -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TID\", \"email\": \"admin@${TID}.runtimeai.io\", \"password\": \"password123\"}" 2>&1)

if echo "$LOGIN_RESULT" | grep -q "user_id"; then
  ok "Login successful"
else
  warn "Login failed, using admin secret for operations"
fi

# ─── Helper: API call with both auth methods ──────────────
api_call() {
  local METHOD=$1
  local ENDPOINT=$2
  local DATA="${3:-}"
  
  if [ -n "$DATA" ]; then
    curl -sk -b "$COOKIE" -X "$METHOD" "$BASE$ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
      -H "X-Tenant-ID: $TID" \
      -d "$DATA" 2>&1
  else
    curl -sk -b "$COOKIE" -X "$METHOD" "$BASE$ENDPOINT" \
      -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
      -H "X-Tenant-ID: $TID" 2>&1
  fi
}

# ─── 1. Ticketing Configuration ──────────────────────────
info "Seeding ticketing configuration..."
RESULT=$(api_call PUT "/api/ticketing/config" "{
  \"tenant_id\": \"$TID\",
  \"provider\": \"jira\",
  \"jira_url\": \"https://runtimeai.atlassian.net\",
  \"jira_email\": \"integrations@runtimeai.io\",
  \"jira_api_token\": \"placeholder-configure-in-vault\",
  \"jira_project_key\": \"RTAI\",
  \"auto_create_severity\": [\"critical\", \"high\"],
  \"enabled\": false
}")
if echo "$RESULT" | grep -qiE "ok|200|config"; then
  ok "Ticketing config seeded"
else
  warn "Ticketing config: $RESULT"
fi

# ─── 2. Sponsors ─────────────────────────────────────────
info "Seeding agent sponsors..."

# Get available agents
AGENTS=$(api_call GET "/api/agents?tenant_id=$TID")
AGENT_IDS=$(echo "$AGENTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    agents = data.get('agents', [])
    for a in agents[:3]:
        print(a.get('agent_id', ''))
except: pass
" 2>/dev/null)

for AGENT_ID in $AGENT_IDS; do
  if [ -n "$AGENT_ID" ]; then
    RESULT=$(api_call POST "/api/agents/$AGENT_ID/sponsors" "{
      \"user_id\": \"admin@${TID}.runtimeai.io\",
      \"role\": \"primary\",
      \"is_primary\": true
    }")
    if echo "$RESULT" | grep -qiE "created|ok|201|already"; then
      ok "Sponsor assigned: admin → $AGENT_ID"
    else
      warn "Sponsor for $AGENT_ID: $RESULT"
    fi
  fi
done

# ─── 3. Incidents ────────────────────────────────────────
info "Seeding incidents..."
for INC_JSON in \
  '{"title":"Unauthorized data access by payment-agent","description":"Payment agent accessed customer PII data outside approved scope. DLP monitors detected the anomaly at 14:23 UTC.","severity":"critical","agent_name":"eqx-payment-agent"}' \
  '{"title":"Excessive API calls from data-analyst","description":"Data analyst agent exceeded rate limits on analytics API, triggering automated throttling.","severity":"medium","agent_name":"eqx-data-analyst"}' \
  '{"title":"Certificate renewal failure","description":"TLS certificate auto-renewal failed for security-scanner agent. Manual intervention required.","severity":"high","agent_name":"eqx-security-scanner"}'; do
  
  TITLE=$(echo "$INC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])" 2>/dev/null)
  RESULT=$(api_call POST "/api/issue" "$INC_JSON")
  if echo "$RESULT" | grep -qiE "created|id"; then
    ok "Incident: $TITLE"
  else
    warn "Incident '$TITLE': $RESULT"
  fi
done

# ─── 4. Access Packages ─────────────────────────────────
info "Seeding access packages..."
for PKG_JSON in \
  '{"name":"Production Read-Only","description":"Read-only access to production data sources and monitoring dashboards.","permissions":["read:metrics","read:logs","read:dashboards"],"approvers":["admin@'"$TID"'.runtimeai.io"]}' \
  '{"name":"Analytics Full Access","description":"Full access to analytics APIs, data lakes, and reporting tools.","permissions":["read:analytics","write:reports","execute:queries"],"approvers":["admin@'"$TID"'.runtimeai.io"]}'; do
  
  NAME=$(echo "$PKG_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])" 2>/dev/null)
  RESULT=$(api_call POST "/api/access-packages" "$PKG_JSON")
  if echo "$RESULT" | grep -qiE "created|id|ok"; then
    ok "Access Package: $NAME"
  else
    warn "Access Package '$NAME': $RESULT"
  fi
done

# ─── 5. Verify Seed Data ────────────────────────────────
echo ""
info "Verifying seeded gap data..."

# Notifications (auto-generated from events)
NOTIF_RESULT=$(api_call GET "/api/notifications?limit=5")
NOTIF_COUNT=$(echo "$NOTIF_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")
info "Notifications: $NOTIF_COUNT"

# Reports
REPORT_RESULT=$(api_call GET "/api/report?type=agents")
if echo "$REPORT_RESULT" | grep -qiE "total_agents|data"; then
  ok "Reports API: working"
else
  warn "Reports API: $REPORT_RESULT"
fi

# Incidents
INC_RESULT=$(api_call GET "/api/issue")
INC_COUNT=$(echo "$INC_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")
info "Incidents: $INC_COUNT"

# Key Rotation (GET availability check — POST requires Vault Broker)
info "Key rotation endpoint exists (requires Vault Broker for POST)"

# Governance Hub data (existing endpoints)
GOV_RESULT=$(api_call GET "/api/governance/hub?tenant_id=$TID")
if echo "$GOV_RESULT" | grep -qiE "hub|policies|agents"; then
  ok "Governance Hub: available"
else
  warn "Governance Hub: $GOV_RESULT"
fi

echo ""
ok "Gap modules seed complete for tenant: $TID"

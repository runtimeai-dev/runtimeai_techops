#!/bin/bash
# seed_rt19_customer.sh — Seed a full customer tenant on rt19 (zero SQL, API-only)
# Usage: ./seed_rt19_customer.sh [tenant_id] [admin_email]
set -euo pipefail

# ── Configuration ──
TENANT_ID="${1:-acme-corp}"
ADMIN_EMAIL="${2:-admin@acme-corp.com}"
API_BASE="https://api.rt19.runtimeai.io"
ADMIN_SECRET="${RUNTIMEAI_ADMIN_SECRET:-}"
COOKIE="/tmp/${TENANT_ID}_session.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
STEP=0

if [ -z "$ADMIN_SECRET" ]; then
  echo -e "${RED}Error: RUNTIMEAI_ADMIN_SECRET environment variable is required${NC}"
  echo "  export RUNTIMEAI_ADMIN_SECRET=\$(kubectl get secret rt19-app-secrets -n rt19 -o jsonpath='{.data.RUNTIMEAI_ADMIN_SECRET}' | base64 -d)"
  exit 1
fi

step() {
  STEP=$((STEP + 1))
  echo -e "\n${YELLOW}[$STEP] $1${NC}"
}

ok() {
  echo -e "  ${GREEN}✅ $1${NC}"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}❌ $1${NC}"
  FAIL=$((FAIL + 1))
}

api_post() {
  local endpoint="$1"
  local data="$2"
  local extra_headers="${3:-}"

  if [ -n "$extra_headers" ]; then
    curl -sf -b "$COOKIE" -c "$COOKIE" -X POST "$API_BASE$endpoint" \
      -H "Content-Type: application/json" \
      -H "$extra_headers" \
      -d "$data" 2>/dev/null
  else
    curl -sf -b "$COOKIE" -c "$COOKIE" -X POST "$API_BASE$endpoint" \
      -H "Content-Type: application/json" \
      -d "$data" 2>/dev/null
  fi
}

api_get() {
  curl -sf -b "$COOKIE" "$API_BASE$1" 2>/dev/null
}

echo "============================================"
echo "  RuntimeAI rt19 — Customer Seed"
echo "  Tenant: $TENANT_ID"
echo "  Admin:  $ADMIN_EMAIL"
echo "  API:    $API_BASE"
echo "  $(date)"
echo "============================================"

# ── Step 1: Create Tenant ──
step "Create tenant: $TENANT_ID"
RESULT=$(api_post "/api/admin/tenants" "{
  \"tenant_id\": \"$TENANT_ID\",
  \"name\": \"Acme Corporation\",
  \"plan\": \"enterprise\",
  \"contact_email\": \"$ADMIN_EMAIL\",
  \"settings\": {
    \"max_agents\": 500,
    \"max_users\": 100,
    \"features\": [\"identity\",\"discovery\",\"governance\",\"firewall\",\"mcp\",\"finops\",\"compliance\",\"marketplace\",\"esign\",\"behavioral\",\"aiops\",\"ml\"]
  }
}" "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" || echo "")
if [ -n "$RESULT" ]; then ok "Tenant created"; else fail "Tenant creation failed (may already exist)"; fi

# ── Step 2: Create Admin User ──
step "Create admin user: $ADMIN_EMAIL"
RESULT=$(api_post "/api/admin/users" "{
  \"tenant_id\": \"$TENANT_ID\",
  \"email\": \"$ADMIN_EMAIL\",
  \"display_name\": \"Acme Admin\",
  \"role\": \"admin\",
  \"password\": \"password123\"
}" "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" || echo "")
if [ -n "$RESULT" ]; then ok "Admin user created"; else fail "Admin user creation failed"; fi

# ── Step 3: Login ──
step "Login as admin"
RESULT=$(api_post "/api/auth/login" "{
  \"tenant_id\": \"$TENANT_ID\",
  \"email\": \"$ADMIN_EMAIL\",
  \"password\": \"password123\"
}" || echo "")
if [ -n "$RESULT" ]; then ok "Logged in"; else fail "Login failed"; fi

# ── Step 4: Create Additional Users ──
step "Create team members"
for role_email in "operator:ops@acme-corp.com:Acme Ops" "auditor:auditor@acme-corp.com:Acme Auditor" "developer:dev@acme-corp.com:Acme Developer"; do
  IFS=':' read -r role email name <<< "$role_email"
  RESULT=$(api_post "/api/users/invite" "{\"email\":\"$email\",\"role\":\"$role\",\"display_name\":\"$name\"}" || echo "")
  if [ -n "$RESULT" ]; then ok "Invited $email ($role)"; else fail "Failed to invite $email"; fi
done

# ── Step 5: Create Blueprints ──
step "Create agent blueprints"
for bp in "customer-support-agent:Support agents:limited" "data-analyst-agent:Analytics agents:minimal" "security-agent:Security monitoring:high"; do
  IFS=':' read -r name desc tier <<< "$bp"
  RESULT=$(api_post "/api/blueprints" "{
    \"name\":\"$name\",\"description\":\"$desc\",\"risk_tier\":\"$tier\",
    \"allowed_tools\":[\"read\",\"query\",\"report\"],\"max_daily_tokens\":50000
  }" || echo "")
  if [ -n "$RESULT" ]; then ok "Blueprint: $name"; else fail "Blueprint: $name"; fi
done

# ── Step 6: Register Agents ──
step "Register AI agents (8 agents)"
AGENTS=("acme-support-bot:chatbot:gpt-4o:customer-support" "acme-analytics-bot:data_analyst:claude-sonnet-4-6:analytics" "acme-hr-bot:assistant:gpt-4o-mini:hr" "acme-finance-bot:data_analyst:gpt-4o:finance" "acme-security-scanner:scanner:claude-haiku-4-5:security" "acme-compliance-bot:compliance:gpt-4o:legal" "acme-devops-bot:automation:claude-sonnet-4-6:engineering" "acme-marketing-bot:content:gpt-4o-mini:marketing")
for agent_def in "${AGENTS[@]}"; do
  IFS=':' read -r name type model dept <<< "$agent_def"
  RESULT=$(api_post "/api/agents" "{
    \"name\":\"$name\",\"type\":\"$type\",\"model\":\"$model\",
    \"provider\":\"openai\",\"department\":\"$dept\",\"environment\":\"production\",
    \"description\":\"$name for $dept department\"
  }" || echo "")
  if [ -n "$RESULT" ]; then ok "Agent: $name"; else fail "Agent: $name"; fi
done

# ── Step 7: Create Guardrails ──
step "Create guardrail policies"
for gr in "pii-blocker:dlp:Block PII in agent responses" "toxicity-filter:content_safety:Block toxic content" "prompt-injection-guard:security:Detect prompt injection"; do
  IFS=':' read -r name type desc <<< "$gr"
  RESULT=$(api_post "/api/guardrails" "{
    \"name\":\"$name\",\"type\":\"$type\",\"description\":\"$desc\",
    \"rules\":[{\"pattern\":\"sensitive\",\"action\":\"block\"}],
    \"scope\":\"all_agents\",\"enabled\":true
  }" || echo "")
  if [ -n "$RESULT" ]; then ok "Guardrail: $name"; else fail "Guardrail: $name"; fi
done

# ── Step 8: Enable Compliance Frameworks ──
step "Enable compliance frameworks"
for fw in "soc2" "fedramp" "hipaa" "eu_ai_act" "gdpr" "nist_ai_rmf" "iso27001" "pci_dss" "ccpa" "nist_csf" "cis_controls" "cobit" "itil"; do
  RESULT=$(api_post "/api/compliance/frameworks" "{\"framework\":\"$fw\",\"enabled\":true}" || echo "")
  if [ -n "$RESULT" ]; then ok "Framework: $fw"; else fail "Framework: $fw"; fi
done

# ── Step 9: Create Egress Policies ──
step "Create egress policies"
RESULT=$(api_post "/api/policies/egress" '{
  "name":"approved-ai-providers",
  "rules":[
    {"destination":"api.openai.com","port":443,"action":"allow"},
    {"destination":"api.anthropic.com","port":443,"action":"allow"},
    {"destination":"*.bedrock.*.amazonaws.com","port":443,"action":"allow"},
    {"destination":"*","port":"*","action":"deny"}
  ],
  "applies_to":"all_agents"
}' || echo "")
if [ -n "$RESULT" ]; then ok "Egress policy: approved providers"; else fail "Egress policy"; fi

# ── Step 10: Create Workflows ──
step "Create lifecycle workflows"
for wf in "agent-onboarding:Agent Onboarding" "credential-rotation:Credential Rotation" "risk-escalation:Risk Escalation" "agent-decommission:Agent Decommission"; do
  IFS=':' read -r name desc <<< "$wf"
  RESULT=$(api_post "/api/workflows" "{
    \"name\":\"$name\",\"description\":\"$desc\",
    \"trigger\":{\"type\":\"manual\"},\"steps\":[],\"enabled\":true
  }" || echo "")
  if [ -n "$RESULT" ]; then ok "Workflow: $name"; else fail "Workflow: $name"; fi
done

# ── Step 11: Create Discovery Scanner Configs ──
step "Create discovery scanner configurations"
for scanner in "cloud:aws:AWS Cloud Scanner" "cloud:azure:Azure Cloud Scanner" "ide:vscode:IDE Scanner" "endpoint:network:Endpoint Scanner" "automation:github:Automation Scanner"; do
  IFS=':' read -r type provider desc <<< "$scanner"
  RESULT=$(api_post "/api/discovery/scanners" "{
    \"name\":\"acme-$provider-scanner\",\"type\":\"$type\",
    \"config\":{\"provider\":\"$provider\",\"scan_interval_hours\":24},
    \"enabled\":true
  }" || echo "")
  if [ -n "$RESULT" ]; then ok "Scanner: $desc"; else fail "Scanner: $desc"; fi
done

# ── Step 12: Create Budget ──
step "Create FinOps budgets"
RESULT=$(api_post "/api/finops/budgets" '{
  "name":"company-monthly","scope":{"tenant":"all"},
  "amount":10000.00,"currency":"USD","period":"monthly",
  "alerts":[{"threshold_percent":80,"channels":["email"]},{"threshold_percent":100,"channels":["email","slack"]}],
  "hard_limit":false
}' || echo "")
if [ -n "$RESULT" ]; then ok "Budget: company-monthly ($10k)"; else fail "Budget creation"; fi

# ── Step 13: Seed MCP Connections ──
step "Create MCP gateway connections"
RESULT=$(api_post "/api/mcp/connections" '{
  "name":"acme-postgresql","server":"mcp-server-postgresql",
  "config":{"host":"analytics-db","port":5432,"database":"analytics","user":"readonly","read_only":true},
  "enabled":true
}' || echo "")
if [ -n "$RESULT" ]; then ok "MCP: PostgreSQL connection"; else fail "MCP connection"; fi

# ── Summary ──
echo ""
echo "============================================"
echo "  Seed Complete"
echo "  ✅ $PASS passed | ❌ $FAIL failed"
echo "  Tenant: $TENANT_ID"
echo "  Dashboard: https://app.rt19.runtimeai.io"
echo "  Login: $ADMIN_EMAIL / password123"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n${YELLOW}Some steps failed. Check the API logs:${NC}"
  echo "  kubectl logs -n rt19 deployment/control-plane --tail=50"
  exit 1
fi

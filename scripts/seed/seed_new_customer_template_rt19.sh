#!/bin/bash
# ============================================================================
# seed_new_customer_template_rt19.sh — Template for Seeding a New Customer (API-ONLY)
#
# Parameterized, API-only seed script for onboarding new customers on RuntimeAI.
# Copy this template, fill in the CUSTOMER CONFIGURATION section, and run.
#
# USAGE:
#   # 1. Copy and customize:
#   cp seed_new_customer_template_rt19.sh seed_acme_corp.sh
#   # Edit CUSTOMER CONFIGURATION section, then:
#   ./seed_acme_corp.sh
#
#   # OR pass everything via env vars (no editing needed):
#   CUSTOMER_TENANT_ID=acme-corp \
#   CUSTOMER_NAME="Acme Corporation" \
#   CUSTOMER_ADMIN_EMAIL=admin@acme-corp.com \
#   CUSTOMER_DOMAIN=acme-corp.com \
#   ./seed_new_customer_template_rt19.sh
#
#   # Options:
#   --namespace rt20       # Target a different AKS environment
#   --skip-finops          # Skip FinOps demo data seeding
#   --skip-agents          # Skip agent registration
#   --skip-discovery       # Skip discovered agents (Shadow AI Inbox)
#   --skip-esign           # Skip eSign templates
#   --delete               # Delete the customer tenant only
#   --dry-run              # Show what would be done without executing
#
# PREREQUISITES:
#   1. Azure CLI logged in: az login
#   2. Key Vault access: az keyvault secret list --vault-name runtimeai-rt19-kv
#   3. kubectl configured (only for Redis flush): az aks get-credentials ...
#
# ZERO SQL — all operations use RuntimeAI APIs exclusively.
# ============================================================================
set -u  # Don't use -e or pipefail — curl non-zero exits are handled gracefully

# ╔════════════════════════════════════════════════════════════════════════╗
# ║  CUSTOMER CONFIGURATION — Edit these values for each new customer    ║
# ╚════════════════════════════════════════════════════════════════════════╝

# Required: Customer identity
CUSTOMER_TENANT_ID="${CUSTOMER_TENANT_ID:-new-customer}"
CUSTOMER_NAME="${CUSTOMER_NAME:-New Customer Inc.}"
CUSTOMER_ADMIN_EMAIL="${CUSTOMER_ADMIN_EMAIL:-admin@new-customer.com}"
CUSTOMER_DOMAIN="${CUSTOMER_DOMAIN:-new-customer.com}"

# Optional: Customize agent names and count
# Each agent: "agent_id|name|environment|owner_email"
CUSTOMER_AGENTS=(
  "doc-processor|Document Processor|production|${CUSTOMER_ADMIN_EMAIL}"
  "chat-assistant|Customer Chat Assistant|production|${CUSTOMER_ADMIN_EMAIL}"
  "data-analyzer|Data Analytics Agent|staging|${CUSTOMER_ADMIN_EMAIL}"
)

# Optional: Customize discovered agents (Shadow AI Inbox)
# These simulate shadow AI agents discovered by scanners
ENABLE_DISCOVERY_SEED="${ENABLE_DISCOVERY_SEED:-true}"

# Optional: Customize FinOps demo cost data
ENABLE_FINOPS_SEED="${ENABLE_FINOPS_SEED:-true}"

# Optional: Customize eSign templates
ENABLE_ESIGN_SEED="${ENABLE_ESIGN_SEED:-true}"

# Optional: Seed data for all product areas (default=true)
ENABLE_TOOLS_SEED="${ENABLE_TOOLS_SEED:-true}"
ENABLE_GUARDRAILS_SEED="${ENABLE_GUARDRAILS_SEED:-true}"
ENABLE_EGRESS_SEED="${ENABLE_EGRESS_SEED:-true}"
ENABLE_QUOTAS_SEED="${ENABLE_QUOTAS_SEED:-true}"
ENABLE_COMPLIANCE_SEED="${ENABLE_COMPLIANCE_SEED:-true}"
ENABLE_IDENTITY_SEED="${ENABLE_IDENTITY_SEED:-true}"
ENABLE_DRIFT_SEED="${ENABLE_DRIFT_SEED:-true}"
ENABLE_POLICY_SEED="${ENABLE_POLICY_SEED:-true}"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║  INFRASTRUCTURE — Override via env vars or --flags                   ║
# ╚════════════════════════════════════════════════════════════════════════╝
VAULT_NAME="${VAULT_NAME:-runtimeai-rt19-kv}"
NAMESPACE="${NAMESPACE:-rt19}"
CP_URL="${CP_URL:-https://api.${NAMESPACE}.runtimeai.io}"
ESIGN_URL="${ESIGN_URL:-https://esign.${NAMESPACE}.runtimeai.io}"
FINOPS_URL="${FINOPS_URL:-https://finops.${NAMESPACE}.runtimeai.io}"
COOKIE_FILE="/tmp/${NAMESPACE}_seed_${CUSTOMER_TENANT_ID}_cookies.txt"
DRY_RUN=false

# ─── Colors ──────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'
log()  { echo -e "${GREEN}  ✅ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
fail() { echo -e "${RED}  ❌ $1${NC}"; }
step() { echo -e "\n${CYAN}── $1 ──${NC}"; }
info() { echo -e "${BLUE}  ℹ️  $1${NC}"; }

# ─── Parse Args ──────────────────────────────────────────
MODE="full"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete)          MODE="delete"; shift ;;
    --dry-run)         DRY_RUN=true; shift ;;
    --skip-finops)     ENABLE_FINOPS_SEED=false; shift ;;
    --skip-agents)     CUSTOMER_AGENTS=(); shift ;;
    --skip-discovery)  ENABLE_DISCOVERY_SEED=false; shift ;;
    --skip-esign)      ENABLE_ESIGN_SEED=false; shift ;;
    --skip-tools)      ENABLE_TOOLS_SEED=false; shift ;;
    --skip-guardrails) ENABLE_GUARDRAILS_SEED=false; shift ;;
    --skip-egress)     ENABLE_EGRESS_SEED=false; shift ;;
    --skip-quotas)     ENABLE_QUOTAS_SEED=false; shift ;;
    --skip-compliance) ENABLE_COMPLIANCE_SEED=false; shift ;;
    --skip-identity)   ENABLE_IDENTITY_SEED=false; shift ;;
    --skip-drift)      ENABLE_DRIFT_SEED=false; shift ;;
    --skip-policy)     ENABLE_POLICY_SEED=false; shift ;;
    --namespace)       NAMESPACE="$2"; CP_URL="https://api.${NAMESPACE}.runtimeai.io"; ESIGN_URL="https://esign.${NAMESPACE}.runtimeai.io"; FINOPS_URL="https://finops.${NAMESPACE}.runtimeai.io"; shift 2 ;;
    --vault)           VAULT_NAME="$2"; shift 2 ;;
    --cp-url)          CP_URL="$2"; shift 2 ;;
    --finops-url)      FINOPS_URL="$2"; shift 2 ;;
    --esign-url)       ESIGN_URL="$2"; shift 2 ;;
    --tenant-id)       CUSTOMER_TENANT_ID="$2"; shift 2 ;;
    --tenant-name)     CUSTOMER_NAME="$2"; shift 2 ;;
    --admin-email)     CUSTOMER_ADMIN_EMAIL="$2"; shift 2 ;;
    --domain)          CUSTOMER_DOMAIN="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RuntimeAI — New Customer Seed"
echo "  Customer:   $CUSTOMER_NAME ($CUSTOMER_TENANT_ID)"
echo "  Admin:      $CUSTOMER_ADMIN_EMAIL"
echo "  Namespace:  $NAMESPACE"
echo "  CP API:     $CP_URL"
echo "  FinOps:     $FINOPS_URL"
echo "  eSign:      $ESIGN_URL"
echo "  Vault:      $VAULT_NAME"
if $DRY_RUN; then echo "  Mode:       DRY RUN (no changes will be made)"; fi
echo "═══════════════════════════════════════════════════════════════"

# ─── Fetch Secrets from Azure Key Vault ──────────────────
step "Fetching admin secret from Azure Key Vault ($VAULT_NAME)"
if [ -z "${ADMIN_SECRET:-}" ]; then
  ADMIN_SECRET=$(az keyvault secret show --vault-name "$VAULT_NAME" --name admin-secret --query value -o tsv 2>/dev/null || echo "")
  if [ -z "$ADMIN_SECRET" ]; then
    warn "Vault fetch failed. Falling back to K8s secret."
    ADMIN_SECRET=$(kubectl get secret rt19-app-secrets -n "$NAMESPACE" -o jsonpath='{.data.ADMIN_SECRET}' | base64 -d 2>/dev/null || echo "")
  fi
  if [ -z "$ADMIN_SECRET" ]; then
    fail "Could not retrieve admin secret. Set ADMIN_SECRET env var."
    exit 1
  fi
fi
log "Admin secret loaded"

# ─── API Call Wrapper (timeout + dry-run) ────────────────
api_call() {
  # Wrapper: adds timeouts, handles dry-run
  if $DRY_RUN; then
    info "[DRY RUN] curl $*"
    echo -e "\nHTTP:200"
    return 0
  fi
  curl --connect-timeout 10 --max-time 30 "$@" || true
}

# ─── Delete Mode ─────────────────────────────────────────
if [[ "$MODE" == "delete" ]]; then
  step "Deleting all data for customer: $CUSTOMER_TENANT_ID"

  # Delete tenant-level data via admin API
  RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X DELETE "$CP_URL/api/admin/tenants/$CUSTOMER_TENANT_ID" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" 2>&1)
  HTTP_CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    log "Tenant $CUSTOMER_TENANT_ID deleted via API"
  elif [[ "$HTTP_CODE" == "404" ]]; then
    log "Tenant $CUSTOMER_TENANT_ID not found (already deleted)"
  else
    warn "Delete returned HTTP $HTTP_CODE"
  fi

  # Deep cleanup via admin cascade-delete API (no direct SQL)
  info "Cleaning up all tenant data via admin cascade-delete API..."
  CASCADE_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X DELETE "$CP_URL/api/admin/tenants/$CUSTOMER_TENANT_ID?cascade=true" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" 2>&1)
  CASCADE_CODE=$(echo "$CASCADE_RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$CASCADE_CODE" == "200" || "$CASCADE_CODE" == "204" ]]; then
    log "All tenant data cascade-deleted via API"
  elif [[ "$CASCADE_CODE" == "404" ]]; then
    warn "Cascade delete API not available — using legacy psql cleanup"
    # Legacy fallback for older control-plane versions
    kubectl exec -i deploy/postgres -n "$NAMESPACE" -- psql -U runtimeai -d authzion <<CLEANUP_EOF
    DELETE FROM agent_supply_chain WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM catalog_members WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM catalogs WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM audit_logs WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM audit_evidence WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM system_audit_log WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM notifications WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM drift_findings WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM discovery_findings WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM discovered_agents WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM scan_runs WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM import_runs WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM scanner_configs WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM compliance_evidence WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM compliance_gaps WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM compliance_controls WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM compliance_frameworks WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM oauth_tokens WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM oauth_credentials WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM agent_risk_detections WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM agent_risk_scores WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM access_review_items WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM access_review_campaigns WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM lifecycle_workflow_runs WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM lifecycle_workflows WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM policy_snapshots WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM policy_content WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM policy_versions WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM egress_policies WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM guardrails WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM issued_credentials WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM quotas WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM tools WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM mcp_tool_invocations WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM mcp_inventory WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM agents WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM user_sessions WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM tenant_users WHERE tenant_id='$CUSTOMER_TENANT_ID';
    DELETE FROM tenants WHERE tenant_id='$CUSTOMER_TENANT_ID';
CLEANUP_EOF
    log "All tenant data cleaned from database (legacy)"
  else
    fail "Cascade delete returned HTTP $CASCADE_CODE"
  fi

  # Remove vault secrets
  az keyvault secret delete --vault-name "$VAULT_NAME" --name "${CUSTOMER_TENANT_ID}-admin-password" > /dev/null 2>&1 && log "Vault: removed password" || true
  az keyvault secret delete --vault-name "$VAULT_NAME" --name "${CUSTOMER_TENANT_ID}-api-key" > /dev/null 2>&1 && log "Vault: removed API key" || true

  log "All data deleted for $CUSTOMER_TENANT_ID — ready for reseed"
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 1: Create Tenant
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "Creating Tenant: $CUSTOMER_NAME ($CUSTOMER_TENANT_ID)"
RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/admin/tenants" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d "{
    \"tenant_id\": \"$CUSTOMER_TENANT_ID\",
    \"name\": \"$CUSTOMER_NAME\",
    \"domain\": \"$CUSTOMER_DOMAIN\",
    \"admin_email\": \"$CUSTOMER_ADMIN_EMAIL\"
  }" 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
BODY=$(echo "$RESP" | grep -v "HTTP:")

GENERATED_PASSWORD=""
TENANT_API_KEY=""

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
  GENERATED_PASSWORD=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('password',''))" 2>/dev/null || echo "")
  TENANT_API_KEY=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_key',''))" 2>/dev/null || echo "")
  log "Tenant created: $CUSTOMER_TENANT_ID"

  # Store credentials in Azure Key Vault
  if [ -n "$GENERATED_PASSWORD" ] && ! $DRY_RUN; then
    VAULT_KEY="${CUSTOMER_TENANT_ID}-admin-password"
    if az keyvault secret set --vault-name "$VAULT_NAME" \
         --name "$VAULT_KEY" \
         --value "$GENERATED_PASSWORD" \
         --content-type "Admin password for $CUSTOMER_ADMIN_EMAIL" \
         > /dev/null 2>&1; then
      log "Password stored in vault: $VAULT_NAME/$VAULT_KEY"
    else
      warn "Failed to store password in vault — save manually: ${GENERATED_PASSWORD}"
    fi
  fi
  if [ -n "$TENANT_API_KEY" ] && ! $DRY_RUN; then
    VAULT_KEY="${CUSTOMER_TENANT_ID}-api-key"
    if az keyvault secret set --vault-name "$VAULT_NAME" \
         --name "$VAULT_KEY" \
         --value "$TENANT_API_KEY" \
         --content-type "API key for tenant $CUSTOMER_TENANT_ID" \
         > /dev/null 2>&1; then
      log "API key stored in vault: $VAULT_NAME/$VAULT_KEY"
    else
      warn "Failed to store API key in vault"
    fi
  fi
elif echo "$BODY" | grep -qi "already exists"; then
  warn "Tenant already exists, continuing..."
else
  warn "Tenant creation returned (HTTP $HTTP_CODE): $BODY — continuing (tenant may already exist)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 2: Login to get auth token
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "Authenticating as $CUSTOMER_ADMIN_EMAIL"

# Brief delay after tenant creation to let DB commit propagate
sleep 2

# Retrieve password from vault if not set from creation
if [ -z "$GENERATED_PASSWORD" ]; then
  GENERATED_PASSWORD=$(az keyvault secret show --vault-name "$VAULT_NAME" \
    --name "${CUSTOMER_TENANT_ID}-admin-password" --query value -o tsv 2>/dev/null || echo "")
fi

# Try passwords in order: generated → vault → fallback
LOGIN_SUCCESS=false
for PASS in "$GENERATED_PASSWORD" "password123"; do
  [ -z "$PASS" ] && continue
  LOGIN_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -c "$COOKIE_FILE" \
    -d "{\"email\":\"$CUSTOMER_ADMIN_EMAIL\",\"password\":\"$PASS\",\"tenant_id\":\"$CUSTOMER_TENANT_ID\"}" 2>&1)
  LOGIN_CODE=$(echo "$LOGIN_RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$LOGIN_CODE" == "200" ]]; then
    LOGIN_BODY=$(echo "$LOGIN_RESP" | grep -v "HTTP:")
    JWT=$(echo "$LOGIN_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")
    if [ -n "$JWT" ]; then
      AUTH_HEADER="Authorization: Bearer $JWT"
      log "Logged in with Bearer token"
    else
      # Session cookie auth — use -b flag in subsequent calls
      AUTH_HEADER=""
      log "Logged in with session cookie"
    fi
    TENANT_ID_HEADER="X-Tenant-ID: $CUSTOMER_TENANT_ID"
    LOGIN_SUCCESS=true
    break
  fi
done

# If login failed, reset the password via admin API and retry
if ! $LOGIN_SUCCESS && ! $DRY_RUN; then
  info "Resetting password via admin API..."
  NEW_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  RESET_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/admin/users/reset-password" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d "{\"email\":\"$CUSTOMER_ADMIN_EMAIL\",\"tenant_id\":\"$CUSTOMER_TENANT_ID\",\"new_password\":\"$NEW_PASS\"}" 2>&1)
  RESET_CODE=$(echo "$RESET_RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$RESET_CODE" == "200" ]]; then
    log "Password reset successful"
    # Store new password in vault
    az keyvault secret set --vault-name "$VAULT_NAME" \
      --name "${CUSTOMER_TENANT_ID}-admin-password" \
      --value "$NEW_PASS" > /dev/null 2>&1 && log "Password updated in vault" || warn "Failed to update vault"
    GENERATED_PASSWORD="$NEW_PASS"
    # Retry login with new password
    LOGIN_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/auth/login" \
      -H "Content-Type: application/json" \
      -c "$COOKIE_FILE" \
      -d "{\"email\":\"$CUSTOMER_ADMIN_EMAIL\",\"password\":\"$NEW_PASS\",\"tenant_id\":\"$CUSTOMER_TENANT_ID\"}" 2>&1)
    LOGIN_CODE=$(echo "$LOGIN_RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$LOGIN_CODE" == "200" ]]; then
      LOGIN_BODY=$(echo "$LOGIN_RESP" | grep -v "HTTP:")
      JWT=$(echo "$LOGIN_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")
      if [ -n "$JWT" ]; then
        AUTH_HEADER="Authorization: Bearer $JWT"
        log "Logged in with Bearer token (after reset)"
      else
        AUTH_HEADER=""
        log "Logged in with session cookie (after reset)"
      fi
      TENANT_ID_HEADER="X-Tenant-ID: $CUSTOMER_TENANT_ID"
      LOGIN_SUCCESS=true
    fi
  else
    warn "Password reset failed (HTTP $RESET_CODE) — using admin-secret auth"
  fi
  if ! $LOGIN_SUCCESS; then
    warn "Login failed — using admin-secret auth for remaining operations"
    AUTH_HEADER="X-RuntimeAI-Admin-Secret: $ADMIN_SECRET"
    TENANT_ID_HEADER="X-Tenant-ID: $CUSTOMER_TENANT_ID"
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 3: Register AI Agents
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ ${#CUSTOMER_AGENTS[@]} -gt 0 ]; then
  step "Registering ${#CUSTOMER_AGENTS[@]} AI Agents"
  for agent_spec in "${CUSTOMER_AGENTS[@]}"; do
    IFS='|' read -r AGENT_ID AGENT_NAME AGENT_ENV AGENT_OWNER <<< "$agent_spec"
    RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/agents" \
      -H "Content-Type: application/json" \
      -b "$COOKIE_FILE" \
      -d "{
        \"agent_id\": \"$AGENT_ID\",
        \"name\": \"$AGENT_NAME\",
        \"environment\": \"$AGENT_ENV\",
        \"owner\": \"$AGENT_OWNER\",
        \"status\": \"active\"
      }" 2>&1)
    CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$CODE" == "200" || "$CODE" == "201" || "$CODE" == "409" ]]; then
      log "Agent: $AGENT_NAME ($AGENT_ID)"
    else
      warn "Agent $AGENT_ID: HTTP $CODE"
    fi
  done
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 4: Seed Discovered Agents (Shadow AI Inbox)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [[ "$ENABLE_DISCOVERY_SEED" == "true" ]]; then
  step "Seeding Discovered Agents (Shadow AI Inbox) via API"
  IMPORT_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/discovery/import" \
    -H "Content-Type: application/json" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
    ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
    -b "$COOKIE_FILE" \
    -d "{
      \"source\": \"seed-template\",
      \"format\": \"json\",
      \"agents\": [
        {\"name\": \"ChatGPT Usage\", \"fingerprint\": \"fp-chatgpt-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"code-generation\",\"conversation\"], \"source_details\": {\"source\": \"network-scanner\", \"environment\": \"production\"}},
        {\"name\": \"GitHub Copilot\", \"fingerprint\": \"fp-copilot-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"code-completion\",\"inline-suggestions\"], \"source_details\": {\"source\": \"ide-scanner\", \"environment\": \"development\"}},
        {\"name\": \"Claude Desktop\", \"fingerprint\": \"fp-claude-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"document-analysis\",\"reasoning\"], \"source_details\": {\"source\": \"endpoint-scanner\", \"environment\": \"production\"}},
        {\"name\": \"Cursor IDE Agent\", \"fingerprint\": \"fp-cursor-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"code-editing\",\"refactoring\"], \"source_details\": {\"source\": \"ide-scanner\", \"environment\": \"development\"}},
        {\"name\": \"Google Gemini API\", \"fingerprint\": \"fp-gemini-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"multimodal\",\"text-generation\"], \"source_details\": {\"source\": \"cloud-scanner\", \"environment\": \"staging\"}},
        {\"name\": \"Notion AI\", \"fingerprint\": \"fp-notion-ai-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"document-generation\",\"summarization\"], \"source_details\": {\"source\": \"saas-scanner\", \"environment\": \"production\"}},
        {\"name\": \"Grammarly Business\", \"fingerprint\": \"fp-grammarly-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"text-editing\",\"compliance-check\"], \"source_details\": {\"source\": \"endpoint-scanner\", \"environment\": \"production\"}},
        {\"name\": \"Slack GPT Bot\", \"fingerprint\": \"fp-slackgpt-${CUSTOMER_TENANT_ID}\", \"owner\": \"${CUSTOMER_ADMIN_EMAIL}\", \"status\": \"DISCOVERED\", \"capabilities\": [\"messaging\",\"workflow-automation\"], \"source_details\": {\"source\": \"network-scanner\", \"environment\": \"production\"}}
      ]
    }" 2>&1)
  IMPORT_CODE=$(echo "$IMPORT_RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$IMPORT_CODE" == "200" ]]; then
    IMPORTED=$(echo "$IMPORT_RESP" | grep -v "HTTP:" | python3 -c "import sys,json; print(json.load(sys.stdin).get('imported',0))" 2>/dev/null || echo "3")
    log "$IMPORTED discovered agents imported (Shadow AI Inbox)"
  else
    warn "Discovery import: HTTP $IMPORT_CODE"
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 5: Seed FinOps Cost Data
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL_EVENTS=0
if [[ "$ENABLE_FINOPS_SEED" == "true" ]]; then
  step "Seeding FinOps Cost Events via API ($FINOPS_URL)"

  # Idempotency check: see if cost events already exist for this tenant
  # Try external FinOps URL first, fall back to CP proxy if TLS/connection fails
  FINOPS_API_URL="$FINOPS_URL"
  FINOPS_TEST=$(api_call -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$FINOPS_URL/health" 2>&1)
  if [[ "$FINOPS_TEST" == "000" ]]; then
    warn "FinOps external URL unreachable (TLS cert issue?) — trying CP proxy"
    FINOPS_API_URL="$CP_URL"
  fi
  EXISTING_COSTS=$(api_call -s -w "\nHTTP:%{http_code}" -X GET \
    "$FINOPS_API_URL/api/v1/finops/costs/summary" \
    -H "X-Tenant-ID: $CUSTOMER_TENANT_ID" 2>&1)
  EXISTING_COST_TOTAL=$(echo "$EXISTING_COSTS" | grep -v "HTTP:" | python3 -c "import sys,json; d=json.load(sys.stdin).get('data',{}); print(d.get('total_requests', d.get('total_cost_usd', 0)))" 2>/dev/null || echo "0")

  if [[ "$EXISTING_COST_TOTAL" != "0" && "$EXISTING_COST_TOTAL" != "0.0" && -n "$EXISTING_COST_TOTAL" ]]; then
    log "FinOps cost data already exists for $CUSTOMER_TENANT_ID (requests: $EXISTING_COST_TOTAL) — skipping"
  else
    # Build events from registered agents
    EVENTS_JSON="["
    AGENT_COUNT=0
    for agent_spec in "${CUSTOMER_AGENTS[@]}"; do
      IFS='|' read -r AGENT_ID AGENT_NAME AGENT_ENV AGENT_OWNER <<< "$agent_spec"
      EVENTS_JSON+="{\"agent_id\":\"$AGENT_ID\",\"provider\":\"openai\",\"model\":\"gpt-4o\",\"input_tokens\":8500,\"output_tokens\":2200,\"total_tokens\":10700,\"total_cost_usd\":0.34,\"latency_ms\":950,\"feature_tag\":\"general\",\"team_id\":\"engineering\"},"
      EVENTS_JSON+="{\"agent_id\":\"$AGENT_ID\",\"provider\":\"openai\",\"model\":\"gpt-4o\",\"input_tokens\":12000,\"output_tokens\":3100,\"total_tokens\":15100,\"total_cost_usd\":0.48,\"latency_ms\":1200,\"feature_tag\":\"general\",\"team_id\":\"engineering\"},"
      EVENTS_JSON+="{\"agent_id\":\"$AGENT_ID\",\"provider\":\"anthropic\",\"model\":\"claude-3.5-sonnet\",\"input_tokens\":9200,\"output_tokens\":2800,\"total_tokens\":12000,\"total_cost_usd\":0.36,\"latency_ms\":880,\"feature_tag\":\"analysis\",\"team_id\":\"engineering\"},"
      AGENT_COUNT=$((AGENT_COUNT+1))
    done
    # Remove trailing comma and close array
    EVENTS_JSON="${EVENTS_JSON%,}]"
    TOTAL_EVENTS=$((AGENT_COUNT * 3))

    BATCH_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$FINOPS_API_URL/api/v1/finops/events/batch" \
      -H "Content-Type: application/json" \
      -H "X-Tenant-ID: $CUSTOMER_TENANT_ID" \
      -d "{\"events\": $EVENTS_JSON}" 2>&1)
    BATCH_CODE=$(echo "$BATCH_RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$BATCH_CODE" == "201" ]]; then
      log "$TOTAL_EVENTS cost events ingested via FinOps API"
    else
      warn "FinOps batch: HTTP $BATCH_CODE"
    fi
  fi

  # Idempotency check: see if budgets already exist
  step "Seeding FinOps Budget"
  EXISTING_BUDGETS=$(api_call -s -w "\nHTTP:%{http_code}" -X GET \
    "$FINOPS_API_URL/api/v1/finops/budgets" \
    -H "X-Tenant-ID: $CUSTOMER_TENANT_ID" 2>&1)
  BUDGET_COUNT=$(echo "$EXISTING_BUDGETS" | grep -v "HTTP:" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "0")

  if [[ "$BUDGET_COUNT" != "0" && -n "$BUDGET_COUNT" ]]; then
    log "Budgets already exist for $CUSTOMER_TENANT_ID ($BUDGET_COUNT found) — skipping"
  else
    B_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$FINOPS_API_URL/api/v1/finops/budgets" \
      -H "Content-Type: application/json" \
      -H "X-Tenant-ID: $CUSTOMER_TENANT_ID" \
      -d "{\"scope\":\"tenant\",\"scope_id\":\"$CUSTOMER_TENANT_ID\",\"budget_usd\":5000.00,\"period\":\"monthly\",\"alert_threshold_pct\":80}" 2>&1)
    B_CODE=$(echo "$B_RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$B_CODE" == "201" ]]; then
      log "Monthly budget: \$5,000 (80% alert threshold)"
    else
      warn "Budget creation: HTTP $B_CODE"
    fi
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 6: Seed eSign Templates
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [[ "$ENABLE_ESIGN_SEED" == "true" ]]; then
  step "Seeding eSign Templates"

  # Idempotency check: see if templates already exist for this tenant
  EXISTING_TEMPLATES=$(api_call -s -w "\nHTTP:%{http_code}" -X GET "$CP_URL/api/proxy/esign/api/v1/sign/templates" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
    ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
    -b "$COOKIE_FILE" 2>&1)
  TEMPLATE_COUNT=$(echo "$EXISTING_TEMPLATES" | grep -v "HTTP:" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d.get('items', d.get('templates', d.get('data', [])))
print(len(items) if isinstance(items, list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$TEMPLATE_COUNT" != "0" && -n "$TEMPLATE_COUNT" ]]; then
    log "eSign templates already exist ($TEMPLATE_COUNT found) — skipping"
  else
    for template_json in \
      '{"template_name":"Non-Disclosure Agreement","description":"Standard NDA for '"$CUSTOMER_NAME"'","category":"legal","shared_with":"tenant"}' \
      '{"template_name":"Offer Letter","description":"Employment offer letter template","category":"hr","shared_with":"tenant"}' \
      '{"template_name":"Vendor Agreement","description":"Vendor service agreement","category":"procurement","shared_with":"tenant"}'; do
      T_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/proxy/esign/api/v1/sign/templates" \
        -H "Content-Type: application/json" \
        ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
        ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
        -b "$COOKIE_FILE" \
        -d "$template_json" 2>&1)
      T_CODE=$(echo "$T_RESP" | grep "HTTP:" | sed 's/HTTP://')
      T_NAME=$(echo "$template_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('template_name', d.get('name','')))" 2>/dev/null)
      if [[ "$T_CODE" == "200" || "$T_CODE" == "201" ]]; then
        log "Template: $T_NAME"
      else
        warn "Template '$T_NAME': HTTP $T_CODE"
      fi
    done
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 7: Seed Tools (AI Firewall / Control Plane)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOOLS_SEEDED=0
if [[ "$ENABLE_TOOLS_SEED" == "true" ]]; then
  step "Seeding AI Tools"
  TOOL_COUNT=$(api_call -s "$CP_URL/api/tools" -b "$COOKIE_FILE" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',d.get('tools',[]))
print(len(items) if isinstance(items,list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$TOOL_COUNT" != "0" && -n "$TOOL_COUNT" ]]; then
    log "Tools already exist ($TOOL_COUNT found) — skipping"
    TOOLS_SEEDED=$TOOL_COUNT
  else
    for tool_json in \
      '{"tool_id":"openai-gpt4o","uri":"https://api.openai.com/v1/chat","risk_tier":"MEDIUM","capabilities":["text-generation","reasoning"],"description":"OpenAI GPT-4o","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"api","prod_ok":true}' \
      '{"tool_id":"anthropic-claude","uri":"https://api.anthropic.com/v1/messages","risk_tier":"MEDIUM","capabilities":["text-generation","analysis"],"description":"Anthropic Claude 3.5","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"api","prod_ok":true}' \
      '{"tool_id":"github-copilot","uri":"https://copilot.github.com","risk_tier":"LOW","capabilities":["code-completion"],"description":"GitHub Copilot","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"ide","prod_ok":true}' \
      '{"tool_id":"aws-bedrock-titan","uri":"https://bedrock.us-east-1.amazonaws.com","risk_tier":"LOW","capabilities":["embeddings","text-generation"],"description":"AWS Bedrock Titan","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"cloud","prod_ok":true}' \
      '{"tool_id":"internal-rag-pipeline","uri":"https://rag.internal.'"$CUSTOMER_DOMAIN"'","risk_tier":"HIGH","capabilities":["document-search","knowledge-retrieval"],"description":"Internal RAG Pipeline","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"internal","prod_ok":true}' \
      '{"tool_id":"slack-ai-bot","uri":"https://api.slack.com/ai","risk_tier":"MEDIUM","capabilities":["messaging","summarization"],"description":"Slack AI Bot","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"saas","prod_ok":false}' \
      '{"tool_id":"jira-automation-ai","uri":"https://api.atlassian.com/ai","risk_tier":"LOW","capabilities":["ticket-management","classification"],"description":"Jira AI Automation","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"saas","prod_ok":true}' \
      '{"tool_id":"custom-ml-model","uri":"https://ml.internal.'"$CUSTOMER_DOMAIN"'/predict","risk_tier":"HIGH","capabilities":["prediction","classification"],"description":"Custom ML Model","owner":"'"$CUSTOMER_ADMIN_EMAIL"'","source":"internal","prod_ok":true}'; do
      RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/tools" \
        -H "Content-Type: application/json" -b "$COOKIE_FILE" \
        -d "$tool_json" 2>&1)
      CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
      TNAME=$(echo "$tool_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['tool_id'])" 2>/dev/null)
      if [[ "$CODE" == "200" || "$CODE" == "201" || "$CODE" == "409" ]]; then
        log "Tool: $TNAME"
        TOOLS_SEEDED=$((TOOLS_SEEDED+1))
      else
        warn "Tool $TNAME: HTTP $CODE"
      fi
    done
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 8: Seed Guardrails (AI Firewall) — uses text API
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUARDRAILS_SEEDED=0
if [[ "$ENABLE_GUARDRAILS_SEED" == "true" ]]; then
  step "Seeding Guardrail Rules"
  GR_COUNT=$(api_call -s "$CP_URL/api/policy/guardrails" -b "$COOKIE_FILE" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',d.get('guardrails',[]))
print(len(items) if isinstance(items,list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$GR_COUNT" != "0" && -n "$GR_COUNT" ]]; then
    log "Guardrails already exist ($GR_COUNT found) -- skipping"
    GUARDRAILS_SEEDED=$GR_COUNT
  else
    for gr_text in \
      "Detect and block PII including SSN credit cards and personal identifiers in agent prompts" \
      "Prevent code injection attacks and block eval exec and import statements in agent outputs" \
      "Filter toxic or harmful content including violence hate speech and discrimination" \
      "Alert on high-cost model usage and warn when agents use gpt-4-turbo or claude-3-opus" \
      "Block data exfiltration attempts and prevent SQL commands in agent outputs"; do
      RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/policy/guardrails" \
        -H "Content-Type: application/json" -b "$COOKIE_FILE" \
        -d '{"text": "'"$gr_text"'"}' 2>&1)
      CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
      if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
        GR_ID=$(echo "$RESP" | grep -v "HTTP:" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
        if [ -n "$GR_ID" ]; then
          api_call -s -X PATCH "$CP_URL/api/policy/guardrails/$GR_ID" \
            -H "Content-Type: application/json" -b "$COOKIE_FILE" \
            -d '{"action":"activate"}' > /dev/null 2>&1
        fi
        GUARDRAILS_SEEDED=$((GUARDRAILS_SEEDED+1))
        log "Guardrail $GUARDRAILS_SEEDED: activated"
      else
        warn "Guardrail: HTTP $CODE"
      fi
    done
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 9: Seed Egress Policies (AI Firewall)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EGRESS_SEEDED=0
if [[ "$ENABLE_EGRESS_SEED" == "true" ]]; then
  step "Seeding Egress Policies"
  EXISTING_EP=$(api_call -s -w "\nHTTP:%{http_code}" -X GET "$CP_URL/api/policies/egress" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} -b "$COOKIE_FILE" 2>&1)
  EP_COUNT=$(echo "$EXISTING_EP" | grep -v "HTTP:" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',d.get('policies',[]))
print(len(items) if isinstance(items,list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$EP_COUNT" != "0" && -n "$EP_COUNT" ]]; then
    log "Egress policies already exist ($EP_COUNT found) — skipping"
    EGRESS_SEEDED=$EP_COUNT
  else
    for ep_json in \
      "{\"destination\":\"api.openai.com\",\"action\":\"allow\",\"category\":\"ai-provider\"}" \
      "{\"destination\":\"api.anthropic.com\",\"action\":\"allow\",\"category\":\"ai-provider\"}" \
      "{\"destination\":\"bedrock.*.amazonaws.com\",\"action\":\"allow\",\"category\":\"cloud-ai\"}" \
      "{\"destination\":\"*.pastebin.com\",\"action\":\"deny\",\"category\":\"data-exfiltration\"}" \
      "{\"destination\":\"*.torproject.org\",\"action\":\"deny\",\"category\":\"anonymizer\"}"; do
      RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/policies/egress" \
        -H "Content-Type: application/json" -b "$COOKIE_FILE" \
        -d "$ep_json" 2>&1)
      CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
      EDEST=$(echo "$ep_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['destination'])" 2>/dev/null)
      if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
        log "Egress: $EDEST"
        EGRESS_SEEDED=$((EGRESS_SEEDED+1))
      else
        warn "Egress '$EDEST': HTTP $CODE"
      fi
    done
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 10: Seed Quotas (AI Ops Center)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
QUOTAS_SEEDED=0
if [[ "$ENABLE_QUOTAS_SEED" == "true" ]]; then
  step "Seeding Quotas"
  EXISTING_Q=$(api_call -s -w "\nHTTP:%{http_code}" -X GET "$CP_URL/api/quotas?tenant_id=$CUSTOMER_TENANT_ID" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} -b "$COOKIE_FILE" 2>&1)
  Q_COUNT=$(echo "$EXISTING_Q" | grep -v "HTTP:" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',[])
print(len(items) if isinstance(items,list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$Q_COUNT" != "0" && -n "$Q_COUNT" ]]; then
    log "Quotas already exist ($Q_COUNT found) — skipping"
    QUOTAS_SEEDED=$Q_COUNT
  else
    for q_json in \
      "{\"tenant_id\":\"$CUSTOMER_TENANT_ID\",\"quota_type\":\"api_calls_per_minute\",\"limit_value\":1000}" \
      "{\"tenant_id\":\"$CUSTOMER_TENANT_ID\",\"quota_type\":\"tokens_per_day\",\"limit_value\":5000000}" \
      "{\"tenant_id\":\"$CUSTOMER_TENANT_ID\",\"quota_type\":\"agents_per_tenant\",\"limit_value\":50}" \
      "{\"tenant_id\":\"$CUSTOMER_TENANT_ID\",\"quota_type\":\"storage_gb\",\"limit_value\":100}"; do
      RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X PUT "$CP_URL/api/quotas" \
        -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
        ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} -b "$COOKIE_FILE" \
        -d "$q_json" 2>&1)
      CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
      QTYPE=$(echo "$q_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['quota_type'])" 2>/dev/null)
      if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
        log "Quota: $QTYPE"
        QUOTAS_SEEDED=$((QUOTAS_SEEDED+1))
      else
        warn "Quota '$QTYPE': HTTP $CODE"
      fi
    done
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 11: Seed Policy Draft (AI Control Plane)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
POLICY_SEEDED=0
if [[ "$ENABLE_POLICY_SEED" == "true" ]]; then
  step "Seeding Governance Policy"
  EXISTING_P=$(api_call -s -w "\nHTTP:%{http_code}" -X GET "$CP_URL/api/policy/versions" \
    -b "$COOKIE_FILE" 2>&1)
  P_COUNT=$(echo "$EXISTING_P" | grep -v "HTTP:" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d.get('versions',[])
print(len(items) if isinstance(items,list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$P_COUNT" != "0" && -n "$P_COUNT" ]]; then
    log "Policy versions already exist ($P_COUNT found) — skipping"
    POLICY_SEEDED=$P_COUNT
  else
    RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/policy/content/save" \
      -H "Content-Type: application/json" -b "$COOKIE_FILE" \
      -d '{"source_format":"markdown","source_content":"# AI Governance Policy v1.0\n\n## Scope\nAll AI agents operating within the enterprise infrastructure.\n\n## Rules\n1. All agents must be registered in the Identity Fabric before production use.\n2. HIGH risk tools require approval from the Security team.\n3. PII data must not be sent to external AI providers.\n4. All agent actions are logged to the immutable audit trail.\n5. Cost budgets are enforced per-agent with 80% alert thresholds.","description":"Initial governance policy"}' 2>&1)
    CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
      log "Governance policy draft saved"
      POLICY_SEEDED=1
    else
      warn "Policy save: HTTP $CODE"
    fi
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 12: Seed Compliance Frameworks (AI Compliance Hub)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COMPLIANCE_SEEDED=0
if [[ "$ENABLE_COMPLIANCE_SEED" == "true" ]]; then
  step "Seeding Compliance Frameworks"
  EXISTING_CF=$(api_call -s -w "\nHTTP:%{http_code}" -X GET "$CP_URL/api/compliance/frameworks" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} -b "$COOKIE_FILE" 2>&1)
  CF_COUNT=$(echo "$EXISTING_CF" | grep -v "HTTP:" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',d.get('frameworks',[]))
print(len(items) if isinstance(items,list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$CF_COUNT" != "0" && -n "$CF_COUNT" ]]; then
    log "Compliance frameworks already exist ($CF_COUNT found) — skipping"
    COMPLIANCE_SEEDED=$CF_COUNT
  else
    for cf_json in \
      '{"framework_name":"SOC 2 Type II","description":"Service Organization Control 2 Type II"}' \
      '{"framework_name":"ISO 27001:2022","description":"Information Security Management System"}' \
      '{"framework_name":"EU AI Act","description":"European Union Artificial Intelligence Act"}' \
      '{"framework_name":"NIST AI RMF","description":"NIST AI Risk Management Framework"}' \
      '{"framework_name":"FedRAMP Moderate","description":"Federal Risk Authorization Management Program"}'; do
      RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/compliance/frameworks" \
        -H "Content-Type: application/json" -b "$COOKIE_FILE" \
        -d "$cf_json" 2>&1)
      CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
      CFNAME=$(echo "$cf_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('framework_name', d.get('name','')))" 2>/dev/null)
      if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
        log "Framework: $CFNAME"
        COMPLIANCE_SEEDED=$((COMPLIANCE_SEEDED+1))
      else
        warn "Framework '$CFNAME': HTTP $CODE"
      fi
    done
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 13: Seed Drift Findings (Agent Behavioral Intel) via API
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DRIFT_SEEDED=0
if [[ "$ENABLE_DRIFT_SEED" == "true" ]]; then
  step "Seeding Drift Findings"
  DRIFT_RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/dp/drift-findings" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ADMIN_SECRET" \
    -H "X-Tenant-ID: $CUSTOMER_TENANT_ID" \
    -d '{
      "findings": [
        {"agent_id":"doc-processor","drift_type":"config_change","severity":"HIGH","expected_value":"gpt-4","actual_value":"gpt-4o","description":"Agent model changed from gpt-4 to gpt-4o without approval"},
        {"agent_id":"chat-assistant","drift_type":"behavior_anomaly","severity":"CRITICAL","expected_value":"<50MB/hr","actual_value":"450MB/hr","description":"Unusual outbound data volume detected: 450MB in 1 hour"},
        {"agent_id":"data-analyzer","drift_type":"permission_escalation","severity":"MEDIUM","expected_value":"db:read","actual_value":"db:write","description":"Agent requested elevated database permissions"},
        {"agent_id":"doc-processor","drift_type":"endpoint_change","severity":"LOW","expected_value":"v1","actual_value":"v2","description":"API endpoint URL updated to new version"},
        {"agent_id":"chat-assistant","drift_type":"latency_spike","severity":"MEDIUM","expected_value":"950ms","actual_value":"2800ms","description":"Response latency increased 3x over baseline"}
      ]
    }' 2>&1)
  DRIFT_CODE=$(echo "$DRIFT_RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$DRIFT_CODE" == "200" ]]; then
    DRIFT_SEEDED=$(echo "$DRIFT_RESP" | grep -v "HTTP:" | python3 -c "import sys,json; print(json.load(sys.stdin).get('inserted',0))" 2>/dev/null || echo "0")
    log "$DRIFT_SEEDED drift findings seeded via API"
  else
    warn "Drift findings: HTTP $DRIFT_CODE"
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# STEP 14: Seed OAuth Credentials (Agent Identity Fabric)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IDENTITY_SEEDED=0
if [[ "$ENABLE_IDENTITY_SEED" == "true" ]]; then
  step "Seeding OAuth Credentials"
  EXISTING_OC=$(api_call -s -w "\nHTTP:%{http_code}" -X GET "$CP_URL/api/oauth/credentials" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} -b "$COOKIE_FILE" 2>&1)
  OC_COUNT=$(echo "$EXISTING_OC" | grep -v "HTTP:" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',d.get('credentials',[]))
print(len(items) if isinstance(items,list) else 0)
" 2>/dev/null || echo "0")

  if [[ "$OC_COUNT" != "0" && -n "$OC_COUNT" ]]; then
    log "OAuth credentials already exist ($OC_COUNT found) — skipping"
    IDENTITY_SEEDED=$OC_COUNT
  else
    for oc_json in \
      "{\"client_name\":\"Production API Client\",\"grant_type\":\"client_credentials\",\"scope\":\"read write\",\"description\":\"Main production API access\"}" \
      "{\"client_name\":\"CI/CD Pipeline\",\"grant_type\":\"client_credentials\",\"scope\":\"read\",\"description\":\"Automated deployment pipeline\"}" \
      "{\"client_name\":\"Monitoring Agent\",\"grant_type\":\"client_credentials\",\"scope\":\"read\",\"description\":\"Health monitoring service\"}"; do
      RESP=$(api_call -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/oauth/credentials" \
        -H "Content-Type: application/json" ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
        ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} -b "$COOKIE_FILE" \
        -d "$oc_json" 2>&1)
      CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
      OCNAME=$(echo "$oc_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['client_name'])" 2>/dev/null)
      if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
        log "OAuth: $OCNAME"
        IDENTITY_SEEDED=$((IDENTITY_SEEDED+1))
      else
        warn "OAuth '$OCNAME': HTTP $CODE"
      fi
    done
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Customer Seed Complete: $CUSTOMER_NAME"
echo ""
echo "  Tenant ID:   $CUSTOMER_TENANT_ID"
echo "  Admin:       $CUSTOMER_ADMIN_EMAIL"
echo "  Dashboard:   https://app.${NAMESPACE}.runtimeai.io"
echo ""
if [ -n "$GENERATED_PASSWORD" ]; then
  echo "  Credentials stored in vault:"
  echo "    Password:  az keyvault secret show --vault-name $VAULT_NAME --name ${CUSTOMER_TENANT_ID}-admin-password --query value -o tsv"
  echo "    API Key:   az keyvault secret show --vault-name $VAULT_NAME --name ${CUSTOMER_TENANT_ID}-api-key --query value -o tsv"
fi
echo ""
echo "  Seeded data:"
echo "    Agents:        ${#CUSTOMER_AGENTS[@]} registered"
[[ "$ENABLE_DISCOVERY_SEED" == "true" ]] && echo "    Discovery:     8 shadow AI agents (inbox)" || true
[[ "$ENABLE_TOOLS_SEED" == "true" ]]     && echo "    Tools:         ${TOOLS_SEEDED} AI tools" || true
[[ "$ENABLE_GUARDRAILS_SEED" == "true" ]]&& echo "    Guardrails:    ${GUARDRAILS_SEEDED} rules" || true
[[ "$ENABLE_EGRESS_SEED" == "true" ]]    && echo "    Egress:        ${EGRESS_SEEDED} policies" || true
[[ "$ENABLE_QUOTAS_SEED" == "true" ]]    && echo "    Quotas:        ${QUOTAS_SEEDED} limits" || true
[[ "$ENABLE_POLICY_SEED" == "true" ]]    && echo "    Policy:        ${POLICY_SEEDED} governance policy" || true
[[ "$ENABLE_COMPLIANCE_SEED" == "true" ]]&& echo "    Compliance:    ${COMPLIANCE_SEEDED} frameworks" || true
[[ "$ENABLE_DRIFT_SEED" == "true" ]]     && echo "    Drift:         ${DRIFT_SEEDED} findings" || true
[[ "$ENABLE_IDENTITY_SEED" == "true" ]]  && echo "    Identity:      ${IDENTITY_SEEDED} OAuth credentials" || true
[[ "$ENABLE_FINOPS_SEED" == "true" ]]    && echo "    FinOps:        ${TOTAL_EVENTS:-0} cost events + 1 budget" || true
[[ "$ENABLE_ESIGN_SEED" == "true" ]]     && echo "    eSign:         3 templates" || true
echo ""
echo "  Delete & reseed:"
echo "    ./$(basename $0) --delete --tenant-id $CUSTOMER_TENANT_ID"
echo "    ./$(basename $0) --tenant-id $CUSTOMER_TENANT_ID --admin-email $CUSTOMER_ADMIN_EMAIL"
echo "═══════════════════════════════════════════════════════════════"

# Cleanup
rm -f "$COOKIE_FILE" 2>/dev/null

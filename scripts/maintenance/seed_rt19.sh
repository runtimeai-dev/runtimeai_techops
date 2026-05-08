#!/bin/bash
# ============================================================================
# seed_rt19.sh — Seed Demo Data on RuntimeAI AKS Pods (API-ONLY)
#
# Pod-independent seed script for any RuntimeAI AKS environment.
# Fetches secrets from Azure Key Vault. ALL operations use APIs — no SQL.
#
# USAGE:
#   ./seed_rt19.sh                        # Seed rt19 (default)
#   ./seed_rt19.sh --namespace rt20       # Seed a different pod/namespace
#   ./seed_rt19.sh --delete               # Delete Felt Sense tenant only
#   ./seed_rt19.sh --esign-only           # Seed eSign data only
#   ./seed_rt19.sh --list-secrets         # Show all secrets in vault
#
# PREREQUISITES:
#   1. Azure CLI logged in: az login
#   2. Key Vault access:    az keyvault secret list --vault-name runtimeai-rt19-kv
#   3. kubectl configured (only for Redis flush): az aks get-credentials ...
#
# SECRETS RETRIEVAL (manual):
#   # List all secrets in vault
#   az keyvault secret list --vault-name runtimeai-rt19-kv --query "[].name" -o tsv
#
#   # Get a specific secret value
#   az keyvault secret show --vault-name runtimeai-rt19-kv --name sendgrid-api-key --query value -o tsv
#
#   # Get ALL secrets as key=value pairs
#   for s in $(az keyvault secret list --vault-name runtimeai-rt19-kv --query "[].name" -o tsv); do
#     echo "$s=$(az keyvault secret show --vault-name $VAULT_NAME --name $s --query value -o tsv)"
#   done
#
# ENVIRONMENT VARIABLES (override defaults):
#   VAULT_NAME=runtimeai-rt19-kv  # Azure Key Vault name
#   NAMESPACE=rt19                 # K8s namespace
#   CP_URL=https://api.rt19.runtimeai.io  # Control-plane URL
#   ESIGN_URL=https://esign.rt19.runtimeai.io  # eSign URL
#   ADMIN_SECRET=xxx               # Override vault fetch (for tests)
# ============================================================================
set -eo pipefail

# ─── Configuration (pod-independent — override via env vars) ─────
VAULT_NAME="${VAULT_NAME:-runtimeai-rt19-kv}"
NAMESPACE="${NAMESPACE:-rt19}"
TENANT_ID="felt-sense-ai"
TENANT_NAME="Felt Sense AI"
ADMIN_EMAIL="admin@felt-sense-ai.ai"
ADMIN_PASS="password123"
CP_URL="${CP_URL:-https://api.${NAMESPACE}.runtimeai.io}"
ESIGN_URL="${ESIGN_URL:-https://esign.${NAMESPACE}.runtimeai.io}"
# FinOps is a backend service — access via Control Plane proxy
# DO NOT use a public URL; the CP proxies at /api/v1/finops/*
FINOPS_URL="${FINOPS_URL:-$CP_URL}"
COOKIE_FILE="/tmp/${NAMESPACE}_seed_cookies.txt"

# ─── Colors ──────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
log()  { echo -e "${GREEN}  ✅ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
fail() { echo -e "${RED}  ❌ $1${NC}"; }
step() { echo -e "\n${CYAN}── $1 ──${NC}"; }

# ─── Parse Args ──────────────────────────────────────────
MODE="full"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete)       MODE="delete"; shift ;;
    --esign-only)   MODE="esign"; shift ;;
    --list-secrets) MODE="list-secrets"; shift ;;
    --namespace)    NAMESPACE="$2"; CP_URL="https://api.${NAMESPACE}.runtimeai.io"; ESIGN_URL="https://esign.${NAMESPACE}.runtimeai.io"; shift 2 ;;
    --vault)        VAULT_NAME="$2"; shift 2 ;;
    --cp-url)       CP_URL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo ""
echo "═══════════════════════════════════════════════════"
echo "  RuntimeAI Seed Script"
echo "  Namespace: $NAMESPACE"
echo "  Vault:     $VAULT_NAME"
echo "  API:       $CP_URL"
echo "═══════════════════════════════════════════════════"

# ─── List Secrets Mode ───────────────────────────────────
if [[ "$MODE" == "list-secrets" ]]; then
  step "Secrets in $VAULT_NAME"
  az keyvault secret list --vault-name "$VAULT_NAME" --query "[].{Name:name, Updated:attributes.updated}" -o table 2>&1
  echo ""
  echo "To retrieve a secret value:"
  echo "  az keyvault secret show --vault-name $VAULT_NAME --name <secret-name> --query value -o tsv"
  exit 0
fi

# ─── Fetch Secrets from Azure Key Vault ──────────────────
step "Fetching secrets from Azure Key Vault ($VAULT_NAME)"
if [ -z "${ADMIN_SECRET:-}" ]; then
  ADMIN_SECRET=$(az keyvault secret show --vault-name "$VAULT_NAME" --name admin-secret --query value -o tsv 2>/dev/null || echo "")
  if [ -z "$ADMIN_SECRET" ]; then
    warn "Vault fetch failed. Falling back to K8s secret."
    ADMIN_SECRET=$(kubectl get secret rt19-app-secrets -n "$NAMESPACE" -o jsonpath='{.data.ADMIN_SECRET}' | base64 -d 2>/dev/null || echo "")
  fi
  if [ -z "$ADMIN_SECRET" ]; then
    fail "Could not retrieve admin secret from vault or K8s. Set ADMIN_SECRET env var."
    exit 1
  fi
fi
log "Admin secret loaded"

# ─── Cleanup (API-only — no SQL) ─────────────────────────
cleanup_tenant() {
  step "Cleaning up existing Felt Sense data in $NAMESPACE (via API)"
  RESP=$(curl -s -w "\n%{http_code}" -X DELETE "$CP_URL/api/admin/tenants/$TENANT_ID" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" 2>&1)
  HTTP_CODE=$(echo "$RESP" | tail -1)
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    log "Tenant $TENANT_ID deleted via API"
  elif [[ "$HTTP_CODE" == "404" ]]; then
    log "Tenant $TENANT_ID not found (already clean)"
  else
    warn "Tenant delete returned HTTP $HTTP_CODE: $(echo "$RESP" | head -n -1)"
  fi
  log "Cleanup complete"
}

# ─── Create Tenant ───────────────────────────────────────
GENERATED_PASSWORD=""
TENANT_API_KEY=""
TENANT_ID_HEADER=""
AUTH_HEADER=""

create_tenant() {
  step "Creating Felt Sense AI Tenant"
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$CP_URL/api/admin/tenants" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    -d "{
      \"tenant_id\": \"$TENANT_ID\",
      \"name\": \"$TENANT_NAME\",
      \"domain\": \"felt-sense-ai.ai\",
      \"admin_email\": \"$ADMIN_EMAIL\"
    }" 2>&1)
  HTTP_CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    # Capture the generated password and API key from response
    GENERATED_PASSWORD=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('password',''))" 2>/dev/null || echo "")
    TENANT_API_KEY=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_key',''))" 2>/dev/null || echo "")
    log "Tenant created: $TENANT_ID"

    # ── Store credentials in Azure Key Vault for later retrieval ──
    if [ -n "$GENERATED_PASSWORD" ]; then
      log "Generated password captured (length: ${#GENERATED_PASSWORD})"
      if az keyvault secret set --vault-name "$VAULT_NAME" \
           --name "felt-sense-admin-password" \
           --value "$GENERATED_PASSWORD" \
           --content-type "Generated admin password for $ADMIN_EMAIL" \
           > /dev/null 2>&1; then
        log "Password stored in vault: $VAULT_NAME/felt-sense-admin-password"
      else
        warn "Failed to store password in vault — save manually: ${GENERATED_PASSWORD}"
      fi
    fi
    if [ -n "$TENANT_API_KEY" ]; then
      log "API key captured: ${TENANT_API_KEY:0:12}..."
      if az keyvault secret set --vault-name "$VAULT_NAME" \
           --name "felt-sense-api-key" \
           --value "$TENANT_API_KEY" \
           --content-type "API key for tenant $TENANT_ID" \
           > /dev/null 2>&1; then
        log "API key stored in vault: $VAULT_NAME/felt-sense-api-key"
      else
        warn "Failed to store API key in vault"
      fi
    fi
  elif echo "$BODY" | grep -qi "already exists"; then
    warn "Tenant already exists, continuing..."
  else
    fail "Tenant creation failed (HTTP $HTTP_CODE): $BODY"
    return 1
  fi
}

# ─── Login ───────────────────────────────────────────────
login() {
  step "Authenticating as $ADMIN_EMAIL → $CP_URL"

  # Flush Redis rate limits from any previous failed attempts
  kubectl exec deploy/redis -n "$NAMESPACE" -- redis-cli KEYS "login_*" 2>/dev/null | \
    xargs -r kubectl exec deploy/redis -n "$NAMESPACE" -- redis-cli DEL 2>/dev/null || true

  # ── Retrieve credentials from vault if not already set ──
  if [ -z "$GENERATED_PASSWORD" ]; then
    GENERATED_PASSWORD=$(az keyvault secret show --vault-name "$VAULT_NAME" \
      --name "felt-sense-admin-password" --query value -o tsv 2>/dev/null || echo "")
    if [ -n "$GENERATED_PASSWORD" ]; then
      log "Admin password retrieved from vault"
    fi
  fi
  if [ -z "$TENANT_API_KEY" ]; then
    TENANT_API_KEY=$(az keyvault secret show --vault-name "$VAULT_NAME" \
      --name "felt-sense-api-key" --query value -o tsv 2>/dev/null || echo "")
    if [ -n "$TENANT_API_KEY" ]; then
      log "API key retrieved from vault"
    fi
  fi

  # Build ordered list of passwords to try: vault password first, then hardcoded fallback
  local PASSWORDS_TO_TRY=()
  if [ -n "$GENERATED_PASSWORD" ]; then
    PASSWORDS_TO_TRY+=("$GENERATED_PASSWORD")
  fi
  PASSWORDS_TO_TRY+=("$ADMIN_PASS")

  # Try each password in order
  for LOGIN_PASS in "${PASSWORDS_TO_TRY[@]}"; do
    RESP=$(curl -s -w "\n%{http_code}" -X POST "$CP_URL/api/auth/login" \
      -H "Content-Type: application/json" \
      -c "$COOKIE_FILE" \
      -d "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$LOGIN_PASS\"}" 2>&1)
    HTTP_CODE=$(echo "$RESP" | tail -1)
    BODY=$(echo "$RESP" | sed '$d')
    local HAS_SESSION=$(grep -c "runtimeai_session" "$COOKIE_FILE" 2>/dev/null || echo "0")

    if [[ "$HTTP_CODE" == "200" ]] && [[ "$HAS_SESSION" -gt 0 ]]; then
      AUTH_HEADER="Cookie: $(grep runtimeai_session "$COOKIE_FILE" | awk '{print $NF"="$7}')"
      log "Logged in via session cookie"
      return 0
    fi
    warn "Password attempt failed (HTTP $HTTP_CODE), trying next..."
  done

  # Fallback: Use API key with X-Tenant-ID header if password login fails
  if [ -n "$TENANT_API_KEY" ]; then
    warn "Session login failed, using API key auth..."
    AUTH_HEADER="X-API-Key: $TENANT_API_KEY"
    TENANT_ID_HEADER="X-Tenant-ID: $TENANT_ID"
    log "Using API key auth for $TENANT_ID"
    return 0
  fi

  fail "All authentication methods failed (HTTP $HTTP_CODE): $BODY"
  return 1
}

# ─── Seed Agents ─────────────────────────────────────────
seed_agents() {
  step "Seeding AI Agents"
  local agents=(
    '{"name":"Contract Analyzer","type":"llm","vendor":"openai","model":"gpt-4o","status":"active","risk_level":"high","description":"Analyzes legal contracts for risk and compliance"}'
    '{"name":"HR Onboarding Bot","type":"llm","vendor":"anthropic","model":"claude-3.5-sonnet","status":"active","risk_level":"medium","description":"Automates employee onboarding workflows"}'
    '{"name":"Financial Forecaster","type":"llm","vendor":"openai","model":"gpt-4-turbo","status":"active","risk_level":"critical","description":"Predicts revenue and expense trends"}'
    '{"name":"Customer Support Agent","type":"llm","vendor":"google","model":"gemini-pro","status":"active","risk_level":"low","description":"Handles tier-1 customer inquiries"}'
    '{"name":"Code Security Scanner","type":"llm","vendor":"anthropic","model":"claude-3-opus","status":"paused","risk_level":"high","description":"Scans code repos for security vulnerabilities"}'
  )
  for agent_json in "${agents[@]}"; do
    local name=$(echo "$agent_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    curl -s -X POST "$CP_URL/api/agents" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -d "$agent_json" > /dev/null 2>&1
    log "Agent: $name"
  done
}

# ─── Seed eSign Documents ────────────────────────────────
seed_esign() {
  step "Seeding eSign Documents"

  # Create a minimal PDF for seeding (valid PDF structure)
  SEED_PDF="/tmp/${NAMESPACE}_seed_doc.pdf"
  cat > "$SEED_PDF" << 'SEEDPDF'
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj
xref
0 4
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
trailer<</Size 4/Root 1 0 R>>
startxref
206
%%EOF
SEEDPDF

  ESIGN_PROXY="$CP_URL/api/proxy/esign/api/v1/sign"

  # Create NDA and send for signing (triggers email via SendGrid)
  NDA_RESP=$(curl -s -X POST "$ESIGN_PROXY/documents" \
    -H "$AUTH_HEADER" \
    ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
    -b "$COOKIE_FILE" \
    -F "title=Mutual NDA - RuntimeAI x Felt Sense" \
    -F "description=Non-disclosure agreement for AI governance partnership" \
    -F "document_type=nda" \
    -F "file=@$SEED_PDF;filename=mutual_nda.pdf" 2>&1)
  NDA_ID=$(echo "$NDA_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('document',{}).get('document_id', d.get('document_id', d.get('id',''))))" 2>/dev/null || echo "")

  if [ -n "$NDA_ID" ] && [ "$NDA_ID" != "None" ] && [ "$NDA_ID" != "" ]; then
    log "NDA created: $NDA_ID"

    # Add signer (eSign expects {"signers":[...]} array format with signing_order)
    SIGNER_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$ESIGN_PROXY/documents/$NDA_ID/signers" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -d '[{"name":"Roshan Shaik","email":"roshanshaik+signer1@gmail.com","role":"signer","signing_order":1}]' 2>&1)
    SIGNER_CODE=$(echo "$SIGNER_RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$SIGNER_CODE" == "201" ]]; then
      log "Signer added: roshanshaik+signer1@gmail.com"
    else
      warn "Signer add failed (HTTP $SIGNER_CODE): $(echo "$SIGNER_RESP" | head -n -1)"
    fi

    # Send for signing → triggers SendGrid email
    SEND_RESP=$(curl -s -w "\n%{http_code}" -X POST "$ESIGN_PROXY/documents/$NDA_ID/send" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" 2>&1)
    SEND_CODE=$(echo "$SEND_RESP" | tail -1)
    if [[ "$SEND_CODE" == "200" ]]; then
      log "📧 Document sent for signing! Check roshanshaik+signer1@gmail.com"
    else
      warn "Send returned HTTP $SEND_CODE: $(echo "$SEND_RESP" | head -n -1)"
    fi
  else
    warn "NDA creation response: $NDA_RESP"
  fi

  # Additional documents
  for doc_title in \
    "AI Vendor Agreement - Felt Sense" \
    "SOW-2026-001 AI Governance Implementation" \
    "Board Resolution - AI Policy"; do
    DOC_RESP=$(curl -s -X POST "$ESIGN_PROXY/documents" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -F "title=$doc_title" \
      -F "description=Seeded document for Felt Sense AI demo" \
      -F "document_type=agreement" \
      -F "file=@$SEED_PDF;filename=$(echo "$doc_title" | tr ' ' '_' | tr '[:upper:]' '[:lower:]').pdf" 2>&1)
    DOC_ID=$(echo "$DOC_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('document',{}).get('document_id', d.get('document_id', d.get('id',''))))" 2>/dev/null || echo "")
    if [ -n "$DOC_ID" ] && [ "$DOC_ID" != "None" ] && [ "$DOC_ID" != "" ]; then
      log "Document: $doc_title (ID: ${DOC_ID:0:12}...)"
    else
      warn "Document '$doc_title': $DOC_RESP"
    fi
  done

  # ── Seed Templates ──
  step "Seeding eSign Templates"
  for tpl_data in \
    '{"template_name":"Non-Disclosure Agreement (NDA)","description":"Standard mutual NDA for business partnerships and vendor engagements","category":"legal","shared_with":"tenant"}' \
    '{"template_name":"Employee Offer Letter","description":"Standard offer letter with compensation details, equity, and start date","category":"hr","shared_with":"tenant"}' \
    '{"template_name":"Vendor Service Agreement","description":"Master services agreement for external vendor partnerships and SLAs","category":"procurement","shared_with":"tenant"}' \
    '{"template_name":"Statement of Work (SOW)","description":"Project scope, deliverables, timeline, and payment milestones","category":"projects","shared_with":"tenant"}' \
    '{"template_name":"Board Resolution","description":"Corporate board resolution for major business decisions and approvals","category":"governance","shared_with":"tenant"}'; do
    NAME=$(echo "$tpl_data" | python3 -c "import json,sys; print(json.load(sys.stdin)['template_name'])")
    TPL_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$ESIGN_PROXY/templates" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -H "Content-Type: application/json" \
      -d "$tpl_data" 2>&1)
    TPL_CODE=$(echo "$TPL_RESP" | tail -1 | sed 's/HTTP://')
    if [[ "$TPL_CODE" == "201" ]]; then
      log "Template: $NAME"
    elif [[ "$TPL_CODE" == "409" ]]; then
      log "Template: $NAME (already exists)"
    else
      warn "Template '$NAME': HTTP $TPL_CODE"
    fi
  done

  # ── Seed Contacts ──
  step "Seeding eSign Contacts"
  for contact_data in \
    '{"name":"Sarah Chen","email":"sarah.chen@felt-sense.ai","company":"Felt Sense AI","title":"VP Engineering","phone":"+1-415-555-0101"}' \
    '{"name":"Michael Rodriguez","email":"michael.r@techpartners.io","company":"TechPartners Inc","title":"CEO","phone":"+1-212-555-0202"}' \
    '{"name":"Emily Johnson","email":"emily.j@globalventures.com","company":"Global Ventures","title":"General Counsel","phone":"+1-312-555-0303"}' \
    '{"name":"David Kim","email":"david.kim@acmecorp.net","company":"ACME Corporation","title":"VP Operations","phone":"+1-650-555-0404"}' \
    '{"name":"Lisa Park","email":"lisa.park@innovatetech.co","company":"InnovateTech","title":"CFO","phone":"+1-206-555-0505"}'; do
    CNAME=$(echo "$contact_data" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    CT_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$ESIGN_PROXY/contacts" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -H "Content-Type: application/json" \
      -d "$contact_data" 2>&1)
    CT_CODE=$(echo "$CT_RESP" | tail -1 | sed 's/HTTP://')
    if [[ "$CT_CODE" == "201" ]]; then
      log "Contact: $CNAME"
    elif [[ "$CT_CODE" == "409" ]]; then
      log "Contact: $CNAME (already exists)"
    else
      warn "Contact '$CNAME': HTTP $CT_CODE"
    fi
  done

  rm -f "$SEED_PDF" 2>/dev/null
}

# ─── Seed Discovered Agents (Shadow AI Inbox) — via API ──
seed_discovered_agents() {
  step "Seeding Discovered Agents (Shadow AI Inbox) via API"

  IMPORT_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/discovery/import" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
    -b "$COOKIE_FILE" \
    -d '{
      "source": "seed-script",
      "format": "json",
      "agents": [
        {"name": "ChatGPT Enterprise Plugin", "fingerprint": "fp-chatgpt-plugin-8a3f", "owner": "eng-team@felt-sense.ai", "status": "DISCOVERED", "capabilities": ["code-generation","text-analysis","conversation","function-calling"], "source_details": {"source": "ide-scanner", "ip": "10.0.1.42", "environment": "production"}},
        {"name": "Claude 3.5 Sonnet API", "fingerprint": "fp-claude-api-b4c2", "owner": "ml-team@felt-sense.ai", "status": "DISCOVERED", "capabilities": ["code-generation","document-analysis","reasoning","tool-use"], "source_details": {"source": "network-scanner", "ip": "10.0.2.18", "environment": "staging"}},
        {"name": "GitHub Copilot (VS Code)", "fingerprint": "fp-copilot-vsc-d7e9", "owner": "dev-team@felt-sense.ai", "status": "REGISTERED", "capabilities": ["code-completion","code-generation","inline-suggestions"], "source_details": {"source": "ide-scanner", "ip": "10.0.1.55", "environment": "development"}},
        {"name": "Gemini Advanced", "fingerprint": "fp-gemini-adv-x9k1", "owner": "research@felt-sense.ai", "status": "DISCOVERED", "capabilities": ["code-generation","multimodal","search","reasoning"], "source_details": {"source": "cloud-scanner", "ip": "10.0.3.10", "environment": "production"}},
        {"name": "Cursor AI Editor", "fingerprint": "fp-cursor-ai-m3n5", "owner": "dev-team@felt-sense.ai", "status": "DISCOVERED", "capabilities": ["code-generation","code-editing","multi-file-editing","terminal-commands"], "source_details": {"source": "ide-scanner", "ip": "10.0.1.88", "environment": "development"}},
        {"name": "Perplexity Pro", "fingerprint": "fp-perplexity-r2d4", "owner": "product@felt-sense.ai", "status": "QUARANTINED", "risk_score": 72, "capabilities": ["search","web-browsing","citation","summarization"], "source_details": {"source": "network-scanner", "ip": "10.0.4.22", "environment": "production"}},
        {"name": "LangChain Autonomous Agent", "fingerprint": "fp-langchain-agt-f5h8", "owner": "ml-team@felt-sense.ai", "status": "DISCOVERED", "capabilities": ["agent-orchestration","tool-use","chain-of-thought","autonomous-execution"], "source_details": {"source": "api-monitor", "ip": "10.0.2.77", "environment": "staging"}},
        {"name": "Custom RAG Pipeline", "fingerprint": "fp-custom-rag-j7k2", "owner": "data-team@felt-sense.ai", "status": "REGISTERED", "capabilities": ["document-retrieval","embedding","semantic-search","answer-generation"], "source_details": {"source": "cloud-scanner", "ip": "10.0.5.33", "environment": "production"}}
      ]
    }' 2>&1)
  IMPORT_CODE=$(echo "$IMPORT_RESP" | grep "HTTP:" | sed 's/HTTP://')
  IMPORT_BODY=$(echo "$IMPORT_RESP" | grep -v "HTTP:")
  IMPORTED=$(echo "$IMPORT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('imported',0))" 2>/dev/null || echo "?")
  SKIPPED=$(echo "$IMPORT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('skipped',0))" 2>/dev/null || echo "?")
  if [[ "$IMPORT_CODE" == "200" ]]; then
    log "$IMPORTED discovered agents imported, $SKIPPED skipped (Shadow AI Inbox)"
  else
    warn "Discovery import returned HTTP $IMPORT_CODE: $IMPORT_BODY"
  fi
}

# ─── Seed FinOps Cost Data (via CP proxy → ai-finops-service) ───
seed_finops_costs() {
  step "Seeding FinOps Cost Events via CP proxy ($CP_URL)"

  # FinOps is an internal backend service — always route through CP proxy
  FINOPS_API_URL="$CP_URL"

  # Batch ingest 28 cost events via POST /api/v1/finops/events/batch
  BATCH_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$FINOPS_API_URL/api/v1/finops/events/batch" \
    -H "Content-Type: application/json" \
    -H "X-Tenant-ID: $TENANT_ID" \
    -d '{
      "events": [
        {"agent_id":"contract-analyzer","provider":"openai","model":"gpt-4o","input_tokens":12500,"output_tokens":3200,"total_tokens":15700,"total_cost_usd":0.48,"latency_ms":1200,"feature_tag":"contract-review","team_id":"legal"},
        {"agent_id":"contract-analyzer","provider":"openai","model":"gpt-4o","input_tokens":18900,"output_tokens":4100,"total_tokens":23000,"total_cost_usd":0.72,"latency_ms":1850,"feature_tag":"contract-review","team_id":"legal"},
        {"agent_id":"contract-analyzer","provider":"openai","model":"gpt-4o","input_tokens":9800,"output_tokens":2800,"total_tokens":12600,"total_cost_usd":0.38,"latency_ms":950,"feature_tag":"risk-analysis","team_id":"legal"},
        {"agent_id":"contract-analyzer","provider":"openai","model":"gpt-4o","input_tokens":22000,"output_tokens":5500,"total_tokens":27500,"total_cost_usd":0.88,"latency_ms":2100,"feature_tag":"contract-review","team_id":"legal"},
        {"agent_id":"contract-analyzer","provider":"openai","model":"gpt-4o","input_tokens":15000,"output_tokens":3800,"total_tokens":18800,"total_cost_usd":0.58,"latency_ms":1400,"feature_tag":"compliance-check","team_id":"legal"},
        {"agent_id":"contract-analyzer","provider":"openai","model":"gpt-4o","input_tokens":31000,"output_tokens":8200,"total_tokens":39200,"total_cost_usd":1.24,"latency_ms":3200,"feature_tag":"contract-review","team_id":"legal"},
        {"agent_id":"contract-analyzer","provider":"openai","model":"gpt-4o","input_tokens":28500,"output_tokens":7100,"total_tokens":35600,"total_cost_usd":1.12,"latency_ms":2800,"feature_tag":"risk-analysis","team_id":"legal"},
        {"agent_id":"hr-onboarding-bot","provider":"anthropic","model":"claude-3.5-sonnet","input_tokens":8200,"output_tokens":2100,"total_tokens":10300,"total_cost_usd":0.31,"latency_ms":800,"feature_tag":"onboarding","team_id":"hr"},
        {"agent_id":"hr-onboarding-bot","provider":"anthropic","model":"claude-3.5-sonnet","input_tokens":11500,"output_tokens":3200,"total_tokens":14700,"total_cost_usd":0.44,"latency_ms":1100,"feature_tag":"onboarding","team_id":"hr"},
        {"agent_id":"hr-onboarding-bot","provider":"anthropic","model":"claude-3.5-sonnet","input_tokens":9800,"output_tokens":2600,"total_tokens":12400,"total_cost_usd":0.37,"latency_ms":900,"feature_tag":"benefits-inquiry","team_id":"hr"},
        {"agent_id":"hr-onboarding-bot","provider":"anthropic","model":"claude-3.5-sonnet","input_tokens":14200,"output_tokens":3900,"total_tokens":18100,"total_cost_usd":0.55,"latency_ms":1350,"feature_tag":"onboarding","team_id":"hr"},
        {"agent_id":"hr-onboarding-bot","provider":"anthropic","model":"claude-3.5-sonnet","input_tokens":19800,"output_tokens":5100,"total_tokens":24900,"total_cost_usd":0.76,"latency_ms":1900,"feature_tag":"policy-qa","team_id":"hr"},
        {"agent_id":"financial-forecaster","provider":"openai","model":"gpt-4-turbo","input_tokens":45000,"output_tokens":12000,"total_tokens":57000,"total_cost_usd":2.28,"latency_ms":4500,"feature_tag":"revenue-forecast","team_id":"finance"},
        {"agent_id":"financial-forecaster","provider":"openai","model":"gpt-4-turbo","input_tokens":52000,"output_tokens":14500,"total_tokens":66500,"total_cost_usd":2.66,"latency_ms":5200,"feature_tag":"expense-analysis","team_id":"finance"},
        {"agent_id":"financial-forecaster","provider":"openai","model":"gpt-4-turbo","input_tokens":38000,"output_tokens":9800,"total_tokens":47800,"total_cost_usd":1.91,"latency_ms":3800,"feature_tag":"revenue-forecast","team_id":"finance"},
        {"agent_id":"financial-forecaster","provider":"openai","model":"gpt-4-turbo","input_tokens":61000,"output_tokens":16200,"total_tokens":77200,"total_cost_usd":3.09,"latency_ms":6100,"feature_tag":"budget-planning","team_id":"finance"},
        {"agent_id":"financial-forecaster","provider":"openai","model":"gpt-4-turbo","input_tokens":47000,"output_tokens":11800,"total_tokens":58800,"total_cost_usd":2.35,"latency_ms":4700,"feature_tag":"revenue-forecast","team_id":"finance"},
        {"agent_id":"financial-forecaster","provider":"openai","model":"gpt-4-turbo","input_tokens":55000,"output_tokens":13500,"total_tokens":68500,"total_cost_usd":2.74,"latency_ms":5500,"feature_tag":"expense-analysis","team_id":"finance"},
        {"agent_id":"customer-support-agent","provider":"google","model":"gemini-pro","input_tokens":6500,"output_tokens":1800,"total_tokens":8300,"total_cost_usd":0.12,"latency_ms":400,"feature_tag":"ticket-triage","team_id":"support"},
        {"agent_id":"customer-support-agent","provider":"google","model":"gemini-pro","input_tokens":7200,"output_tokens":2100,"total_tokens":9300,"total_cost_usd":0.14,"latency_ms":450,"feature_tag":"auto-response","team_id":"support"},
        {"agent_id":"customer-support-agent","provider":"google","model":"gemini-pro","input_tokens":5800,"output_tokens":1600,"total_tokens":7400,"total_cost_usd":0.11,"latency_ms":350,"feature_tag":"ticket-triage","team_id":"support"},
        {"agent_id":"customer-support-agent","provider":"google","model":"gemini-pro","input_tokens":8900,"output_tokens":2400,"total_tokens":11300,"total_cost_usd":0.17,"latency_ms":500,"feature_tag":"sentiment-analysis","team_id":"support"},
        {"agent_id":"customer-support-agent","provider":"google","model":"gemini-pro","input_tokens":12000,"output_tokens":3200,"total_tokens":15200,"total_cost_usd":0.23,"latency_ms":650,"feature_tag":"auto-response","team_id":"support"},
        {"agent_id":"code-security-scanner","provider":"anthropic","model":"claude-3-opus","input_tokens":35000,"output_tokens":8800,"total_tokens":43800,"total_cost_usd":2.19,"latency_ms":5500,"feature_tag":"vuln-scan","team_id":"security"},
        {"agent_id":"code-security-scanner","provider":"anthropic","model":"claude-3-opus","input_tokens":42000,"output_tokens":10500,"total_tokens":52500,"total_cost_usd":2.63,"latency_ms":6800,"feature_tag":"dependency-audit","team_id":"security"},
        {"agent_id":"code-security-scanner","provider":"anthropic","model":"claude-3-opus","input_tokens":29000,"output_tokens":7200,"total_tokens":36200,"total_cost_usd":1.81,"latency_ms":4500,"feature_tag":"vuln-scan","team_id":"security"},
        {"agent_id":"code-security-scanner","provider":"anthropic","model":"claude-3-opus","input_tokens":38000,"output_tokens":9500,"total_tokens":47500,"total_cost_usd":2.38,"latency_ms":6000,"feature_tag":"code-review","team_id":"security"},
        {"agent_id":"code-security-scanner","provider":"anthropic","model":"claude-3-opus","input_tokens":51000,"output_tokens":12800,"total_tokens":63800,"total_cost_usd":3.19,"latency_ms":8200,"feature_tag":"vuln-scan","team_id":"security"}
      ]
    }' 2>&1)
  BATCH_CODE=$(echo "$BATCH_RESP" | grep "HTTP:" | sed 's/HTTP://')
  if [[ "$BATCH_CODE" == "201" ]]; then
    INSERTED=$(echo "$BATCH_RESP" | grep -v "HTTP:" | python3 -c "import sys,json; print(json.load(sys.stdin).get('inserted',0))" 2>/dev/null || echo "28")
    log "$INSERTED cost events ingested via FinOps API"
  else
    warn "FinOps batch ingest returned HTTP $BATCH_CODE: $(echo "$BATCH_RESP" | head -n -1)"
  fi

  # Seed budget policies via POST /api/v1/finops/budgets
  step "Seeding FinOps Budgets via API"
  for budget_json in \
    '{"scope":"agent","scope_id":"contract-analyzer","budget_usd":5000.00,"period":"monthly","alert_threshold_pct":80}' \
    '{"scope":"agent","scope_id":"code-security-scanner","budget_usd":3000.00,"period":"monthly","alert_threshold_pct":75}' \
    '{"scope":"agent","scope_id":"customer-support-agent","budget_usd":1000.00,"period":"monthly","alert_threshold_pct":90}' \
    '{"scope":"tenant","scope_id":"felt-sense-ai","budget_usd":10000.00,"period":"monthly","alert_threshold_pct":85}'; do
    B_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$FINOPS_API_URL/api/v1/finops/budgets" \
      -H "Content-Type: application/json" \
      -H "X-Tenant-ID: $TENANT_ID" \
      -d "$budget_json" 2>&1)
    B_CODE=$(echo "$B_RESP" | grep "HTTP:" | sed 's/HTTP://')
    B_SCOPE=$(echo "$budget_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['scope_id'])")
    if [[ "$B_CODE" == "201" ]]; then
      log "Budget: $B_SCOPE"
    else
      warn "Budget '$B_SCOPE': HTTP $B_CODE"
    fi
  done

  log "28 cost events + 4 budgets seeded (FinOps — API only)"
}

# ─── Seed IdP Connectors (OPER_RT19-031 TASK-07) ─────────
seed_idp_connectors() {
  step "Seeding IdP Connectors via API"
  local IDP_COUNT=0
  for idp_data in \
    '{"provider":"okta","display_name":"Felt Sense Okta SSO","vault_secret_path":"runtimeai/idp/felt-sense/okta","config":{"domain":"dev-feltsense.okta.com","scopes":["openid","profile","email"]},"scan_interval":"6 hours"}' \
    '{"provider":"azuread","display_name":"Felt Sense Azure AD","vault_secret_path":"runtimeai/idp/felt-sense/azuread","config":{"tenant_id":"fs-azure-tenant-001","graph_scopes":["Application.Read.All"]},"scan_interval":"6 hours"}' \
    '{"provider":"google","display_name":"Felt Sense Google Workspace","vault_secret_path":"runtimeai/idp/felt-sense/google","config":{"domain":"felt-sense-ai.ai","admin_email":"admin@felt-sense-ai.ai"},"scan_interval":"12 hours"}' \
    '{"provider":"aws","display_name":"Felt Sense AWS IAM Identity Center","vault_secret_path":"runtimeai/idp/felt-sense/aws","config":{"region":"us-east-1"},"scan_interval":"6 hours"}' \
    '{"provider":"oci","display_name":"Felt Sense Oracle OCI IAM","vault_secret_path":"runtimeai/idp/felt-sense/oci","config":{"region":"us-ashburn-1"},"scan_interval":"24 hours"}' \
    '{"provider":"mcp","display_name":"Felt Sense Custom IdP (via MCP)","vault_secret_path":"runtimeai/idp/felt-sense/mcp","config":{"gateway_url":"http://mcp-gateway:8098","tool_name":"idp_scan"},"scan_interval":"12 hours"}'; do
    local NAME=$(echo "$idp_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['display_name'])")
    RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/discovery/idp-connectors" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -d "$idp_data" 2>&1)
    CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$CODE" == "201" ]]; then
      log "IdP Connector: $NAME"
      IDP_COUNT=$((IDP_COUNT + 1))
    else
      warn "IdP '$NAME': HTTP $CODE"
    fi
  done
  log "$IDP_COUNT IdP connectors seeded (okta, azuread, google, aws, oci, mcp)"
}

# ─── Seed GitHub App Installations (OPER_RT19-031 TASK-14) ──
seed_github_installations() {
  step "Seeding GitHub App Installations via API"
  local GH_COUNT=0
  for gh_data in \
    '{"installation_id":100001,"app_id":12345,"org_name":"feltsense-ai","account_type":"Organization","permissions":{"contents":"read","metadata":"read","members":"read"},"status":"active"}' \
    '{"installation_id":100002,"app_id":12345,"org_name":"feltsense-ml-models","account_type":"Organization","permissions":{"contents":"read","metadata":"read"},"status":"active"}' \
    '{"installation_id":100003,"app_id":12345,"org_name":"feltsense-infrastructure","account_type":"Organization","permissions":{"contents":"read","metadata":"read","organization_administration":"read"},"status":"active"}'; do
    local ORG=$(echo "$gh_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['org_name'])")
    RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/github/installations" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" \
      ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -d "$gh_data" 2>&1)
    CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$CODE" == "201" ]]; then
      log "GitHub Installation: $ORG"
      GH_COUNT=$((GH_COUNT + 1))
    else
      warn "GitHub '$ORG': HTTP $CODE"
    fi
  done
  log "$GH_COUNT GitHub App installations seeded"
}

# ─── Seed Guardrails (IF-GRD) ────────────────────────────
seed_guardrails() {
  step "Seeding Guardrails via API"
  local GR_COUNT=0
  for gr_data in \
    '{"text":"Block PII in outbound API calls","action":"BLOCK","scope":"egress","severity":"HIGH","enabled":true}' \
    '{"text":"Require human approval for financial transactions over $10k","action":"REQUIRE_APPROVAL","scope":"agent","severity":"CRITICAL","enabled":true}' \
    '{"text":"Log all model API calls for audit trail","action":"LOG","scope":"all","severity":"LOW","enabled":true}' \
    '{"text":"Rate limit agents to 100 requests per minute","action":"THROTTLE","scope":"agent","severity":"MEDIUM","enabled":true}' \
    '{"text":"Block access to unapproved model endpoints","action":"BLOCK","scope":"egress","severity":"HIGH","enabled":true}'; do
    curl -s -X POST "$CP_URL/api/policy/guardrails" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$gr_data" > /dev/null 2>&1 && GR_COUNT=$((GR_COUNT + 1))
  done
  log "$GR_COUNT guardrails seeded"
}

# ─── Seed Egress Policies ────────────────────────────────
seed_egress_policies() {
  step "Seeding Egress Policies via API"
  local EP_COUNT=0
  for ep_data in \
    '{"destination":"api.openai.com","action":"ALLOW","category":"ai_provider"}' \
    '{"destination":"api.anthropic.com","action":"ALLOW","category":"ai_provider"}' \
    '{"destination":"*.googleapis.com","action":"ALLOW","category":"ai_provider"}' \
    '{"destination":"pastebin.com","action":"DENY","category":"data_exfiltration"}' \
    '{"destination":"*.darkweb.io","action":"DENY","category":"malicious"}' \
    '{"destination":"api.stripe.com","action":"ALLOW","category":"payment"}'; do
    curl -s -X POST "$CP_URL/api/policy/egress" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$ep_data" > /dev/null 2>&1 && EP_COUNT=$((EP_COUNT + 1))
  done
  log "$EP_COUNT egress policies seeded"
}

# ─── Seed Risk Scores ───────────────────────────────────
seed_risk_scores() {
  step "Seeding Risk Scores via API"
  local RS_COUNT=0
  for rs_data in \
    '{"agent_id":"contract-analyzer","risk_score":72,"risk_factors":["pii_processing","financial_data","external_api"]}' \
    '{"agent_id":"hr-onboarding-bot","risk_score":45,"risk_factors":["employee_data","internal_only"]}' \
    '{"agent_id":"financial-forecaster","risk_score":88,"risk_factors":["financial_data","model_drift","high_cost"]}' \
    '{"agent_id":"customer-support-agent","risk_score":25,"risk_factors":["customer_data","low_autonomy"]}' \
    '{"agent_id":"code-security-scanner","risk_score":55,"risk_factors":["code_access","vulnerability_data"]}'; do
    curl -s -X POST "$CP_URL/api/risk/scores" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$rs_data" > /dev/null 2>&1 && RS_COUNT=$((RS_COUNT + 1))
  done
  log "$RS_COUNT risk scores seeded"
}

# ─── Seed Compliance Frameworks ──────────────────────────
seed_compliance() {
  step "Seeding Compliance Frameworks via API"
  local CF_COUNT=0
  for cf_data in \
    '{"framework_id":"soc2-type2","name":"SOC 2 Type II","version":"2024","status":"in_progress","controls_total":120,"controls_met":95,"controls_partial":15,"controls_not_met":10}' \
    '{"framework_id":"iso27001","name":"ISO 27001:2022","version":"2022","status":"in_progress","controls_total":93,"controls_met":78,"controls_partial":10,"controls_not_met":5}' \
    '{"framework_id":"nist-ai-rmf","name":"NIST AI RMF","version":"1.0","status":"active","controls_total":72,"controls_met":58,"controls_partial":9,"controls_not_met":5}' \
    '{"framework_id":"eu-ai-act","name":"EU AI Act","version":"2024","status":"planning","controls_total":48,"controls_met":22,"controls_partial":16,"controls_not_met":10}' \
    '{"framework_id":"fedramp-moderate","name":"FedRAMP Moderate","version":"Rev5","status":"planning","controls_total":325,"controls_met":180,"controls_partial":85,"controls_not_met":60}'; do
    curl -s -X POST "$CP_URL/api/compliance/frameworks" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$cf_data" > /dev/null 2>&1 && CF_COUNT=$((CF_COUNT + 1))
  done
  log "$CF_COUNT compliance frameworks seeded"
}

# ─── Seed Access Reviews ─────────────────────────────────
seed_access_reviews() {
  step "Seeding Access Reviews via API"
  local AR_COUNT=0
  for ar_data in \
    '{"name":"Q1 2026 Agent Access Review","scope":"all_agents","reviewer_email":"admin@felt-sense-ai.ai","status":"in_progress","due_date":"2026-03-31"}' \
    '{"name":"High-Risk Agent Quarterly Review","scope":"high_risk","reviewer_email":"admin@felt-sense-ai.ai","status":"pending","due_date":"2026-04-15"}' \
    '{"name":"Financial Data Access Certification","scope":"financial_agents","reviewer_email":"admin@felt-sense-ai.ai","status":"pending","due_date":"2026-04-30"}'; do
    curl -s -X POST "$CP_URL/api/access-reviews" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$ar_data" > /dev/null 2>&1 && AR_COUNT=$((AR_COUNT + 1))
  done
  log "$AR_COUNT access review campaigns seeded"
}

# ─── Seed Lifecycle Workflows ────────────────────────────
seed_workflows() {
  step "Seeding Lifecycle Workflows via API"
  local WF_COUNT=0
  for wf_data in \
    '{"name":"Agent Onboarding","trigger":"agent.registered","steps":[{"action":"security_scan","timeout":"5m"},{"action":"risk_assessment","timeout":"10m"},{"action":"policy_check","timeout":"5m"},{"action":"approve_or_reject","timeout":"24h"}],"enabled":true}' \
    '{"name":"Drift Remediation","trigger":"drift.detected","steps":[{"action":"notify_owner","timeout":"1m"},{"action":"quarantine_if_critical","timeout":"5m"},{"action":"create_ticket","timeout":"2m"}],"enabled":true}' \
    '{"name":"Credential Rotation","trigger":"credential.expiring_soon","steps":[{"action":"notify_owner","timeout":"1m"},{"action":"rotate_credential","timeout":"1h"},{"action":"verify_rotation","timeout":"30m"}],"enabled":true}'; do
    curl -s -X POST "$CP_URL/api/workflows" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$wf_data" > /dev/null 2>&1 && WF_COUNT=$((WF_COUNT + 1))
  done
  log "$WF_COUNT lifecycle workflows seeded"
}

# ─── Seed MCP Tools ──────────────────────────────────────
seed_mcp_tools() {
  step "Seeding MCP Tools via API"
  local MT_COUNT=0
  for mt_data in \
    '{"tool_id":"github-core","uri":"mcp://github.com/core","owner":"eng-team","risk_tier":"LOW","prod_ok":true,"description":"Source code management and CI/CD","capabilities":["read","write","deploy"]}' \
    '{"tool_id":"openai-chat","uri":"mcp://api.openai.com/v1/chat","owner":"ml-team","risk_tier":"MEDIUM","prod_ok":true,"description":"OpenAI Chat Completions API","capabilities":["generate","summarize","analyze"]}' \
    '{"tool_id":"jira-tracker","uri":"mcp://jira.atlassian.com/api","owner":"pm-team","risk_tier":"LOW","prod_ok":true,"description":"Issue tracking and project management","capabilities":["read","create","update"]}' \
    '{"tool_id":"slack-notify","uri":"mcp://slack.com/api","owner":"ops-team","risk_tier":"LOW","prod_ok":true,"description":"Team notifications and alerts","capabilities":["send","read"]}' \
    '{"tool_id":"vercel-deploy","uri":"mcp://api.vercel.com/v1","owner":"eng-team","risk_tier":"MEDIUM","prod_ok":false,"description":"Frontend deployment platform","capabilities":["deploy","rollback"]}'; do
    curl -s -X POST "$CP_URL/api/tools" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$mt_data" > /dev/null 2>&1 && MT_COUNT=$((MT_COUNT + 1))
  done
  log "$MT_COUNT MCP tools seeded"
}

# ─── Seed Scanner Configs ────────────────────────────────
seed_scanner_configs() {
  step "Seeding Scanner Configs via API (POST upsert)"
  local SC_COUNT=0
  for scanner_id in aws azure gcp kubernetes github gitlab vscode cursor docker network; do
    RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$CP_URL/api/discovery/scanner-configs" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" \
      -d "{\"scanner_id\":\"$scanner_id\",\"enabled\":true,\"schedule_cron\":\"0 */6 * * *\"}" 2>&1)
    CODE=$(echo "$RESP" | grep "HTTP:" | sed 's/HTTP://')
    if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
      SC_COUNT=$((SC_COUNT + 1))
    else
      warn "Scanner config '$scanner_id': HTTP $CODE"
    fi
  done
  log "$SC_COUNT scanner configs activated"
}

# ─── Seed SoD Rules ──────────────────────────────────────
seed_sod_rules() {
  step "Seeding Separation of Duties (SoD) Rules via API"
  local SOD_COUNT=0
  for sod_data in \
    '{"name":"No Agent Self-Approval","description":"An agent cannot approve its own deployment or credential rotation","conflict_type":"self_approval","scope":"agent","severity":"CRITICAL","action":"block","enabled":true}' \
    '{"name":"Segregate Deploy and Audit","description":"Agents with deploy access cannot have audit log write access","conflict_type":"role_conflict","scope":"agent","roles_a":["deployer"],"roles_b":["auditor"],"severity":"HIGH","action":"alert","enabled":true}' \
    '{"name":"Financial Agent Dual Control","description":"Financial agents require dual approval for transactions over threshold","conflict_type":"dual_control","scope":"financial","severity":"CRITICAL","action":"require_dual_approval","enabled":true}' \
    '{"name":"Separate Code Review and Merge","description":"Code review agent and merge executor must be different agents","conflict_type":"role_conflict","scope":"development","roles_a":["code_reviewer"],"roles_b":["code_merger"],"severity":"HIGH","action":"block","enabled":true}'; do
    curl -s -X POST "$CP_URL/api/governance/sod-rules" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$sod_data" > /dev/null 2>&1 && SOD_COUNT=$((SOD_COUNT + 1))
  done
  log "$SOD_COUNT SoD rules seeded"
}

# ─── Seed Conditional Access Policies ────────────────────
seed_conditional_access() {
  step "Seeding Conditional Access Policies via API"
  local CA_COUNT=0
  for ca_data in \
    '{"name":"Block High-Risk Agents from Production","conditions":{"risk_score_above":70,"environment":"production"},"action":"block","target_type":"environment","target_id":"production"}' \
    '{"name":"Require MFA for Financial Data Access","conditions":{"data_classification":"financial","mfa_required":true},"action":"require_mfa","target_type":"resource","target_id":"financial-data"}' \
    '{"name":"Restrict After-Hours Agent Activity","conditions":{"time_range":{"after":"22:00","before":"06:00"},"timezone":"UTC"},"action":"block","target_type":"all","target_id":"*"}' \
    '{"name":"Allow Verified Agents Only in Staging","conditions":{"verification_status":"verified","environment":"staging"},"action":"allow","target_type":"environment","target_id":"staging"}' \
    '{"name":"Block Agents with Expired Credentials","conditions":{"credential_status":"expired"},"action":"block","target_type":"credential","target_id":"*"}'; do
    curl -s -X POST "$CP_URL/api/policies/conditional-access" \
      -H "Content-Type: application/json" \
      -H "$AUTH_HEADER" ${TENANT_ID_HEADER:+-H "$TENANT_ID_HEADER"} \
      -b "$COOKIE_FILE" -d "$ca_data" > /dev/null 2>&1 && CA_COUNT=$((CA_COUNT + 1))
  done
  log "$CA_COUNT conditional access policies seeded"
}

# ─── Seed Data Plane Events ─────────────────────────────
seed_data_plane_events() {
  step "Seeding Data Plane Events via API"

  # Heartbeat
  curl -s -X POST "$CP_URL/api/dp/heartbeat" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${TENANT_API_KEY:-internal}" \
    -H "X-Tenant-ID: $TENANT_ID" \
    -d '{
      "data_plane_id":"dp-feltsense-rt19-01","version":"1.2.0",
      "components":{"flow-enforcer":{"status":"healthy","version":"1.1.0","uptime_hours":720},"waf":{"status":"healthy","version":"1.0.3","rules_loaded":42},"data-proxy":{"status":"healthy","version":"1.0.1","connections":15},"discovery-scanner":{"status":"healthy","version":"0.9.0"}},
      "metrics":{"requests_per_second":145,"blocked_requests_24h":23,"active_agents":7,"egress_policies_enforced":89}
    }' > /dev/null 2>&1
  log "Data Plane heartbeat seeded"

  # Egress events
  curl -s -X POST "$CP_URL/api/dp/egress-events" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${TENANT_API_KEY:-internal}" \
    -H "X-Tenant-ID: $TENANT_ID" \
    -d '{"events":[
      {"agent_id":"contract-analyzer","destination":"api.openai.com","action":"ALLOW","reason":"policy match"},
      {"agent_id":"code-security-scanner","destination":"pastebin.com","action":"DENY","reason":"egress blocked"},
      {"agent_id":"customer-support-agent","destination":"api.stripe.com","action":"ALLOW","reason":"policy match"},
      {"agent_id":"financial-forecaster","destination":"unknown-api.darkweb.io","action":"DENY","reason":"destination not approved"}
    ]}' > /dev/null 2>&1
  log "4 egress audit events seeded"

  # WAF events
  curl -s -X POST "$CP_URL/api/dp/waf-events" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${TENANT_API_KEY:-internal}" \
    -H "X-Tenant-ID: $TENANT_ID" \
    -d '{"events":[
      {"attack_type":"sqli","source_ip":"10.0.1.55","request_uri":"/api/query?id=1 OR 1=1--","user_agent":"python-requests/2.28"},
      {"attack_type":"xss","source_ip":"10.0.1.88","request_uri":"/api/chat?msg=<script>alert(1)</script>","user_agent":"curl/8.0"},
      {"attack_type":"prompt_injection","source_ip":"10.0.1.42","request_uri":"/v1/chat/completions","user_agent":"python-httpx/0.24"}
    ]}' > /dev/null 2>&1
  log "3 WAF attack events seeded"

  # Drift findings
  curl -s -X POST "$CP_URL/api/dp/drift-findings" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${TENANT_API_KEY:-internal}" \
    -H "X-Tenant-ID: $TENANT_ID" \
    -d '{"findings":[
      {"agent_id":"contract-analyzer","drift_type":"policy_violation","severity":"HIGH","expected_value":"egress:api.openai.com ONLY","actual_value":"egress:api.openai.com,pastebin.com","description":"Agent accessing unapproved destination"},
      {"agent_id":"financial-forecaster","drift_type":"config_change","severity":"MEDIUM","expected_value":"model:gpt-4","actual_value":"model:gpt-4-turbo","description":"Agent switched model without approval"},
      {"agent_id":"code-security-scanner","drift_type":"permission_escalation","severity":"CRITICAL","expected_value":"role:read-only","actual_value":"role:admin","description":"Agent role escalated without change ticket"}
    ]}' > /dev/null 2>&1
  log "3 drift findings seeded"

  # Cost/usage data via DP API
  curl -s -X POST "$CP_URL/api/dp/cost-usage" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${TENANT_API_KEY:-internal}" \
    -H "X-Tenant-ID: $TENANT_ID" \
    -d '{"usage":[
      {"agent_id":"contract-analyzer","model":"gpt-4o","tokens":125000,"cost_usd":3.75},
      {"agent_id":"financial-forecaster","model":"gpt-4-turbo","tokens":350000,"cost_usd":7.00},
      {"agent_id":"customer-support-agent","model":"gemini-pro","tokens":80000,"cost_usd":0.48},
      {"agent_id":"hr-onboarding-bot","model":"claude-3.5-sonnet","tokens":45000,"cost_usd":1.35},
      {"agent_id":"code-security-scanner","model":"claude-3-opus","tokens":210000,"cost_usd":3.15}
    ]}' > /dev/null 2>&1
  log "5 cost usage events seeded via DP API"
}

# ─── Main ────────────────────────────────────────────────
case "$MODE" in
  delete)
    cleanup_tenant
    ;;
  esign)
    login
    seed_esign
    ;;
  full)
    cleanup_tenant
    create_tenant
    sleep 2
    login
    seed_agents
    seed_discovered_agents
    seed_guardrails
    seed_egress_policies
    seed_risk_scores
    seed_compliance
    seed_access_reviews
    seed_workflows
    seed_mcp_tools
    seed_scanner_configs
    seed_sod_rules
    seed_conditional_access
    seed_finops_costs
    seed_idp_connectors
    seed_github_installations
    seed_data_plane_events
    seed_esign

    step "Seed Complete!"
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────────────┐"
    echo "  │  Tenant:    $TENANT_ID"
    echo "  │  Login:     $ADMIN_EMAIL"
    echo "  │  API:       $CP_URL"
    echo "  │  eSign:     $ESIGN_URL"
    echo "  │  Vault:     $VAULT_NAME"
    echo "  │"
    echo "  │  Seeded Data:"
    echo "  │    Agents:              5  (registered)"
    echo "  │    Shadow AI:           8  (discovered)"
    echo "  │    Guardrails:          5"
    echo "  │    Egress Policies:     6"
    echo "  │    Risk Scores:         5"
    echo "  │    Compliance:          5  frameworks"
    echo "  │    Access Reviews:      3  campaigns"
    echo "  │    Workflows:           3  (lifecycle)"
    echo "  │    MCP Tools:           5"
    echo "  │    Scanner Configs:    10"
    echo "  │    SoD Rules:           4"
    echo "  │    CA Policies:         5"
    echo "  │    FinOps:             28  cost events + 4 budgets"
    echo "  │    IdP Connectors:      6  (okta, azuread, google, aws, oci, mcp)"
    echo "  │    GitHub Installs:     3  (feltsense-ai orgs)"
    echo "  │    Data Plane:         11  events (heartbeat, egress, WAF, drift, cost)"
    echo "  │    eSign:               4  docs + 5 templates + 5 contacts"
    echo "  │"
    echo "  │  Credentials stored in vault (not shown in plaintext):"
    echo "  │    az keyvault secret show --vault-name $VAULT_NAME --name felt-sense-admin-password --query value -o tsv"
    echo "  │    az keyvault secret show --vault-name $VAULT_NAME --name felt-sense-api-key --query value -o tsv"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    echo ""
    ;;
esac

rm -f "$COOKIE_FILE" 2>/dev/null

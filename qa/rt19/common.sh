#!/bin/bash

# ── RuntimeAI QA Common Functions ──────────────────────────────────────
# Shared across all QA test scripts.
# Supports both local (docker-compose) and Azure (rt19) environments.
# ────────────────────────────────────────────────────────────────────────

# ── Environment Detection ──────────────────────────────────────────────
# If BASE_URL contains "https://" we're running against Azure/cloud.
_is_cloud() {
    [[ "${BASE_URL:-}" == https://* ]]
}

# ── Tenant / Credential Config ─────────────────────────────────────────
TENANT_ID="${TENANT_ID:-felt-sense-ai}"
TEST_EMAIL="${TEST_EMAIL:-admin@felt-sense-ai.ai}"
TEST_PASS="${TEST_PASS:-password123}"
TEST_TENANT="${TENANT_ID}"

# QA Tenant (for MSFT features)
QA_TENANT_ID="${QA_TENANT_ID:-acme-qa-org}"
QA_ADMIN_EMAIL="${QA_ADMIN_EMAIL:-a-operator@acme-qa-org.local}"
QA_ADMIN_PASS="password123"

# ── URL Config ─────────────────────────────────────────────────────────
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-${BASE_URL:-http://localhost:4000}}"
export BASE_URL="${BASE_URL:-$CONTROL_PLANE_URL}"

# For cloud environments, route all service URLs through the control plane proxy.
# For local environments, use direct service ports.
if _is_cloud; then
    DISCOVERY_URL="${DISCOVERY_URL:-${BASE_URL}}"
    POLICY_URL="${POLICY_URL:-${BASE_URL}}"
    DRIFT_URL="${DRIFT_URL:-${BASE_URL}}"
    LANDING_URL="${LANDING_URL:-${BASE_URL}}"
else
    DISCOVERY_URL="${DISCOVERY_URL:-http://localhost:8190}"
    POLICY_URL="${POLICY_URL:-http://localhost:8093}"
    DRIFT_URL="${DRIFT_URL:-http://localhost:8183}"
    LANDING_URL="${LANDING_URL:-http://localhost:5174}"
fi

API_KEY_SECRET="${API_KEY_SECRET:-dev-secret-key}"
ADMIN_SECRET="${ADMIN_SECRET:-}"
INTERNAL_SERVICE_TOKEN="${INTERNAL_SERVICE_TOKEN:-runtimeai-dev-secret-2026}"

# ── Cookie Jar ─────────────────────────────────────────────────────────
# If the orchestrator already set COOKIE_FILE (e.g., rt19_full_platform_test.sh),
# reuse that session rather than creating a new cookies.txt.
COOKIE_FILE="${COOKIE_FILE:-cookies.txt}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[QA] $1${NC}"
}

pass() {
    echo -e "${GREEN}[QA] PASS: $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# ── Login (Azure-aware) ───────────────────────────────────────────────
# 1. If COOKIE_FILE already has a valid session (set by orchestrator), skip login.
# 2. If ADMIN_SECRET is set, use admin impersonation (works on Azure).
# 3. Otherwise, fall back to direct email/password login.
login() {
    local email="${1:-$TEST_EMAIL}"
    local password="${2:-$TEST_PASS}"
    local tenant="${3:-$TEST_TENANT}"

    log "Logging in as $email to tenant $tenant..."

    # Strategy 1: Check if we already have a valid session cookie from orchestrator
    if [ -f "$COOKIE_FILE" ] && [ -s "$COOKIE_FILE" ]; then
        # Quick probe: if /api/health returns 200 with this cookie, we're already authed
        local probe_code
        probe_code=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE_FILE" "${CONTROL_PLANE_URL}/api/agents" 2>/dev/null || echo "000")
        if [ "$probe_code" = "200" ]; then
            log "Login successful. (Reusing existing session cookie.)"
            # Copy to cookies.txt for scripts that hardcode that path
            if [ "$COOKIE_FILE" != "cookies.txt" ]; then
                cp "$COOKIE_FILE" cookies.txt 2>/dev/null || true
            fi
            return 0
        fi
    fi

    # Strategy 2: Admin impersonation via ADMIN_SECRET (Azure-compatible)
    if [ -n "$ADMIN_SECRET" ]; then
        local imp_result
        imp_result=$(curl -sk -c "$COOKIE_FILE" -X POST "${CONTROL_PLANE_URL}/api/admin/impersonate" \
            -H "Content-Type: application/json" \
            -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
            -d "{\"tenant_id\": \"$tenant\"}" 2>&1)
        if echo "$imp_result" | grep -q "impersonating"; then
            log "Login successful. Session cookie saved."
            # Copy to cookies.txt for scripts that hardcode that path
            if [ "$COOKIE_FILE" != "cookies.txt" ]; then
                cp "$COOKIE_FILE" cookies.txt 2>/dev/null || true
            fi
            return 0
        fi
    fi

    # Strategy 3: Direct email/password login
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -c "$COOKIE_FILE" -X POST "${CONTROL_PLANE_URL}/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"tenant_id\": \"$tenant\", \"email\": \"$email\", \"password\": \"$password\"}")

    if [ "$HTTP_CODE" != "200" ]; then
        error "Login failed with status $HTTP_CODE"
    fi
    log "Login successful. Session cookie saved."

    # Copy to cookies.txt for scripts that hardcode that path
    if [ "$COOKIE_FILE" != "cookies.txt" ]; then
        cp "$COOKIE_FILE" cookies.txt 2>/dev/null || true
    fi
}

# Wrapper for authenticated curl
auth_curl() {
    curl -sk -b "$COOKIE_FILE" -b cookies.txt "$@"
}

# Wrapper for API Key authenticated curl
apikey_curl() {
    curl -sk -H "X-API-Key: ${API_KEY_SECRET}" "$@"
}

# Wrapper for OPA authenticated curl
OPA_TOKEN="${OPA_TOKEN:-rtai-opa-secret-2026}"
opa_curl() {
    curl -sk -H "Authorization: Bearer ${OPA_TOKEN}" "$@"
}

get_agent_token() {
    local tenant="${1:-$TENANT_ID}"
    local agent="qa-agent"
    echo "$agent.$tenant.sig"
}

# Helper to create agent and return ID
create_agent() {
    local name="${1:-Test Agent}"
    local owner="${2:-dev-team}"
    local env="${3:-production}"

    # Generate temporary ID for request (ignored by backend)
    local temp_id="agent-$(date +%s)"

    RESPONSE=$(auth_curl -H "Content-Type: application/json" \
      -d "{\"agent_id\":\"$temp_id\",\"name\":\"$name\",\"owner\":\"$owner\",\"environment\":\"$env\"}" \
      "$CONTROL_PLANE_URL/api/agents")

    # Extract real ID
    REAL_ID=$(echo "$RESPONSE" | jq -r '.agent_id')

    if [ "$REAL_ID" == "null" ] || [ -z "$REAL_ID" ]; then
        echo "Error creating agent: $RESPONSE" >&2
        return 1
    fi
    echo "$REAL_ID"
}

# Helper: skip test if in cloud environment and feature requires docker
skip_if_cloud() {
    if _is_cloud; then
        echo "  ⏩ SKIP: $1 (requires Docker — not available in Azure)"
        return 0
    fi
    return 1
}

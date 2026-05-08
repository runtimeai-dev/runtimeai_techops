#!/bin/bash
# Shadow AI Discovery Test — Azure-compatible
# Tests shadow AI detection via Control Plane API (no direct Discovery Service access needed)

set -eo pipefail
source "$(dirname "$0")/common.sh"

log() {
    echo "[$(date +'%H:%M:%S')] $1"
}

fail() {
    log "❌ $1"
    exit 1
}

# 1. Login (Azure-aware)
login "$QA_ADMIN_EMAIL" "$QA_ADMIN_PASS" "$QA_TENANT_ID"

# 2. Check inventory endpoint exists (via Control Plane)
log "Checking discovered agents inventory..."
RESP=$(auth_curl "${CONTROL_PLANE_URL}/api/inventory/discovered")
if echo "$RESP" | jq -e '.' > /dev/null 2>&1; then
    log "✅ Discovery inventory endpoint responsive"
else
    fail "Discovery inventory endpoint not responding"
fi

# 3. Check Shadow AI findings
log "Checking Shadow AI findings..."
FINDINGS=$(auth_curl "${CONTROL_PLANE_URL}/api/discovery/findings")
if echo "$FINDINGS" | jq -e '.' > /dev/null 2>&1; then
    log "✅ Discovery findings endpoint responsive"
else
    fail "Discovery findings endpoint not responding"
fi

# 4. Verify scanner types are available
log "Checking scanner types..."
SCANNER_TYPES=$(auth_curl "${CONTROL_PLANE_URL}/api/discovery/scanner-types")
if echo "$SCANNER_TYPES" | jq -e '.' > /dev/null 2>&1; then
    log "✅ Scanner types available"
else
    fail "Scanner types endpoint not responding"
fi

# 5. Check AI assistants discovery
log "Checking AI assistants discovery..."
AI_ASSISTANTS=$(auth_curl "${CONTROL_PLANE_URL}/api/discovery/ai-assistants")
if echo "$AI_ASSISTANTS" | jq -e '.' > /dev/null 2>&1; then
    log "✅ AI assistants discovery endpoint responsive"
else
    fail "AI assistants discovery endpoint not responding"
fi

log "✅ Shadow AI Discovery Verification Complete"
exit 0

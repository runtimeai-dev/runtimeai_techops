#!/bin/bash
source ./common.sh

# 1. Login as Tenant Admin
login "a-admin@bank-a.local" "password123" "bank-a"

log "--- Step 1: Add Egress Policy (ALLOW api.openai.com) ---"
HTTP_CODE=$(auth_curl -s -o /dev/null -w "%{http_code}" -X POST "${CONTROL_PLANE_URL}/api/policies/egress" \
  -H "Content-Type: application/json" \
  -d '{"destination": "api.openai.com", "action": "ALLOW", "category": "llm_provider"}')

if [ "$HTTP_CODE" != "200" ]; then
    error "Failed to add policy. Status: $HTTP_CODE"
fi
log "Policy added successfully."

log "--- Step 1a: Add Egress Policy (BLOCK evil.com) ---"
auth_curl -s -o /dev/null -X POST "${CONTROL_PLANE_URL}/api/policies/egress" \
  -H "Content-Type: application/json" \
  -d '{"destination": "evil.com", "action": "BLOCK", "category": "malware"}'

log "--- Step 2: Verify Policies List ---"
RESPONSE=$(auth_curl -s "${CONTROL_PLANE_URL}/api/policies/egress")
echo "Policies: $RESPONSE"
if [[ "$RESPONSE" != *"api.openai.com"* ]]; then
    error "Policy for api.openai.com not found in list."
fi
log "Policies list verified."

log "--- Step 3: Check Policy (Simulating Flow Enforcer) ---"
# Case A: ALLOW
log "Case A: Checking api.openai.com (Should be ALLOWH)"
CHECK_RESPONSE=$(curl -s "${CONTROL_PLANE_URL}/api/policies/egress/check" \
  -H "Authorization: Bearer rtai-auditor-token" \
  -H "X-Tenant-ID: bank-a" \
  -H "Content-Type: application/json" \
  -d '{"destination": "api.openai.com"}')

echo "Check Response A: $CHECK_RESPONSE"
if [[ "$CHECK_RESPONSE" != *"ALLOW"* ]]; then
    error "Expected ALLOW for api.openai.com, got $CHECK_RESPONSE"
fi

# Case B: BLOCK (Explicit)
log "Case B: Checking evil.com (Should be BLOCK)"
CHECK_RESPONSE=$(curl -s "${CONTROL_PLANE_URL}/api/policies/egress/check" \
  -H "Authorization: Bearer rtai-auditor-token" \
  -H "X-Tenant-ID: bank-a" \
  -H "Content-Type: application/json" \
  -d '{"destination": "evil.com"}')

echo "Check Response B: $CHECK_RESPONSE"
if [[ "$CHECK_RESPONSE" != *"BLOCK"* ]]; then
    error "Expected BLOCK for evil.com, got $CHECK_RESPONSE"
fi

# Case C: BLOCK (Default Deny)
log "Case C: Checking unknown.com (Should be BLOCK)"
CHECK_RESPONSE=$(curl -s "${CONTROL_PLANE_URL}/api/policies/egress/check" \
  -H "Authorization: Bearer rtai-auditor-token" \
  -H "X-Tenant-ID: bank-a" \
  -H "Content-Type: application/json" \
  -d '{"destination": "unknown.com"}')

echo "Check Response C: $CHECK_RESPONSE"
if [[ "$CHECK_RESPONSE" != *"BLOCK"* ]]; then
    error "Expected BLOCK for unknown.com, got $CHECK_RESPONSE"
fi

log "SUCCESS: All Egress Policy tests passed."

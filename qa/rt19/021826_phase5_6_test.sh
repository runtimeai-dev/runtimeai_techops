#!/bin/bash
# Phase 5-6: Non-Functional Hardening & New Features — QA Test Script
# Tests notification API, activity timeline, compliance export, and pagination
# Date: 2026-02-18

set -eo pipefail

CONTROL_PLANE="${CONTROL_PLANE_URL:-http://localhost:8080}"
PASS=0
FAIL=0
TOTAL=0

log_result() {
    TOTAL=$((TOTAL + 1))
    if [ "$1" = "PASS" ]; then
        PASS=$((PASS + 1))
        echo "  ✅ PASS: $2"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ FAIL: $2 — $3"
    fi
}

# --- Login and get session cookie ---
echo "=== Phase 5-6 QA Tests ==="
echo ""
echo "--- Authenticating ---"

COOKIE_FILE=$(mktemp)
LOGIN_RESP=$(curl -s -c "$COOKIE_FILE" -X POST "${CONTROL_PLANE}/api/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"a-operator@bank-a.local","password":"password123","tenant_id":"bank-a"}' \
    -w "\n%{http_code}")
LOGIN_CODE=$(echo "$LOGIN_RESP" | tail -1)

if [ "$LOGIN_CODE" != "200" ]; then
    echo "  ⚠️  Login failed (HTTP $LOGIN_CODE). Some tests may fail."
fi

echo ""
echo "--- P5-005: Server-Side Pagination Tests ---"

# Test 1: Pagination query params accepted
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/notifications?limit=5&offset=0" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

if [ "$CODE" = "200" ] && echo "$BODY" | jq -e '.total != null and .limit != null and .offset != null' >/dev/null 2>&1; then
    log_result "PASS" "Notifications endpoint returns pagination metadata"
else
    log_result "FAIL" "Notifications endpoint pagination metadata" "HTTP $CODE"
fi

# Test 2: Default limit is applied
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/notifications" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)
LIMIT=$(echo "$BODY" | jq -r '.limit // empty' 2>/dev/null)

if [ "$CODE" = "200" ] && [ "$LIMIT" = "50" ]; then
    log_result "PASS" "Default pagination limit is 50"
else
    log_result "FAIL" "Default pagination limit" "Got limit=$LIMIT"
fi

echo ""
echo "--- P5-006: Notification System Tests ---"

# Test 3: List notifications
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/notifications" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

if [ "$CODE" = "200" ] && echo "$BODY" | jq -e '.items' >/dev/null 2>&1; then
    log_result "PASS" "List notifications returns items array"
else
    log_result "FAIL" "List notifications" "HTTP $CODE"
fi

# Test 4: Unread count endpoint
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/notifications/count" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

if [ "$CODE" = "200" ] && echo "$BODY" | jq -e '.unread != null' >/dev/null 2>&1; then
    log_result "PASS" "Unread count endpoint returns count"
else
    log_result "FAIL" "Unread count endpoint" "HTTP $CODE"
fi

# Test 5: Mark all as read
RESP=$(curl -s -X POST -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/notifications/read-all" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)

if [ "$CODE" = "200" ]; then
    log_result "PASS" "Mark all notifications as read"
else
    log_result "FAIL" "Mark all as read" "HTTP $CODE"
fi

# Test 6: Unread-only filter
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/notifications?unread_only=true" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)

if [ "$CODE" = "200" ]; then
    log_result "PASS" "Unread-only filter accepted"
else
    log_result "FAIL" "Unread-only filter" "HTTP $CODE"
fi

echo ""
echo "--- P6-001: Activity Timeline Tests ---"

# Test 7: Timeline returns unified events
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/activity?limit=10" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

if [ "$CODE" = "200" ] && echo "$BODY" | jq -e '.items and .total != null' >/dev/null 2>&1; then
    log_result "PASS" "Activity timeline returns paginated items"
else
    log_result "FAIL" "Activity timeline" "HTTP $CODE"
fi

# Test 8: Source filter works
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/activity?source=audit" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)

if [ "$CODE" = "200" ]; then
    log_result "PASS" "Activity timeline source filter accepted"
else
    log_result "FAIL" "Activity timeline source filter" "HTTP $CODE"
fi

echo ""
echo "--- P6-003: Compliance Evidence Export Tests ---"

# Test 9: CSV export
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/compliance/export?format=csv" -w "\n%{http_code}" -D -)
CODE=$(echo "$RESP" | tail -1)

if echo "$RESP" | grep -q "text/csv"; then
    log_result "PASS" "Compliance CSV export returns correct content-type"
else
    log_result "FAIL" "CSV export content-type" "Missing text/csv header"
fi

# Test 10: JSON export
RESP=$(curl -s -b "$COOKIE_FILE" "${CONTROL_PLANE}/api/compliance/export?format=json" -w "\n%{http_code}")
CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

if [ "$CODE" = "200" ] && echo "$BODY" | jq -e '.posture and .gaps' >/dev/null 2>&1; then
    log_result "PASS" "Compliance JSON export returns posture and gaps"
else
    log_result "FAIL" "JSON export" "HTTP $CODE"
fi

echo ""
echo "--- P5-001/002/003: Database Migration Tests ---"

# Test 11: Migrations files exist
if [ -f "control-plane/internal/db/migrations/054_enum_constraints.sql" ] && \
   [ -f "control-plane/internal/db/migrations/055_missing_indexes.sql" ] && \
   [ -f "control-plane/internal/db/migrations/056_timestamptz_fix.sql" ]; then
    log_result "PASS" "All 3 migration files exist (054, 055, 056)"
else
    log_result "FAIL" "Migration files" "Missing one or more migration files"
fi

echo ""
echo "--- P5-004: TypeScript Interface Tests ---"

# Test 12: TypeScript types file exists
if [ -f "dashboard/src/types/msft.ts" ]; then
    INTERFACE_COUNT=$(grep -c "export interface" "dashboard/src/types/msft.ts" 2>/dev/null || echo 0)
    if [ "$INTERFACE_COUNT" -ge 10 ]; then
        log_result "PASS" "msft.ts has $INTERFACE_COUNT TypeScript interfaces (≥10)"
    else
        log_result "FAIL" "TypeScript interfaces count" "Found only $INTERFACE_COUNT"
    fi
else
    log_result "FAIL" "msft.ts file" "File not found"
fi

echo ""
echo "--- P6-002/004: Frontend Component Tests ---"

# Test 13: Workflow Action Builder exists
if [ -f "dashboard/src/components/WorkflowActionBuilder.tsx" ]; then
    log_result "PASS" "WorkflowActionBuilder.tsx exists"
else
    log_result "FAIL" "WorkflowActionBuilder.tsx" "File not found"
fi

# Test 14: Onboarding Wizard exists
if [ -f "dashboard/src/components/OnboardingWizard.tsx" ]; then
    log_result "PASS" "OnboardingWizard.tsx exists"
else
    log_result "FAIL" "OnboardingWizard.tsx" "File not found"
fi

echo ""
echo "--- Go Build Verification ---"

# Test 15: Go build passes
cd control-plane 2>/dev/null || true
if go build ./... 2>/dev/null; then
    log_result "PASS" "Go build passes with 0 errors"
else
    log_result "FAIL" "Go build" "Build failed"
fi
cd - >/dev/null 2>/dev/null || true

echo ""
echo "========================================="
echo "  Phase 5-6 QA Results"
echo "  PASS: $PASS / $TOTAL"
echo "  FAIL: $FAIL / $TOTAL"
echo "========================================="

# Cleanup
rm -f "$COOKIE_FILE"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0

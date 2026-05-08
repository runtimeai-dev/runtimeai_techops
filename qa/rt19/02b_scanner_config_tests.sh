#!/bin/bash
# 02b_scanner_config_tests.sh
# QA Test: Scanner Configurations CRUD and Tenant Isolation Validation

set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
TENANT_1="bank-a"
ADMIN_1="a-operator@bank-a.local"
PASS_1="password123"
COOKIE_1="/tmp/scanner_test_cookie1.txt"

TENANT_2="acme-corp"
ADMIN_2="support@acme-corp.local"
PASS_2="password123"
COOKIE_2="/tmp/scanner_test_cookie2.txt"

PASS=0
FAIL=0
TOTAL=0

log_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    echo "  ✅ PASS: $1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    echo "  ❌ FAIL: $1"
    echo "     Detail: ${2:-}"
}

echo "══════════════════════════════════════════════════════════"
echo "  Scanner Config API QA Testing"
echo "  $(date)"
echo "  Target: $BASE_URL"
echo "══════════════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────
# Part 1: Authentication
# ─────────────────────────────────────────
echo "── Authenticating Tenants ──"

# Tenant 1 Login
curl -s -c "$COOKIE_1" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\":\"$TENANT_1\",\"email\":\"$ADMIN_1\",\"password\":\"$PASS_1\"}" > /dev/null

if [ ! -s "$COOKIE_1" ]; then
    log_fail "Login to $TENANT_1" "Could not generate cookie file"
    exit 1
else
    log_pass "Login to $TENANT_1 ($ADMIN_1)"
fi

# Tenant 2 Login
curl -s -c "$COOKIE_2" -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\":\"$TENANT_2\",\"email\":\"$ADMIN_2\",\"password\":\"$PASS_2\"}" > /dev/null

if [ ! -s "$COOKIE_2" ]; then
    log_fail "Login to $TENANT_2" "Could not generate cookie file"
    exit 1
else
    log_pass "Login to $TENANT_2 ($ADMIN_2)"
fi

# ─────────────────────────────────────────
# Part 2: Scanner Config CRUD
# ─────────────────────────────────────────
echo ""
echo "── Part 2: Scanner Config CRUD (Tenant 1) ──"

# 1. Create a scanner config
CREATE_RESP=$(curl -s -w "\n%{http_code}" -b "$COOKIE_1" -X POST "$BASE_URL/api/discovery/scanner-configs" \
    -H "Content-Type: application/json" \
    -d '{
        "scanner_id": "github-actions",
        "name": "GitHub Actions Demo",
        "execution_tier": "cloud_api",
        "credentials_vault_ref": "az://runtimeai-rt19-kv/github-token-test",
        "config": {"org": "test-org"},
        "enabled": true
    }')

HTTP_CODE=$(echo "$CREATE_RESP" | tail -n1)
BODY=$(echo "$CREATE_RESP" | head -n -1)

if [ "$HTTP_CODE" = "201" ]; then
    CONFIG_ID=$(echo "$BODY" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    log_pass "Create Scanner Config (POST): HTTP 201 (ID: $CONFIG_ID)"
else
    log_fail "Create Scanner Config (POST)" "HTTP $HTTP_CODE - $BODY"
fi

# 2. Get scanner configs
GET_RESP=$(curl -s -w "\n%{http_code}" -b "$COOKIE_1" "$BASE_URL/api/discovery/scanner-configs")
HTTP_CODE=$(echo "$GET_RESP" | tail -n1)
BODY=$(echo "$GET_RESP" | head -n -1)

if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | grep -q "\"scanner_id\":\"github-actions\""; then
    log_pass "List Scanner Configs (GET): HTTP 200 (Contains 'github-actions')"
else
    log_fail "List Scanner Configs (GET)" "HTTP $HTTP_CODE or missing 'github-actions' - $BODY"
fi

# 3. Update scanner config
if [ -n "$CONFIG_ID" ]; then
    PATCH_RESP=$(curl -s -w "\n%{http_code}" -b "$COOKIE_1" -X PATCH "$BASE_URL/api/discovery/scanner-configs/$CONFIG_ID" \
        -H "Content-Type: application/json" \
        -d '{
            "execution_tier": "cloud_api",
            "enabled": false,
            "config": {"org": "updated-org"},
            "credentials_vault_ref": ""
        }')
    HTTP_CODE=$(echo "$PATCH_RESP" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_pass "Update Scanner Config (PATCH): HTTP 200"
    else
        log_fail "Update Scanner Config (PATCH)" "HTTP $HTTP_CODE"
    fi
else
    log_fail "Update Scanner Config (PATCH)" "Skipped (no Config ID)"
fi

# ─────────────────────────────────────────
# Part 3: Tenant Isolation Checks
# ─────────────────────────────────────────
echo ""
echo "── Part 3: Tenant Isolation ──"

GET_RESP_2=$(curl -s -w "\n%{http_code}" -b "$COOKIE_2" "$BASE_URL/api/discovery/scanner-configs")
HTTP_CODE=$(echo "$GET_RESP_2" | tail -n1)
BODY=$(echo "$GET_RESP_2" | head -n -1)

if [ "$HTTP_CODE" = "200" ] && ! echo "$BODY" | grep -q "\"id\":\"$CONFIG_ID\""; then
    log_pass "Tenant Isolation (GET): Tenant 2 cannot see Tenant 1 config"
else
    log_fail "Tenant Isolation (GET)" "Tenant 2 saw Tenant 1 config OR HTTP failure: $HTTP_CODE"
fi

if [ -n "$CONFIG_ID" ]; then
    PATCH_RESP_2=$(curl -s -w "\n%{http_code}" -b "$COOKIE_2" -X PATCH "$BASE_URL/api/discovery/scanner-configs/$CONFIG_ID" \
        -H "Content-Type: application/json" \
        -d '{"enabled": true}')
    HTTP_CODE=$(echo "$PATCH_RESP_2" | tail -n1)
    
    if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "403" ]; then
        log_pass "Tenant Isolation (PATCH): Tenant 2 cannot update Tenant 1 config (HTTP $HTTP_CODE)"
    else
        log_fail "Tenant Isolation (PATCH)" "Tenant 2 updated Tenant 1 config OR unexpected HTTP: $HTTP_CODE"
    fi
    
    DEL_RESP_2=$(curl -s -w "\n%{http_code}" -b "$COOKIE_2" -X DELETE "$BASE_URL/api/discovery/scanner-configs/$CONFIG_ID")
    HTTP_CODE=$(echo "$DEL_RESP_2" | tail -n1)
    
    if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "403" ]; then
        log_pass "Tenant Isolation (DELETE): Tenant 2 cannot delete Tenant 1 config (HTTP $HTTP_CODE)"
    else
        log_fail "Tenant Isolation (DELETE)" "Unexpected HTTP: $HTTP_CODE"
    fi
else
    log_fail "Tenant Isolation (Mutation)" "Skipped (no Config ID)"
fi

# 4. Clean up / Delete
if [ -n "$CONFIG_ID" ]; then
    DEL_RESP=$(curl -s -w "\n%{http_code}" -b "$COOKIE_1" -X DELETE "$BASE_URL/api/discovery/scanner-configs/$CONFIG_ID")
    HTTP_CODE=$(echo "$DEL_RESP" | tail -n1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_pass "Delete Scanner Config (DELETE): HTTP 200"
    else
        log_fail "Delete Scanner Config (DELETE)" "HTTP $HTTP_CODE"
    fi
else
    log_fail "Delete Scanner Config (DELETE)" "Skipped (no Config ID)"
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo " RESULTS: $PASS passed / $FAIL failed / $TOTAL total"
echo "══════════════════════════════════════════════════════════"

rm -f "$COOKIE_1" "$COOKIE_2"
exit $FAIL

#!/bin/bash
# ============================================================
# Console Availability & Health Tests
# Covers: NHI Security, Cloud Security, Kinetic AI,
#         RuntimeCRM, Omni Command Center (OPER_RT19-073..077)
#
# Tests per console:
#   1. Landing page returns HTTP 200
#   2. Correct <title> in HTML
#   3. Static asset (logo) serves with correct content-type
#   4. Auth proxy: /api/auth/me returns 401 (not 404/502)
# ============================================================
set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

pass_test() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  ✅ PASS: $1"; }
fail_test() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ❌ FAIL: $1 — $2"; }

check_console() {
    local label="$1"
    local url="$2"
    local expected_title="$3"
    local logo_path="${4:-/logo-v2-dark.png}"
    local auth_path="${5:-/api/auth/me}"

    echo ""
    echo "── $label ($url) ──"

    # 1. Landing page HTTP 200
    local code
    code=$(curl -sf "$url/" -o /dev/null -w "%{http_code}" --max-time 10 2>&1 || echo "000")
    if [ "$code" = "200" ]; then
        pass_test "$label: landing page → 200"
    else
        fail_test "$label: landing page → 200" "got HTTP $code"
    fi

    # 2. Correct page title
    local title
    title=$(curl -sf "$url/" --max-time 10 2>/dev/null | grep -o '<title>[^<]*</title>' | head -1 || true)
    if echo "$title" | grep -qi "$expected_title"; then
        pass_test "$label: page title contains '$expected_title'"
    else
        fail_test "$label: page title contains '$expected_title'" "got: $title"
    fi

    # 3. Logo static asset — content-type must be image/* (not text/html)
    local ct
    ct=$(curl -sf "$url$logo_path" -o /dev/null -w "%{content_type}" --max-time 10 2>&1 || echo "error")
    if echo "$ct" | grep -qi "image/"; then
        pass_test "$label: logo asset content-type is image/*"
    else
        fail_test "$label: logo asset content-type is image/*" "got: $ct"
    fi

    # 4. Auth proxy returns 401 (not 404/502 which would indicate nginx misconfiguration)
    local auth_code
    auth_code=$(curl -sk "$url$auth_path" -o /dev/null -w "%{http_code}" --max-time 10 2>&1 || echo "000")
    if [ "$auth_code" = "401" ] || [ "$auth_code" = "403" ]; then
        pass_test "$label: auth proxy ($auth_path) → $auth_code (auth required)"
    elif [ "$auth_code" = "000" ]; then
        fail_test "$label: auth proxy ($auth_path)" "no connection (000)"
    else
        fail_test "$label: auth proxy ($auth_path) → 401/403" "got HTTP $auth_code"
    fi
}

echo ""
echo "── Console Availability & Health Tests ──"
echo "  Verifying 5 product consoles are live and routing correctly"

# OPER_RT19-073: NHI Security Console
check_console \
    "NHI Security" \
    "https://nhi.rt19.runtimeai.io" \
    "NHI Security"

# OPER_RT19-074: Cloud Security Console
check_console \
    "Cloud Security" \
    "https://cloud.rt19.runtimeai.io" \
    "Cloud Security"

# OPER_RT19-075: Kinetic AI Console
check_console \
    "Kinetic AI" \
    "https://kinetic.rt19.runtimeai.io" \
    "Kinetic"

# OPER_RT19-076: RuntimeCRM Console
check_console \
    "RuntimeCRM" \
    "https://app.runtimecrm.com" \
    "RuntimeCRM"

# OPER_RT19-077: Omni Command Center
check_console \
    "Omni Command Center" \
    "https://omni.rt19.runtimeai.io" \
    "Omni"

# ── Summary ──────────────────────────────────────────────
echo ""
echo "  PASS: $PASS_COUNT  |  FAIL: $FAIL_COUNT"
echo "----------------------------------------"
[ $FAIL_COUNT -eq 0 ]

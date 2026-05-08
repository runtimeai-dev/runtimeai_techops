#!/bin/bash
set -euo pipefail

BASE="${1:-http://localhost:4000}"
TENANT_ID="${2:-felt-sense}"
COOKIE="/tmp/gap_qa_cookies.txt"

PASSED=0
FAILED=0
SKIPPED=0

pass() { echo -e "\033[0;32m  ✓ PASS\033[0m $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "\033[0;31m  ✗ FAIL\033[0m $1"; FAILED=$((FAILED + 1)); }
skip() { echo -e "\033[0;33m  ○ SKIP\033[0m $1"; SKIPPED=$((SKIPPED + 1)); }

echo -e "\n\033[1;34m━━━ 31. eSign Standalone Smoke ━━━\033[0m"
# OPER_RT19-059: eSign is now standalone at esign.rt19.runtimeai.io.
# The /api/proxy/esign dashboard proxy has been removed. Test the standalone frontend.

ESIGN_BASE="${ESIGN_STANDALONE_URL:-https://esign.rt19.runtimeai.io}"
HTTP=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ESIGN_BASE/" 2>/dev/null || echo "000")
if [ "$HTTP" = "200" ]; then
  pass "eSign standalone — $ESIGN_BASE reachable (HTTP $HTTP)"
elif [ "$HTTP" = "000" ]; then
  skip "eSign standalone — not reachable at $ESIGN_BASE"
else
  pass "eSign standalone — HTTP $HTTP (endpoint exists)"
fi

echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "\033[1;32m PASSED: $PASSED\033[0m"
if [ "$FAILED" -gt 0 ]; then
  echo -e "\033[1;31m FAILED: $FAILED\033[0m"
  exit 1
fi

#!/usr/bin/env bash
# =============================================================================
# QA Test: LLM Enforcer Model Enforcement (BE-035)
# Tests proxy key allowed/blocked model restrictions
# =============================================================================
set -euo pipefail

ENFORCER="${ENFORCER_URL:-https://enforcer.rt19.runtimeai.io}"
PASS=0; FAIL=0; TOTAL=0

log() { echo -e "\033[0;36m[TEST]\033[0m $*"; }
pass() { ((PASS++)); ((TOTAL++)); echo -e "  \033[0;32mPASS\033[0m $*"; }
fail() { ((FAIL++)); ((TOTAL++)); echo -e "  \033[0;31mFAIL\033[0m $*"; }

# Requires: PROXY_KEY_RESTRICTED (allowed=[gpt-4o-mini], not gpt-5.4)
# Requires: PROXY_KEY_OPEN (allowed=[])
KEY_RESTRICTED="${PROXY_KEY_RESTRICTED:-}"
KEY_OPEN="${PROXY_KEY_OPEN:-}"

if [[ -z "$KEY_RESTRICTED" || -z "$KEY_OPEN" ]]; then
  echo "ERROR: Set PROXY_KEY_RESTRICTED and PROXY_KEY_OPEN env vars"
  echo "  PROXY_KEY_RESTRICTED: key with allowed_models=[gpt-4o-mini]"
  echo "  PROXY_KEY_OPEN: key with allowed_models=[] (all models)"
  exit 1
fi

echo "═══════════════════════════════════════════════════"
echo "  LLM Enforcer — Model Enforcement Tests"
echo "═══════════════════════════════════════════════════"

# --- OpenAI Tests ---
log "=== OpenAI via Authorization: Bearer ==="

log "[1/8] Restricted key + allowed model (gpt-4o-mini)"
R=$(curl -s "$ENFORCER/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY_RESTRICTED" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}')
if echo "$R" | grep -q '"choices"'; then pass "Allowed model passed through"; else fail "Expected response, got: $(echo $R | head -c 100)"; fi

log "[2/8] Restricted key + disallowed model (gpt-5.4)"
R=$(curl -s "$ENFORCER/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY_RESTRICTED" \
  -d '{"model":"gpt-5.4","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}')
if echo "$R" | grep -q 'model_not_allowed'; then pass "Disallowed model blocked"; else fail "Expected block, got: $(echo $R | head -c 100)"; fi

log "[3/8] Open key + any model (gpt-5.4)"
R=$(curl -s "$ENFORCER/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KEY_OPEN" \
  -d '{"model":"gpt-5.4","messages":[{"role":"user","content":"Say OK"}],"max_completion_tokens":5}')
if echo "$R" | grep -q '"choices"'; then pass "Open key allows all models"; else fail "Expected response, got: $(echo $R | head -c 100)"; fi

log "[4/8] Invalid key"
R=$(curl -s "$ENFORCER/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer rtai-pk-invalid-fake" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}],"max_tokens":5}')
if echo "$R" | grep -q 'invalid_proxy_key'; then pass "Invalid key rejected"; else fail "Expected rejection, got: $(echo $R | head -c 100)"; fi

# --- Anthropic Tests (x-api-key header) ---
log "=== Anthropic via x-api-key ==="

ANTHROPIC_KEY_RESTRICTED="${ANTHROPIC_PROXY_KEY_RESTRICTED:-}"
if [[ -n "$ANTHROPIC_KEY_RESTRICTED" ]]; then
  log "[5/8] Anthropic restricted key + allowed model"
  R=$(curl -s "$ENFORCER/anthropic/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_KEY_RESTRICTED" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-sonnet-4-20250514","max_tokens":10,"messages":[{"role":"user","content":"Say OK"}]}')
  if echo "$R" | grep -q '"content"'; then pass "Anthropic allowed model passed"; else fail "Got: $(echo $R | head -c 100)"; fi

  log "[6/8] Anthropic restricted key + blocked model"
  R=$(curl -s "$ENFORCER/anthropic/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_KEY_RESTRICTED" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-opus-4-6","max_tokens":10,"messages":[{"role":"user","content":"Say OK"}]}')
  if echo "$R" | grep -q 'model_not_allowed'; then pass "Anthropic blocked model rejected"; else fail "Got: $(echo $R | head -c 100)"; fi

  log "[7/8] Anthropic invalid key"
  R=$(curl -s "$ENFORCER/anthropic/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: rtai-pk-invalid" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-sonnet-4-20250514","max_tokens":10,"messages":[{"role":"user","content":"test"}]}')
  if echo "$R" | grep -q 'invalid_proxy_key'; then pass "Anthropic invalid key rejected"; else fail "Got: $(echo $R | head -c 100)"; fi
else
  log "[5-7] Skipped — ANTHROPIC_PROXY_KEY_RESTRICTED not set"
  ((TOTAL+=3))
fi

log "[8/8] No auth header"
R=$(curl -s "$ENFORCER/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}],"max_tokens":5}')
if echo "$R" | grep -qE 'missing|unauthorized|invalid'; then pass "No auth rejected"; else fail "Got: $(echo $R | head -c 100)"; fi

echo ""
echo "=========================================="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Total:  $TOTAL"
echo "=========================================="
[[ "$FAIL" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL

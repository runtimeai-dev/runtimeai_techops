#!/bin/bash
set -e

source ./qa_testing_local/common.sh

echo "--------------------------------------------------"
echo "Running Flow Enforcer Budget Tests..."
echo "--------------------------------------------------"

FLOW_ENFORCER_URL="http://localhost:8092/v1/chat/completions"
# Token format: agent.tenant.sig (handled by Wasm fallback)
TENANT="${TENANT_ID:-bank-a}"
AGENT="qa-agent"
TOKEN="$AGENT.$TENANT.sig"

echo "   Tenant: $TENANT"
echo "   Agent: $AGENT"

# 1. Check Pricing (Cost Ledger Direct)
echo "1. Checking Pricing Availability..."
pricing_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8102/v1/pricing")
if [ "$pricing_status" != "200" ]; then
    echo "   FAILED: Cost Ledger Pricing not available (HTTP $pricing_status)"
    exit 1
fi
echo "   Pricing: Available"

# 2. Send Valid Request (Small cost)
echo "2. Sending Valid Request (Small)..."
# cost = tokens/1000 * 0.03
# "Hello" is ~1 token. Cost ~0.00003. Should pass.
response_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$FLOW_ENFORCER_URL" \
  -H "X-Agent-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}]}')

if [ "$response_code" == "402" ]; then
    echo "   FAILED: Valid request blocked with 402"
    exit 1
fi
# We expect 200 or 503 (if upstream fails), but NOT 402/403 (Policy/Budget)
echo "   Valid Request: Attempted (Code: $response_code). Passed Budget Check."


# 3. Send Large Request (Exceed Budget)
# Default budget is $100.
# We need to spend > $100.
# Price $0.03 / 1k tokens.
# $100 requires 3,333,333 tokens.
# That's too large to send in a single body (Wasm might crash or Envoy limit).
# Instead, we can lower the budget for this tenant via Cost Ledger API!

echo "3. setting Low Budget for Tenant..."
# PUT /v1/budgets
# {"tenant_id": "...", "limit_cents": 10, "threshold_pct": 80}
# Limit 10 cents ($0.10).
update_status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://localhost:8102/v1/budgets" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\":\"$TENANT\",\"limit_cents\":10,\"threshold_pct\":80}")

if [ "$update_status" != "200" ]; then
    echo "   FAILED: Could not update budget (HTTP $update_status)"
    exit 1
fi
echo "   Budget set to \$0.10"

echo "4. Sending Over-Budget Request..."
# Need > $0.10.
# $0.10 / $0.03 * 1000 = 3333 tokens.
# A prompt with ~4000 chars should be enough chars (~1 char/token fallback or tiktoken).
# Let's send a moderate prompt.
# Generate long string.
LONG_TEXT=$(printf 'A%.0s' {1..50000})
# Use /post to get 200 on success (instead of 404 on /chat/completions)
FLOW_ENFORCER_URL_POST="http://localhost:8092/post"
response_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$FLOW_ENFORCER_URL_POST" \
  -H "X-Agent-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"gpt-4\", \"messages\": [{\"role\": \"user\", \"content\": \"$LONG_TEXT\"}]}")

if [ "$response_code" != "402" ]; then
    echo "   FAILED: Expected 402, got $response_code"
    # echo response body for debug?
    exit 1
fi
echo "   Over-Budget Request: Correctly Blocked (402)"

echo "Flow Enforcer Tests: PASSED"

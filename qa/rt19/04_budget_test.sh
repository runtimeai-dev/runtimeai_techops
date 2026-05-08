#!/bin/bash
set -e

source ./qa_testing_local/common.sh

echo "--------------------------------------------------"
echo "Running Cost Ledger Tests..."
echo "--------------------------------------------------"

TENANT="qa-budget-tenant"
COST_LEDGER_URL="http://localhost:8102/v1/check"
RESET_COST=10.0
BLOCK_COST=100.0

echo "1. Testing Budget Enforcement..."

# 1. Reset (simulated by using a fresh tenant or accepting current state)
# For this test, we accept current state but ensure we can hit the limit.
# We'll use a unique tenant ID for this run to start fresh.
TENANT="qa-budget-$(date +%s)"

echo "   Tenant: $TENANT"

# 2. Spend $10 (Limit defaults to $100)
response=$(curl -s -X POST "$COST_LEDGER_URL" -H "Content-Type: application/json" -d "{\"tenant_id\":\"$TENANT\",\"cost\":$RESET_COST}")
allowed=$(echo "$response" | jq -r '.allowed')
remaining=$(echo "$response" | jq -r '.remaining')

if [ "$allowed" != "true" ]; then
    echo "   FAILED: Expected allowed=true, got $response"
    exit 1
fi
echo "   Spend $RESET_COST: Allowed ($remaining remaining)"

# 3. Spend $100 (Should exceed limit of $100 total if we add 100 to 10)
# Wait, default limit is 100. Current spend 10. Remaining 90.
# If we spend 95, it should be allowed (Total 105?? No, wait. 10+95=105 > 100)
# Code logic: newSpend = curent + cost. if newSpend <= limit -> allowed.
# So 10 + 95 = 105. 105 <= 100 is False.
# So it should be blocked.

response=$(curl -s -X POST "$COST_LEDGER_URL" -H "Content-Type: application/json" -d "{\"tenant_id\":\"$TENANT\",\"cost\":95.0}")
allowed=$(echo "$response" | jq -r '.allowed')

if [ "$allowed" != "false" ]; then
    echo "   FAILED: Expected allowed=false, got $response"
    exit 1
fi
echo "   Spend 95.0: Blocked (Budget Exceeded)"

# 4. Verify HTTP Status Code for blocked request
status_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$COST_LEDGER_URL" -H "Content-Type: application/json" -d "{\"tenant_id\":\"$TENANT\",\"cost\":1.0}")
if [ "$status_code" != "402" ]; then
    echo "   FAILED: Expected HTTP 402, got $status_code"
    exit 1
fi
echo "   Blocked Request HTTP Status: $status_code (OK)"



echo "--------------------------------------------------"
echo "2. Testing Pre-Check (Estimate) & Pricing..."

# Use a new tenant to ensure clean state (handleCheck increments even on failure)
TENANT="qa-budget-est-$(date +%s)"
echo "   Tenant: $TENANT"

# 1. Test Pricing
echo "   Fetching Pricing Config..."
pricing_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8102/v1/pricing")
if [ "$pricing_status" != "200" ]; then
    echo "   FAILED: Expected HTTP 200 for /pricing, got $pricing_status"
    exit 1
fi
echo "   Pricing Endpoint: OK"

# 2. Test Estimate (Dry Run)
# Current spend for tenant is committed. Let's try to estimate a large cost that would fail.
# It should return 402, but NOT increase the spend.
echo "   Testing Estimate (Dry Run)..."
est_response=$(curl -s -X POST "http://localhost:8102/v1/estimate" -H "Content-Type: application/json" -d "{\"tenant_id\":\"$TENANT\",\"cost\":1000.0}")
est_allowed=$(echo "$est_response" | jq -r '.allowed')

if [ "$est_allowed" != "false" ]; then
    echo "   FAILED Estimate: Expected allowed=false, got $est_allowed"
    exit 1
fi
echo "   Estimate 1000.0: Correctly Denied"

# Verify spend didn't increase by checking a small valid request again
# Previously we were blocked at 95.0. Total spend was 10.0. Limit 100.
# If estimate committed 1000, we'd be way over.
# If estimate didn't commit, we should still be at 10.0.
# Let's try to spend 5.0 (Total 15.0 <= 100). Should pass.
check_response=$(curl -s -X POST "$COST_LEDGER_URL" -H "Content-Type: application/json" -d "{\"tenant_id\":\"$TENANT\",\"cost\":5.0}")
check_allowed=$(echo "$check_response" | jq -r '.allowed')

if [ "$check_allowed" != "true" ]; then
    echo "   FAILED: Estimate apparently committed spend! Subsequent valid request failed."
    exit 1
fi
echo "   Dry Run Verified: Spend did not increase."

echo "Cost Ledger Tests: PASSED"

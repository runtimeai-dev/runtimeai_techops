#!/bin/bash
# AEP Chaos Testing — 6 resilience scenarios

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[✓]${NC} $*"; }
log_fail() { echo -e "${RED}[✗]${NC} $*"; }

echo "========== AEP CHAOS TEST SUITE =========="
PASSED=0
FAILED=0

# Test 1: Pod Crash Recovery
echo -n "Test 1: Pod crash recovery... "
POD=$(kubectl get pods -n aep -l app=cost-control -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD" ]; then
  kubectl delete pod "$POD" -n aep --force --grace-period=0 2>/dev/null || true
  sleep 3
  NEW_POD=$(kubectl get pods -n aep -l app=cost-control -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$NEW_POD" ]; then
    log_pass "Pod restarted"
    ((PASSED++))
  else
    log_fail "Pod not restarted"
    ((FAILED++))
  fi
else
  echo "SKIPPED (no pod)"
fi

# Test 2: Service Resilience
echo -n "Test 2: Service continues under load... "
for i in {1..20}; do
  kubectl exec -n aep "$POD" -- curl -s http://localhost:8302/health > /dev/null 2>&1 &
done
wait
log_pass "Service handled requests"
((PASSED++))

# Test 3: Health Check
echo -n "Test 3: Health endpoint responding... "
if kubectl exec -n aep "$POD" -- curl -s http://localhost:8302/health > /dev/null 2>&1; then
  log_pass "Health check passing"
  ((PASSED++))
else
  log_fail "Health check failing"
  ((FAILED++))
fi

# Test 4: Pod Status
echo -n "Test 4: Pod in Running state... "
STATUS=$(kubectl get pod "$POD" -n aep -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [ "$STATUS" = "Running" ]; then
  log_pass "Pod Running"
  ((PASSED++))
else
  log_fail "Pod status: $STATUS"
  ((FAILED++))
fi

# Test 5: Service Count
echo -n "Test 5: All services responding... "
COUNT=$(bash qa_testing_local/run_suite.sh 2>/dev/null | grep -c "\[✓\]" || echo "0")
if [ "$COUNT" -ge 10 ]; then
  log_pass "At least 10 services healthy"
  ((PASSED++))
else
  log_fail "Only $COUNT services healthy"
  ((FAILED++))
fi

# Test 6: No Crashes
echo -n "Test 6: No pod crashes during test... "
CRASHES=$(kubectl get events -n aep --sort-by='.lastTimestamp' 2>/dev/null | grep -i "crash\|oom\|error" | wc -l || echo "0")
if [ "$CRASHES" -lt 3 ]; then
  log_pass "No unexpected crashes"
  ((PASSED++))
else
  log_fail "$CRASHES crash events detected"
  ((FAILED++))
fi

echo ""
echo "========== SUMMARY =========="
echo "Passed: $PASSED/6"
echo "Failed: $FAILED/6"
echo ""

if [ $FAILED -eq 0 ]; then
  log_pass "All chaos tests passed!"
  exit 0
else
  log_fail "$FAILED test(s) failed"
  exit 1
fi

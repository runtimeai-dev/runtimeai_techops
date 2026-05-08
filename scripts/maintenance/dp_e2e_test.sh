#!/bin/bash
# =============================================================================
# rt19 Data Plane End-to-End Test Script — RuntimeAI
# =============================================================================
# Tests all DP services E2E with real health checks from inside the cluster.
# Run: ./dp_e2e_test.sh [namespace]
# Prerequisites: kubectl configured for rt19 cluster
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-rt19}"

echo "=========================================="
echo "  RuntimeAI DP End-to-End Test Plan"
echo "  Namespace: $NAMESPACE"
echo "  Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

# -------------------------------------------------------------------
# Run all health checks in a single pod to avoid pod cleanup noise
# -------------------------------------------------------------------
echo ""
echo "Running health checks from inside cluster..."
echo ""

RESULTS=$(kubectl run dp-e2e-$$ --image=curlimages/curl --restart=Never -n "$NAMESPACE" --rm -i 2>/dev/null -- sh -c '
# Control Plane services
for entry in \
  "control-plane:8080:/health:CP" \
  "dashboard:80:/healthz:CP" \
  "auth-svc:8097:/healthz:CP" \
  "mcp-gateway:8091:/healthz:CP" \
  "esign-service:8096:/healthz:CP" \
  "marketplace-service:8097:/healthz:CP" \
  "ai-finops-service:8092:/healthz:CP" \
  "billing-service:5090:/healthz:CP" \
  "aaic-service:5056:/healthz:CP" \
  "saas-admin:80:/healthz:CP" \
; do
  svc=$(echo "$entry" | cut -d: -f1)
  port=$(echo "$entry" | cut -d: -f2)
  path=$(echo "$entry" | cut -d: -f3)
  type=$(echo "$entry" | cut -d: -f4)
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://$svc:$port$path 2>/dev/null)
  echo "RESULT|$type|$svc|$port|$path|$code"
done

# Data Plane services
for entry in \
  "flow-enforcer:8001:/ready:DP" \
  "dp-proxy:8100:/healthz:DP" \
  "drift-engine:8083:/health:DP" \
  "policy-manager:8093:/health:DP" \
  "cost-ledger:8102:/health:DP" \
  "vault-broker:8097:/healthz:DP" \
  "vw-proxy:8103:/healthz:DP" \
  "bot-ca:8104:/healthz:DP" \
  "sequence-modeler:8107:/healthz:DP" \
  "network-analyzer:8106:/healthz:DP" \
  "verifier:8108:/healthz:DP" \
  "waf:8101:/healthz:DP" \
  "bundle-cache:8094:/healthz:DP" \
  "discovery:8090:/health:DP" \
; do
  svc=$(echo "$entry" | cut -d: -f1)
  port=$(echo "$entry" | cut -d: -f2)
  path=$(echo "$entry" | cut -d: -f3)
  type=$(echo "$entry" | cut -d: -f4)
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://$svc:$port$path 2>/dev/null)
  echo "RESULT|$type|$svc|$port|$path|$code"
done

# Sidecar injector (HTTPS)
code=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 3 https://sidecar-injector:443/healthz 2>/dev/null)
echo "RESULT|DP|sidecar-injector|443|/healthz|$code"
' 2>/dev/null)

# -------------------------------------------------------------------
# Parse results and display
# -------------------------------------------------------------------
PASS=0
FAIL=0
CP_PASS=0
CP_FAIL=0
DP_PASS=0
DP_FAIL=0

echo "--- Control Plane Services ---"
echo "$RESULTS" | grep "^RESULT|CP|" | while IFS='|' read -r _ type svc port path code; do
  if [ "$code" = "200" ]; then
    echo "  ✅ $svc:$port$path → $code"
  elif [ -z "$code" ] || [ "$code" = "000" ]; then
    echo "  ⚠️  $svc:$port$path → unreachable"
  else
    echo "  ❌ $svc:$port$path → $code"
  fi
done

echo ""
echo "--- Data Plane Services ---"
echo "$RESULTS" | grep "^RESULT|DP|" | while IFS='|' read -r _ type svc port path code; do
  if [ "$code" = "200" ]; then
    echo "  ✅ $svc:$port$path → $code"
  elif [ -z "$code" ] || [ "$code" = "000" ]; then
    echo "  ⚠️  $svc:$port$path → unreachable"
  else
    echo "  ❌ $svc:$port$path → $code"
  fi
done

# Count results
TOTAL=$(echo "$RESULTS" | grep -c "^RESULT|" || true)
PASSED=$(echo "$RESULTS" | grep "|200$" | grep -c "^RESULT|" || true)
FAILED=$((TOTAL - PASSED))

echo ""

# -------------------------------------------------------------------
# RLS Verification
# -------------------------------------------------------------------
echo "--- RLS Verification ---"
CP_POD=$(kubectl get pods -n "$NAMESPACE" -l app=control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
RLS_LOG=$(kubectl logs "$CP_POD" -n "$NAMESPACE" 2>/dev/null | grep "RLS" | tail -5)

if echo "$RLS_LOG" | grep -q "ENABLED"; then
  RLS_COUNT=$(echo "$RLS_LOG" | grep -o '[0-9]* tenant_isolation' | head -1)
  echo "  ✅ RLS enforcement ENABLED — $RLS_COUNT policies"
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
else
  echo "  ❌ RLS not confirmed"
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
fi

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  DP E2E Test Results"
echo "  Passed: $PASSED / $TOTAL"
if [ "$FAILED" -eq 0 ]; then
  echo "  Status: ALL TESTS PASSED ✅"
else
  echo "  Status: $FAILED FAILURES ❌"
fi
echo "=========================================="

exit "$FAILED"

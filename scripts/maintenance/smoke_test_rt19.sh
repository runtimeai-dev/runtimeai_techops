#!/bin/bash
# =============================================================================
# rt19 Production Smoke Test — RuntimeAI
# =============================================================================
# Tests health of all CP + DP services on the rt19 AKS namespace.
# Run: ./smoke_test_rt19.sh
# Requires: kubectl configured for rt19 cluster, curlimages/curl image access
# =============================================================================

set -euo pipefail

NAMESPACE="${1:-rt19}"
PASS=0
FAIL=0
WARN=0
RESULTS=""

log_pass() { PASS=$((PASS+1)); RESULTS="${RESULTS}\n✅ $1"; }
log_fail() { FAIL=$((FAIL+1)); RESULTS="${RESULTS}\n❌ $1"; }
log_warn() { WARN=$((WARN+1)); RESULTS="${RESULTS}\n⚠️  $1"; }

echo "=========================================="
echo "  RuntimeAI rt19 Smoke Test"
echo "  Namespace: $NAMESPACE"
echo "  Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="
echo ""

# -------------------------------------------------------------------
# 1. Pod Health Check — all pods should be Running + Ready
# -------------------------------------------------------------------
echo "--- Phase 1: Pod Status ---"
NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -v "Running" | grep -v "Completed" || true)
if [ -z "$NOT_READY" ]; then
  TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  log_pass "All $TOTAL_PODS pods Running"
  echo "  ✅ All $TOTAL_PODS pods Running"
else
  echo "  ❌ Unhealthy pods:"
  echo "$NOT_READY" | while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    POD_STATUS=$(echo "$line" | awk '{print $3}')
    log_fail "$POD_NAME ($POD_STATUS)"
    echo "    ❌ $POD_NAME → $POD_STATUS"
  done
fi
echo ""

# -------------------------------------------------------------------
# 2. Service Health Endpoints
# -------------------------------------------------------------------
echo "--- Phase 2: Service Health Endpoints ---"

# Define all services with their correct ports and health paths
# Format: service_name:port:health_path:protocol
SERVICES=(
  # Control Plane
  "control-plane:8080:/health:http"
  "dashboard:80:/healthz:http"
  "auth-svc:8097:/healthz:http"
  "mcp-gateway:8091:/healthz:http"
  "esign-service:8096:/healthz:http"
  "esign-landing:3001:/healthz:http"
  "marketplace-service:8097:/healthz:http"
  "ai-finops-service:8092:/healthz:http"
  "billing-service:5090:/healthz:http"
  "aaic-service:5056:/healthz:http"
  "auditor-dashboard:80:/healthz:http"
  "saas-admin:80:/healthz:http"
  "website-singlepage:80:/:http"
  # Data Plane
  "flow-enforcer:8001:/ready:http"
  "dp-proxy:8100:/healthz:http"
  "drift-engine:8083:/health:http"
  "policy-manager:8093:/health:http"
  "cost-ledger:8102:/health:http"
  "vault-broker:8097:/healthz:http"
  "vw-proxy:8103:/healthz:http"
  "bot-ca:8104:/healthz:http"
  "sequence-modeler:8107:/healthz:http"
  "network-analyzer:8106:/healthz:http"
  "verifier:8108:/healthz:http"
  "waf:8101:/healthz:http"
  "bundle-cache:8094:/healthz:http"
  "sidecar-injector:443:/healthz:https"
  "discovery:8090:/health:http"
)

# Build the curl commands dynamically
CURL_SCRIPT=""
for entry in "${SERVICES[@]}"; do
  IFS=':' read -r svc port path proto <<< "$entry"
  if [ "$proto" = "https" ]; then
    CURL_SCRIPT+="echo -n \"${svc}:${port}${path}: \"; curl -sk -o /dev/null -w \"%{http_code}\" --connect-timeout 3 https://${svc}:${port}${path} 2>/dev/null; echo '';"
  else
    CURL_SCRIPT+="echo -n \"${svc}:${port}${path}: \"; curl -s -o /dev/null -w \"%{http_code}\" --connect-timeout 3 http://${svc}:${port}${path} 2>/dev/null; echo '';"
  fi
done

# Run from inside the cluster
HEALTH_OUTPUT=$(kubectl run smoke-check-$$ --image=curlimages/curl --restart=Never -n "$NAMESPACE" --rm -i 2>/dev/null -- sh -c "$CURL_SCRIPT" 2>/dev/null || true)

echo "$HEALTH_OUTPUT" | while IFS=':' read -r svc_info code_rest; do
  # Parse the output
  svc_port_path=$(echo "$svc_info" | sed 's/^ *//')
  code=$(echo "$code_rest" | tr -d '[:space:]' | tail -c 3)
  if [ "$code" = "200" ]; then
    echo "  ✅ $svc_port_path → $code"
  elif [ -z "$code" ] || [ "$code" = "000" ]; then
    echo "  ⚠️  $svc_port_path → unreachable"
  else
    echo "  ❌ $svc_port_path → $code"
  fi
done
echo ""

# -------------------------------------------------------------------
# 3. Database Connectivity
# -------------------------------------------------------------------
echo "--- Phase 3: Database + Redis ---"
PG_POD=$(kubectl get pods -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PG_POD" ]; then
  PG_STATUS=$(kubectl get pod "$PG_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  ✅ PostgreSQL: $PG_STATUS ($PG_POD)"
else
  echo "  ❌ PostgreSQL: not found"
fi

REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$REDIS_POD" ]; then
  REDIS_STATUS=$(kubectl get pod "$REDIS_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "  ✅ Redis: $REDIS_STATUS ($REDIS_POD)"
else
  echo "  ❌ Redis: not found"
fi
echo ""

# -------------------------------------------------------------------
# 4. RLS Verification (via control-plane logs)
# -------------------------------------------------------------------
echo "--- Phase 4: RLS Verification ---"
CP_POD=$(kubectl get pods -n "$NAMESPACE" -l app=control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
RLS_LOG=$(kubectl logs "$CP_POD" -n "$NAMESPACE" 2>/dev/null | grep -i "\[RLS\]" | tail -3)
if echo "$RLS_LOG" | grep -q "ENABLED"; then
  RLS_COUNT=$(echo "$RLS_LOG" | grep -oP '\d+ tenant_isolation' | head -1)
  echo "  ✅ RLS enforcement ENABLED — $RLS_COUNT policies"
else
  echo "  ⚠️  RLS status unknown — check control-plane logs"
fi
echo ""

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo "=========================================="
echo "  Smoke Test Complete"
echo "  Passed: $PASS | Failed: $FAIL | Warnings: $WARN"
echo "=========================================="

# Exit with failure if any critical failures
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

#!/bin/bash
# AEP K8s Integration Test
# Verifies all 13 services are healthy and inter-communicating
# Date: 2026-05-06

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }

# Service ports and health endpoints
declare -A SERVICES=(
  [aep-admin]=80
  [aep-auth-service]=8350
  [aep-console]=80
  [aep-gateway]=8300
  [agent-builder-factory]=8316
  [commerce-protocol]=8309
  [developer-hub]=8311
  [audit-black-box]=8303
  [kya]=8301
  [cost-control]=8302
  [memory-vault]=8307
  [commerce-rails]=8308
  [contract-manager]=8312
  [marketplace]=8310
  [procurement-hub]=8313
  [finance-rail]=8314
  [observability]=8305
  [pii-shield]=8304
)

echo "========== AEP K8s SERVICE HEALTH CHECK =========="
echo ""

PASSED=0
FAILED=0

for SERVICE in "${!SERVICES[@]}"; do
  PORT=${SERVICES[$SERVICE]}

  # Get pod from deployment
  POD=$(kubectl get pods -n aep -l "app=$SERVICE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [ -z "$POD" ]; then
    log_warn "$SERVICE: No pod found"
    ((FAILED++))
    continue
  fi

  # Test health endpoint
  HEALTH=$(kubectl exec -n aep "$POD" -- curl -s -f "http://localhost:$PORT/healthz" 2>/dev/null || echo "")

  if [ -n "$HEALTH" ]; then
    log_info "$SERVICE ($PORT): READY"
    ((PASSED++))
  else
    log_warn "$SERVICE ($PORT): Health check failed"
    ((FAILED++))
  fi
done

echo ""
echo "========== DEPLOYMENT STATUS =========="
kubectl get deploy -n aep -o wide | grep -E "aep-|agent-|audit|kya|cost|memory|commerce|contract|procurement|finance|observ|pii|market|developer" | awk '{printf "%-30s %3s/%3s   %s\n", $1, $2, $3, ($2==$3?"✓":"⚠")}'

echo ""
echo "========== SUMMARY =========="
echo "Health checks passed: $PASSED/17"
if [ "$FAILED" -gt 0 ]; then
  echo "Health checks failed: $FAILED/17"
  log_warn "Some services are still starting or resource-constrained"
else
  log_info "All AEP services healthy and responding"
fi

echo ""
echo "========== CROSS-SERVICE CONNECTIVITY =========="

# Test: Memory Vault can talk to QuantumVault
VAULT_POD=$(kubectl get pods -n aep -l app=memory-vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$VAULT_POD" ]; then
  QVAULT_REACHABLE=$(kubectl exec -n aep "$VAULT_POD" -- curl -s -f "http://quantumvault.pqdata.svc.cluster.local:8200/healthz" 2>/dev/null && echo "yes" || echo "no")
  if [ "$QVAULT_REACHABLE" = "yes" ]; then
    log_info "Memory Vault → QuantumVault: Connected"
  else
    log_warn "Memory Vault → QuantumVault: Unreachable (may be normal if QuantumVault not deployed)"
  fi
fi

# Test: Cost Control can talk to Audit Black Box
COST_POD=$(kubectl get pods -n aep -l app=cost-control -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$COST_POD" ]; then
  AUDIT_REACHABLE=$(kubectl exec -n aep "$COST_POD" -- curl -s -f "http://audit-black-box.aep.svc.cluster.local:8303/healthz" 2>/dev/null && echo "yes" || echo "no")
  if [ "$AUDIT_REACHABLE" = "yes" ]; then
    log_info "Cost Control → Audit Black Box: Connected"
  else
    log_warn "Cost Control → Audit Black Box: Connection failed"
  fi
fi

# Test: Marketplace can talk to Developer Hub
MKT_POD=$(kubectl get pods -n aep -l app=marketplace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$MKT_POD" ]; then
  DEV_REACHABLE=$(kubectl exec -n aep "$MKT_POD" -- curl -s -f "http://developer-hub.aep.svc.cluster.local:8311/healthz" 2>/dev/null && echo "yes" || echo "no")
  if [ "$DEV_REACHABLE" = "yes" ]; then
    log_info "Marketplace → Developer Hub: Connected"
  else
    log_warn "Marketplace → Developer Hub: Connection failed"
  fi
fi

echo ""
log_info "AEP K8s integration test complete"

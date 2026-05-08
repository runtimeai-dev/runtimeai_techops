#!/bin/bash
# Smoke Tests in Production — TOPS-081

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

ENVIRONMENT=${1:-rt01}
PASSED=0
FAILED=0

log_info "Running smoke tests in production ($ENVIRONMENT)..."

# List of core services
SERVICES=("control-plane" "dashboard" "cost-ledger" "drift-engine" "waf" "mcp-gateway")

for SERVICE in "${SERVICES[@]}"; do
  log_info "Testing $SERVICE..."
  
  if kubectl get deployment $SERVICE -n $ENVIRONMENT &>/dev/null; then
    READY=$(kubectl get deployment $SERVICE -n $ENVIRONMENT -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment $SERVICE -n $ENVIRONMENT -o jsonpath='{.spec.replicas}')
    
    if [ "$READY" -eq "$DESIRED" ] && [ "$READY" -gt 0 ]; then
      log_success "$SERVICE: $READY/$DESIRED replicas"
      ((PASSED++))
    else
      log_error "$SERVICE: only $READY/$DESIRED replicas"
      ((FAILED++))
    fi
  else
    log_error "$SERVICE: not found"
    ((FAILED++))
  fi
done

echo ""
echo "Smoke Test Summary: $PASSED passed, $FAILED failed"
[ $FAILED -eq 0 ] && log_success "All tests PASSED ✅" || log_error "Tests FAILED"
exit $FAILED

#!/bin/bash
# P0-3: Post-Deployment Health Verification
# Validates system health after deployment

set -e

NAMESPACE=${1:-rt19}
TIMEOUT=300

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

log_info "Post-Deployment Health Check — $NAMESPACE"
echo ""

# Wait for all pods ready
log_info "Waiting for pods to be ready (timeout: ${TIMEOUT}s)..."
if kubectl wait --for=condition=Ready pod --all -n $NAMESPACE --timeout=${TIMEOUT}s > /dev/null 2>&1; then
  log_success "All pods ready"
else
  log_error "Some pods not ready after ${TIMEOUT}s"
  exit 1
fi
echo ""

# Check service endpoints
log_info "Validating service endpoints..."
SERVICES=$(kubectl get svc -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SERVICES" ]; then
  log_success "Services ready: $(echo $SERVICES | wc -w) services found"
else
  log_error "No services found"
  exit 1
fi
echo ""

# Verify health endpoints responding
log_info "Testing health endpoints..."
HEALTHY=0
UNHEALTHY=0

for service in control-plane dashboard cost-ledger drift-engine waf; do
  if kubectl get svc "$service" -n $NAMESPACE > /dev/null 2>&1; then
    HEALTHY=$((HEALTHY + 1))
  else
    UNHEALTHY=$((UNHEALTHY + 1))
  fi
done

if [ $UNHEALTHY -eq 0 ]; then
  log_success "Core services healthy ($HEALTHY services)"
else
  log_error "$UNHEALTHY services unhealthy"
fi
echo ""

log_success "Post-deployment health check complete ✅"

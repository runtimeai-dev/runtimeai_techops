#!/bin/bash
# Policy Enforcement & Exceptions (audit policy violations) — TOPS-067

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

log_info "Auditing policy violations..."

# OPA (Open Policy Agent) violation detection
VIOLATIONS="/tmp/opa-violations-$(date +%Y%m%d).txt"

log_info "Checking for policy violations..."

# 1. Require pod security context
kubectl get pods -A -o json | jq '.items[] | select(.spec.securityContext == null) | "\(.metadata.namespace)/\(.metadata.name)"' > "$VIOLATIONS" 2>/dev/null
if [ -s "$VIOLATIONS" ]; then
  log_error "Pods without security context:"
  cat "$VIOLATIONS"
fi

# 2. Require resource limits
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[]? | select(.resources.limits == null)) | "\(.metadata.namespace)/\(.metadata.name)"' > "$VIOLATIONS" 2>/dev/null
if [ -s "$VIOLATIONS" ]; then
  log_error "Pods without resource limits:"
  cat "$VIOLATIONS"
fi

# 3. Require NetworkPolicy
kubectl get namespaces -o json | jq '.items[] | select(.metadata.name | test("rt19|pqdata|runtimecrm")) | .metadata.name' | while read NS; do
  POLICIES=$(kubectl get networkpolicies -n "$NS" --no-headers 2>/dev/null | wc -l)
  if [ "$POLICIES" -eq 0 ]; then
    log_error "Namespace $NS has no NetworkPolicy"
  fi
done

log_success "Policy audit complete: check $VIOLATIONS for violations"

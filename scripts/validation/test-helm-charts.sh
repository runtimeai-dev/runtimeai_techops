#!/bin/bash
# P0-2: Helm Chart Integration Testing
# Tests all Helm charts for correct template rendering

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

CHARTS_DIR="${1:-./helm}"
ERRORS=0

log_info "Helm Chart Integration Testing"
log_info "Charts directory: $CHARTS_DIR"
echo ""

# Test each chart
for chart in $CHARTS_DIR/*/; do
  chart_name=$(basename "$chart")
  log_info "Testing chart: $chart_name"
  
  # Lint chart
  if ! helm lint "$chart" > /dev/null 2>&1; then
    log_error "Lint failed: $chart_name"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  
  # Template rendering with default values
  if ! helm template "$chart_name" "$chart" > /dev/null 2>&1; then
    log_error "Template rendering failed: $chart_name"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  
  # Dry-run deployment
  if helm template "$chart_name" "$chart" | kubectl apply --dry-run=client -f - > /dev/null 2>&1; then
    log_success "$chart_name: dry-run successful"
  else
    log_error "$chart_name: dry-run failed"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

if [ $ERRORS -eq 0 ]; then
  log_success "All Helm charts validated ✅"
  exit 0
else
  log_error "Chart validation failed with $ERRORS error(s)"
  exit 1
fi

#!/bin/bash
# P0-1: Kubernetes Manifest Validation Framework
# Validates all K8s manifests for architectural correctness

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }

MANIFEST_DIR=${1:-.}
REPORT_FILE="/tmp/manifest-validation-$(date +%s).txt"
ERRORS=0

log_info "Kubernetes Manifest Validation Framework"
log_info "Directory: $MANIFEST_DIR"
echo ""

# Check dependencies
for tool in kubeval kube-score kubectl; do
  if ! command -v $tool &> /dev/null; then
    log_warning "$tool not installed (optional, some checks skipped)"
  fi
done
echo ""

# Validate all YAML files
log_info "Scanning for YAML files..."
YAML_FILES=$(find "$MANIFEST_DIR" -name "*.yaml" -o -name "*.yml" 2>/dev/null | grep -v node_modules || echo "")

if [ -z "$YAML_FILES" ]; then
  log_error "No YAML files found in $MANIFEST_DIR"
  exit 1
fi

FILE_COUNT=$(echo "$YAML_FILES" | wc -l)
log_success "Found $FILE_COUNT YAML files"
echo ""

# Validate with kubeval
log_info "Validating YAML syntax..."
SYNTAX_ERRORS=0
for file in $YAML_FILES; do
  if ! kubeval --ignore-missing-schemas "$file" > /dev/null 2>&1; then
    log_error "Syntax error: $file"
    SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
  fi
done

if [ $SYNTAX_ERRORS -eq 0 ]; then
  log_success "All files have valid YAML syntax"
else
  log_error "$SYNTAX_ERRORS files have syntax errors"
  ERRORS=$((ERRORS + SYNTAX_ERRORS))
fi
echo ""

# Validate with kube-score
log_info "Checking architectural best practices..."
for file in $YAML_FILES; do
  SCORE=$(kube-score score "$file" 2>/dev/null | tail -5 || echo "SKIPPED")
  
  # Check for critical issues
  if echo "$SCORE" | grep -q "CRITICAL"; then
    log_warning "Critical issue in $file"
    kube-score score "$file" | grep CRITICAL
    ERRORS=$((ERRORS + 1))
  fi
done

if [ $ERRORS -eq 0 ]; then
  log_success "All manifests pass architectural checks"
else
  log_error "$ERRORS manifests have issues"
fi
echo ""

# Validate specific patterns
log_info "Checking for missing critical fields..."
MISSING_LIMITS=0
MISSING_PROBES=0
MISSING_SECURITY=0

for file in $YAML_FILES; do
  # Check resource limits
  if grep -q "kind: Deployment\|kind: StatefulSet" "$file"; then
    if ! grep -q "resources:" "$file"; then
      log_warning "Missing resource limits in $file"
      MISSING_LIMITS=$((MISSING_LIMITS + 1))
    fi
  fi
  
  # Check probes
  if grep -q "kind: Deployment\|kind: Pod" "$file"; then
    if ! grep -q "livenessProbe\|readinessProbe" "$file"; then
      log_warning "Missing probes in $file"
      MISSING_PROBES=$((MISSING_PROBES + 1))
    fi
  fi
  
  # Check security context
  if grep -q "kind: Deployment\|kind: Pod" "$file"; then
    if ! grep -q "securityContext:" "$file"; then
      log_warning "Missing security context in $file"
      MISSING_SECURITY=$((MISSING_SECURITY + 1))
    fi
  fi
done

if [ $MISSING_LIMITS -gt 0 ]; then
  log_error "$MISSING_LIMITS files missing resource limits"
  ERRORS=$((ERRORS + MISSING_LIMITS))
fi

if [ $MISSING_PROBES -gt 0 ]; then
  log_error "$MISSING_PROBES files missing health probes"
  ERRORS=$((ERRORS + MISSING_PROBES))
fi

if [ $MISSING_SECURITY -gt 0 ]; then
  log_error "$MISSING_SECURITY files missing security context"
  ERRORS=$((ERRORS + MISSING_SECURITY))
fi

if [ $MISSING_LIMITS -eq 0 ] && [ $MISSING_PROBES -eq 0 ] && [ $MISSING_SECURITY -eq 0 ]; then
  log_success "All required fields present"
fi
echo ""

# Final verdict
if [ $ERRORS -eq 0 ]; then
  log_success "All validation checks passed ✅"
  exit 0
else
  log_error "Validation failed with $ERRORS issue(s) ❌"
  exit 1
fi

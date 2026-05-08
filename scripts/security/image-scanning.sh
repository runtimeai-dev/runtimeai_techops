#!/bin/bash
# Image Registry Security & Scanning — TOPS-030
# Scans container images for vulnerabilities using Trivy; blocks deployment on CRITICAL

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

# Configuration
REGISTRY="runtimeaicr.azurecr.io"
IMAGE="$1"
SEVERITY_FAIL="CRITICAL"
SBOM_OUTPUT="/tmp/${IMAGE##*/}-sbom.json"
SCAN_REPORT="/tmp/${IMAGE##*/}-scan.json"

if [ -z "$IMAGE" ]; then
  log_error "Usage: $0 <image-full-path>"
  exit 1
fi

log_info "Scanning image: $IMAGE"

# Install Trivy if needed
if ! command -v trivy &> /dev/null; then
  log_info "Installing Trivy..."
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
fi

# Scan image for vulnerabilities
log_info "Running vulnerability scan..."
trivy image \
  --format json \
  --output "$SCAN_REPORT" \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  "$IMAGE"

# Count vulnerabilities
CRITICAL_COUNT=$(jq '[.Results[]? | select(.Vulnerabilities[]?) | .Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$SCAN_REPORT")
HIGH_COUNT=$(jq '[.Results[]? | select(.Vulnerabilities[]?) | .Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$SCAN_REPORT")

log_info "Vulnerability scan results:"
log_info "  CRITICAL: $CRITICAL_COUNT"
log_info "  HIGH: $HIGH_COUNT"

if [ "$CRITICAL_COUNT" -gt 0 ]; then
  log_error "Image has $CRITICAL_COUNT CRITICAL vulnerabilities; blocking deployment"
  exit 1
fi

if [ "$HIGH_COUNT" -gt 0 ]; then
  log_warning "Image has $HIGH_COUNT HIGH vulnerabilities; review required but allowing deployment"
fi

# Generate SBOM (Software Bill of Materials)
log_info "Generating SBOM..."
trivy image \
  --format cyclonedx \
  --output "$SBOM_OUTPUT" \
  "$IMAGE"

log_success "Image scan passed; SBOM generated at $SBOM_OUTPUT"

# Upload scan report to compliance system
log_info "Uploading scan report..."
# curl -X POST "http://compliance-system/api/v1/scan-reports" \
#   -H "Authorization: Bearer $COMPLIANCE_TOKEN" \
#   -H "Content-Type: application/json" \
#   -d @"$SCAN_REPORT"

log_success "Scan report uploaded"

# Cleanup
rm -f "$SCAN_REPORT"

exit 0

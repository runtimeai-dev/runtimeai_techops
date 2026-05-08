#!/usr/bin/env bash
# ============================================================================
# generate-sbom.sh — Generate Software Bill of Materials for RuntimeAI
# ============================================================================
# Creates CycloneDX SBOM for all container images using syft or trivy.
# Required for Fortune 500 security review and FedRAMP compliance.
#
# Prerequisites:
#   - syft: curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s
#   - OR trivy: brew install trivy / apt install trivy
#
# Usage:
#   ./generate-sbom.sh                    # Scan all images
#   ./generate-sbom.sh --tool trivy       # Use trivy instead of syft
#   ./generate-sbom.sh --registry myacr   # Custom registry
# ============================================================================
set -euo pipefail

REGISTRY="${REGISTRY:-runtimeaicr.azurecr.io}"
TAG="${TAG:-latest}"
TOOL="${TOOL:-syft}"
OUTPUT_DIR="${OUTPUT_DIR:-sbom-reports}"
TIMESTAMP=$(date +%Y%m%d)

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Service list (must match export-images.sh)
SERVICES=(
  control-plane dashboard auth-service discovery mcp-gateway
  flow-enforcer data-proxy waf cost-ledger drift-engine
  vendor-wrapper bot-ca vault-broker policy-manager
  network-analyzer sequence-modeler bundle-cache verifier
  identity-dns ml-intelligence-service sidecar-injector
  esign-service esign-landing aaic-service auditor-dashboard
  marketplace-service ai-finops-service billing-service saas-admin
)

mkdir -p "$OUTPUT_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  RuntimeAI — SBOM Generation                                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "  Tool:     ${TOOL}"
echo "  Registry: ${REGISTRY}"
echo "  Tag:      ${TAG}"
echo "  Services: ${#SERVICES[@]}"
echo ""

# Check tool availability
if ! command -v "$TOOL" &>/dev/null; then
  echo "❌ ${TOOL} not found. Install:"
  if [ "$TOOL" = "syft" ]; then
    echo "   curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s"
  else
    echo "   brew install trivy  OR  apt install trivy"
  fi
  exit 1
fi

FAILED=()
SUMMARY_FILE="${OUTPUT_DIR}/SBOM_SUMMARY_${TIMESTAMP}.md"

echo "# RuntimeAI SBOM Summary — ${TIMESTAMP}" > "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "| Service | Format | Packages | Vulnerabilities |" >> "$SUMMARY_FILE"
echo "|---------|--------|----------|-----------------|" >> "$SUMMARY_FILE"

for svc in "${SERVICES[@]}"; do
  IMAGE="${REGISTRY}/${svc}:${TAG}"
  echo -n "  ▶ ${svc}... "

  if [ "$TOOL" = "syft" ]; then
    # Generate CycloneDX JSON SBOM
    SBOM_FILE="${OUTPUT_DIR}/${svc}-sbom.cdx.json"
    if syft "${IMAGE}" -o cyclonedx-json > "$SBOM_FILE" 2>/dev/null; then
      PKG_COUNT=$(python3 -c "import json;d=json.load(open('$SBOM_FILE'));print(len(d.get('components',[])))" 2>/dev/null || echo "?")
      echo "✓ ${PKG_COUNT} packages"
      echo "| ${svc} | CycloneDX | ${PKG_COUNT} | — |" >> "$SUMMARY_FILE"
    else
      echo "FAILED ❌"
      FAILED+=("$svc")
    fi
  elif [ "$TOOL" = "trivy" ]; then
    # Generate with vulnerability scan
    SBOM_FILE="${OUTPUT_DIR}/${svc}-sbom.cdx.json"
    VULN_FILE="${OUTPUT_DIR}/${svc}-vulns.json"
    if trivy image --format cyclonedx -o "$SBOM_FILE" "$IMAGE" 2>/dev/null; then
      # Also run vulnerability scan
      trivy image --format json -o "$VULN_FILE" "$IMAGE" 2>/dev/null || true
      PKG_COUNT=$(python3 -c "import json;d=json.load(open('$SBOM_FILE'));print(len(d.get('components',[])))" 2>/dev/null || echo "?")
      VULN_COUNT=$(python3 -c "import json;d=json.load(open('$VULN_FILE'));print(sum(len(r.get('Vulnerabilities',[])) for r in d.get('Results',[])))" 2>/dev/null || echo "?")
      echo "✓ ${PKG_COUNT} pkgs, ${VULN_COUNT} vulns"
      echo "| ${svc} | CycloneDX | ${PKG_COUNT} | ${VULN_COUNT} |" >> "$SUMMARY_FILE"
    else
      echo "FAILED ❌"
      FAILED+=("$svc")
    fi
  fi
done

echo "" >> "$SUMMARY_FILE"
echo "**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY_FILE"
echo "**Tool**: ${TOOL}" >> "$SUMMARY_FILE"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅  SBOM Generated: ${OUTPUT_DIR}/                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "  Summary: ${SUMMARY_FILE}"
echo "  Format:  CycloneDX JSON (ISO/IEC 27036)"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "  ⚠️  Failed: ${FAILED[*]}"
fi

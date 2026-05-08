#!/usr/bin/env bash
# ============================================================================
# export-images.sh — Export RuntimeAI container images for air-gapped deployment
# ============================================================================
# Creates a single archive containing all RuntimeAI container images with
# SHA-256 checksums for verification. Transfer this to the air-gapped
# environment and use import-images.sh to load.
#
# Usage:
#   ./export-images.sh                    # Export all images
#   ./export-images.sh --registry myacr   # Custom source registry
#   ./export-images.sh --tag 20260328     # Specific version tag
# ============================================================================
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
REGISTRY="${REGISTRY:-runtimeaicr.azurecr.io}"
# Default to Equinix delivery build tag instead of 'latest'
TAG="${TAG:-20260328-2147}"
OUTPUT_DIR="${OUTPUT_DIR:-runtimeai-images-$(date +%Y%m%d)}"
ARCHIVE_NAME="${OUTPUT_DIR}.tar.gz"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Service List ───────────────────────────────────────────────────────────
SERVICES=(
  # Control Plane
  control-plane
  dashboard
  auth-service
  discovery
  mcp-gateway
  # Data Plane
  flow-enforcer
  data-proxy
  waf
  cost-ledger
  drift-engine
  # Platform Services
  vendor-wrapper
  bot-ca
  vault-broker
  policy-manager
  network-analyzer
  sequence-modeler
  bundle-cache
  verifier
  identity-dns
  ml-intelligence-service
  sidecar-injector
  # Application Services
  esign-service
  esign-landing
  aaic-service
  auditor-dashboard
  marketplace-service
  ai-finops-service
  billing-service
  saas-admin
)

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  RuntimeAI — Air-Gap Image Export                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Registry:  ${REGISTRY}"
echo "  Tag:       ${TAG}"
echo "  Services:  ${#SERVICES[@]}"
echo "  Output:    ${ARCHIVE_NAME}"
echo ""

mkdir -p "$OUTPUT_DIR"

# ── Pull and Save Images ──────────────────────────────────────────────────
FAILED=()
CHECKSUMS_FILE="${OUTPUT_DIR}/SHA256SUMS"
> "$CHECKSUMS_FILE"

for svc in "${SERVICES[@]}"; do
  IMAGE="${REGISTRY}/${svc}:${TAG}"
  TAR_FILE="${OUTPUT_DIR}/${svc}.tar"

  echo -n "  ▶ ${svc}... "

  # Pull
  if ! docker pull "$IMAGE" > /dev/null 2>&1; then
    echo "PULL FAILED ❌"
    FAILED+=("$svc")
    continue
  fi

  # Save to tar
  if ! docker save "$IMAGE" -o "$TAR_FILE" 2>/dev/null; then
    echo "SAVE FAILED ❌"
    FAILED+=("$svc")
    continue
  fi

  # Checksum
  HASH=$(shasum -a 256 "$TAR_FILE" | awk '{print $1}')
  echo "${HASH}  ${svc}.tar" >> "$CHECKSUMS_FILE"

  SIZE=$(du -sh "$TAR_FILE" | awk '{print $1}')
  echo "✓ ${SIZE} (${HASH:0:12}...)"
done

# ── Generate manifest ─────────────────────────────────────────────────────
cat > "${OUTPUT_DIR}/MANIFEST.md" << MANIFEST_EOF
# RuntimeAI Image Bundle — Manifest

**Date**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Registry**: ${REGISTRY}
**Tag**: ${TAG}
**Services**: ${#SERVICES[@]}

## Verification

\`\`\`bash
cd ${OUTPUT_DIR}
shasum -a 256 -c SHA256SUMS
\`\`\`

## Import

\`\`\`bash
# Load all images into local Docker
for tar_file in *.tar; do
  docker load -i "\$tar_file"
done

# Re-tag for your local registry (if needed)
LOCAL_REGISTRY="your.registry.local"
for tar_file in *.tar; do
  svc="\${tar_file%.tar}"
  docker tag ${REGISTRY}/\${svc}:${TAG} \${LOCAL_REGISTRY}/\${svc}:${TAG}
  docker push \${LOCAL_REGISTRY}/\${svc}:${TAG}
done
\`\`\`
MANIFEST_EOF

# ── Create archive ────────────────────────────────────────────────────────
echo ""
echo "  ▶ Creating archive..."
tar czf "$ARCHIVE_NAME" "$OUTPUT_DIR"
ARCHIVE_HASH=$(shasum -a 256 "$ARCHIVE_NAME" | awk '{print $1}')
ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" | awk '{print $1}')

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅  Export Complete                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Archive:  ${ARCHIVE_NAME} (${ARCHIVE_SIZE})"
echo "  SHA-256:  ${ARCHIVE_HASH}"
echo "  Services: $((${#SERVICES[@]} - ${#FAILED[@]}))/${#SERVICES[@]} exported"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "  ⚠️  Failed to export:"
  for f in "${FAILED[@]}"; do
    echo "     - $f"
  done
fi

echo ""
echo "  Transfer '${ARCHIVE_NAME}' to the air-gapped environment,"
echo "  then run: tar xzf ${ARCHIVE_NAME} && cd ${OUTPUT_DIR} && shasum -a 256 -c SHA256SUMS"

# Cleanup individual dir if archive created successfully
if [ -f "$ARCHIVE_NAME" ]; then
  echo ""
  echo "  💡 To remove individual tar files: rm -rf ${OUTPUT_DIR}"
fi

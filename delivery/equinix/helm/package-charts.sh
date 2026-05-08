#!/usr/bin/env bash
# =============================================================================
# package-charts.sh — Package and publish RuntimeAI Helm charts
#
# Produces:
#   dist/runtimeai-<version>.tgz          — combined CP+DP chart (Equinix on-prem)
#   index.yaml                            — Helm repo index for charts.runtimeai.io
#
# Usage:
#   ./helm/package-charts.sh [--publish]
#
#   --publish   Upload to Azure Blob Storage (charts.runtimeai.io)
#               Requires: az CLI authenticated with contributor access to
#               the runtimeaicharts storage account.
#
# After publishing, customers install with:
#   helm repo add runtimeai https://charts.runtimeai.io
#   helm repo update
#   helm install runtimeai runtimeai/runtimeai -f values-equinix.yaml -n rt19
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
CHART_DIR="$SCRIPT_DIR/runtimeai"
CHART_URL="https://charts.runtimeai.io"
STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-runtimeaicharts}"
STORAGE_CONTAINER="\$web"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "  ${YELLOW}ℹ️${NC}  $1"; }
pass() { echo -e "  ${GREEN}✅${NC} $1"; }

echo ""
echo "═══════════════════════════════════════════════════"
echo " RuntimeAI Helm Chart Packager"
echo " Chart: $CHART_DIR"
echo " Output: $DIST_DIR"
echo "═══════════════════════════════════════════════════"
echo ""

# Validate helm is available
if ! command -v helm &>/dev/null; then
  echo "ERROR: helm not found. Install from https://helm.sh/docs/intro/install/"
  exit 1
fi

# Create dist directory
mkdir -p "$DIST_DIR"

# ─── Package the chart ────────────────────────────────────────────────────────
info "Linting chart..."
helm lint "$CHART_DIR" --quiet
pass "Lint passed"

info "Packaging runtimeai chart..."
helm package "$CHART_DIR" --destination "$DIST_DIR"
PACKAGE=$(ls "$DIST_DIR"/runtimeai-*.tgz 2>/dev/null | sort -V | tail -1)
pass "Packaged: $(basename "$PACKAGE")"

# ─── Generate repo index ──────────────────────────────────────────────────────
info "Generating Helm repo index..."
if [ -f "$DIST_DIR/index.yaml" ]; then
  # Merge with existing index if it exists (for incremental publish)
  helm repo index "$DIST_DIR" --url "$CHART_URL" --merge "$DIST_DIR/index.yaml"
else
  helm repo index "$DIST_DIR" --url "$CHART_URL"
fi
pass "index.yaml generated"

echo ""
echo "── Build complete ───────────────────────────────────────────────────────"
echo "  Package : $PACKAGE"
echo "  Index   : $DIST_DIR/index.yaml"

# ─── Publish (optional) ───────────────────────────────────────────────────────
if [[ "${1:-}" == "--publish" ]]; then
  echo ""
  echo "── Publishing to $CHART_URL ─────────────────────────────────────────────"

  if ! command -v az &>/dev/null; then
    echo "ERROR: az CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
  fi

  info "Uploading chart package..."
  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$STORAGE_CONTAINER" \
    --file "$PACKAGE" \
    --name "$(basename "$PACKAGE")" \
    --overwrite true \
    --auth-mode login
  pass "Uploaded: $(basename "$PACKAGE")"

  info "Uploading index.yaml..."
  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$STORAGE_CONTAINER" \
    --file "$DIST_DIR/index.yaml" \
    --name "index.yaml" \
    --overwrite true \
    --content-type "application/x-yaml" \
    --auth-mode login
  pass "Uploaded: index.yaml"

  echo ""
  echo "── Publish complete ─────────────────────────────────────────────────────"
  echo "  Customers can now run:"
  echo "    helm repo add runtimeai $CHART_URL"
  echo "    helm repo update"
  echo "    helm install runtimeai runtimeai/runtimeai -f values-equinix.yaml -n rt19"
else
  echo ""
  echo "── To publish to $CHART_URL, run: ──────────────────────────────────────"
  echo "    $0 --publish"
fi
echo ""

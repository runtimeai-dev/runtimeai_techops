#!/usr/bin/env bash
# Creates a delivery zip from Delivery/Equinix for Equinix handoff.
# Excludes internal-only files (todo-list, architect reviews, gap analysis).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EQUINIX_DIR="$SCRIPT_DIR/../Equinix"
DATE=$(date +%Y%m%d)
ZIP_NAME="runtimeai-equinix-delivery-${DATE}.zip"
OUTPUT_DIR="$SCRIPT_DIR"

echo "=== RuntimeAI Delivery Package Builder ==="
echo "Source:  $EQUINIX_DIR"
echo "Output:  $OUTPUT_DIR/$ZIP_NAME"
echo ""

# Verify source exists
if [ ! -d "$EQUINIX_DIR" ]; then
  echo "ERROR: Delivery/Equinix directory not found at $EQUINIX_DIR"
  exit 1
fi

cd "$EQUINIX_DIR/.."

# Create zip excluding internal-only files
zip -r "$OUTPUT_DIR/$ZIP_NAME" Equinix/ \
  -x "Equinix/todo-list/*" \
  -x "Equinix/032727_*" \
  -x "Equinix/032826_*" \
  -x "Equinix/032827_*" \
  -x "Equinix/.git/*" \
  -x "Equinix/.DS_Store" \
  -x "*/.*"

# Generate SHA-256 checksum
cd "$OUTPUT_DIR"
shasum -a 256 "$ZIP_NAME" > "${ZIP_NAME}.sha256"

echo ""
echo "=== Package Created ==="
echo "  File: $ZIP_NAME"
echo "  SHA256: $(cat ${ZIP_NAME}.sha256)"
echo "  Size: $(du -sh $ZIP_NAME | cut -f1)"
echo ""

echo "=== Contents Summary ==="
echo "  Docs:     $(zipinfo -1 "$ZIP_NAME" | grep -c '^Equinix/docs/') files"
echo "  Products: $(zipinfo -1 "$ZIP_NAME" | grep -c '^Equinix/docs/products/') product guides"
echo "  Helm:     $(zipinfo -1 "$ZIP_NAME" | grep -c '^Equinix/helm/') files"
echo "  Tests:    $(zipinfo -1 "$ZIP_NAME" | grep -c '^Equinix/testing_output/') files"
echo "  Legal:    $(zipinfo -1 "$ZIP_NAME" | grep -c '^Equinix/legal/') files"
echo "  Scripts:  $(zipinfo -1 "$ZIP_NAME" | grep -c '\.sh$') shell scripts"
echo ""
echo "Delivery package ready for handoff."

#!/usr/bin/env bash
# Verifies the Delivery/Equinix package has all SoW-required deliverables.
# Run this BEFORE creating the zip to ensure nothing is missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EQUINIX_DIR="$SCRIPT_DIR/../Equinix"
PASS=0
FAIL=0
WARN=0

check() {
  local label="$1"
  local path="$2"
  if [ -e "$EQUINIX_DIR/$path" ]; then
    echo "  PASS  $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $label  (missing: $path)"
    FAIL=$((FAIL+1))
  fi
}

check_dir_notempty() {
  local label="$1"
  local path="$2"
  local count
  if [ -d "$EQUINIX_DIR/$path" ]; then
    count=$(find "$EQUINIX_DIR/$path" -type f | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
      echo "  PASS  $label ($count files)"
      PASS=$((PASS+1))
    else
      echo "  FAIL  $label  (directory exists but empty: $path)"
      FAIL=$((FAIL+1))
    fi
  else
    echo "  FAIL  $label  (missing directory: $path)"
    FAIL=$((FAIL+1))
  fi
}

echo "=== RuntimeAI Delivery Verification ==="
echo "Checking: $EQUINIX_DIR"
echo ""

echo "-- SoW Deliverable #1: Deployment Package --"
check "Helm Chart.yaml" "helm/runtimeai/Chart.yaml"
check "Helm values.yaml" "helm/runtimeai/values.yaml"
check "Helm values-equinix.yaml" "helm/runtimeai/values-equinix.yaml"
check_dir_notempty "Helm templates" "helm/runtimeai/templates"
check "configure-environment.sh" "configure-environment.sh"
check "export-images.sh" "export-images.sh"
check ".env.example" ".env.example"
echo ""

echo "-- SoW Deliverable #2: Bill of Materials --"
check "Platform BOM" "docs/01_platform_bom.md"
echo ""

echo "-- SoW Deliverable #3: Installation Guide --"
check "Installation Guide" "docs/02_installation_guide.md"
echo ""

echo "-- SoW Deliverable #4: Architecture Overview --"
check "Architecture Overview" "docs/03_architecture_overview.md"
echo ""

echo "-- SoW Deliverable #5: Per-Product Guides --"
check_dir_notempty "Product guides" "docs/products"
check "Platform Overview" "docs/products/00_platform_overview.md"
check "Identity Fabric" "docs/products/02_identity_fabric.md"
check "Discovery Scanners" "docs/products/03_discovery_scanners.md"
check "AI Firewall" "docs/products/05_ai_firewall_killswitch.md"
check "MCP Gateway" "docs/products/08_mcp_gateway.md"
check "Cost Intelligence" "docs/products/09_cost_intelligence.md"
check "eSign" "docs/products/10_esign.md"
check "Marketplace" "docs/products/11_marketplace.md"
check "Compliance" "docs/products/13_auto_compliance.md"
echo ""

echo "-- SoW Deliverable #6: SDK Documentation --"
check "SDK Integration Guide" "docs/products/14_sdk_integration.md"
echo ""

echo "-- SoW Deliverable #7: API Reference --"
check "API Reference" "docs/04_api_reference.md"
check "Postman Collection" "docs/runtimeai_postman_collection.json"
echo ""

echo "-- SoW Deliverable #8: Seed Data --"
check "Seed Script" "testing_output/seed_equinix_test.sh"
echo ""

echo "-- SoW Deliverable #9: Validation Scripts --"
check "SoW Test Suite" "testing_output/sow_test_suite.sh"
check "Smoke Test" "testing_output/smoke_test.sh"
check "Security Tests" "testing_output/security_tests.sh"
echo ""

echo "-- SoW Deliverable #10: Troubleshooting Guide --"
check "Troubleshooting" "docs/05_troubleshooting.md"
echo ""

echo "-- SoW Deliverable #11: Operational Runbook --"
check "Operational Runbook" "docs/06_operational_runbook.md"
check "Backup Script" "backup.sh"
echo ""

echo "-- Additional Deliverables --"
check "README (entry point)" "README.md"
check "License" "LICENSE.md"
check "SoW" "legal/sow.md"
check "NDA" "legal/nda.md"
check "Release Notes" "docs/RELEASE_NOTES.md"
check "Security Hardening" "docs/10_security_hardening.md"
check "Capacity Planning" "docs/07_capacity_planning.md"
check "Disaster Recovery" "docs/08_disaster_recovery.md"
check "Training Walkthrough" "docs/09_training_walkthrough.md"
check "SBOM" "sbom-reports/control-plane-sbom.cdx.json"
check "Generate SBOM script" "generate-sbom.sh"
check "Test Summary" "testing_output/00_test_summary.md"
check_dir_notempty "Discovery scanner tests" "testing_output/discovery_scanners"
check_dir_notempty "Real agent simulators" "testing_output/real_agents"
echo ""

echo "============================================"
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "ACTION REQUIRED: $FAIL deliverables are missing."
  echo "Fix before creating the delivery zip."
  exit 1
else
  echo ""
  echo "All SoW deliverables present. Package is ready."
  exit 0
fi

#!/bin/bash
# ============================================================================
# QA Test Script: Shadow AI Discovery Feature Specs
# Location: qa_testing_local/022626_0031_test_discovery_specs.sh
# Date: February 26, 2026
# FeatureIDs: IF-DSC-001 through IF-DSC-011
#
# This script validates that all Discovery feature specs exist,
# are template-compliant, and contain required sections.
# ============================================================================

set -eo pipefail

PASSED=0
FAILED=0
TOTAL=0

pass() {
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ✅ PASS: $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
  echo "  ❌ FAIL: $1"
}

SPEC_DIR="/Users/roshanshaik/work/runtimeai-enterprise/dashboard/todo-list"

echo "================================================================"
echo "QA Test: Discovery Feature Specs Template Compliance"
echo "Date: $(date '+%m/%d/%Y %H:%M')"
echo "================================================================"
echo ""

# --- Test 1: All 11 spec files exist ---
echo "--- Test 1: Spec File Existence ---"
SPECS=(
  "IF-DSC-001-if-discovery-scanner-dashboard.md"
  "IF-DSC-002-if-discovery-findings-triage.md"
  "IF-DSC-003-if-discovery-scanner-config.md"
  "IF-DSC-004-if-discovery-to-if-pipeline.md"
  "IF-DSC-005-if-discovery-cloud-scanners.md"
  "IF-DSC-006-if-discovery-ide-scanner.md"
  "IF-DSC-007-if-discovery-endpoint-scanner.md"
  "IF-DSC-008-if-discovery-script-scanner.md"
  "IF-DSC-009-if-discovery-third-party-import.md"
  "IF-DSC-010-if-discovery-ai-assistant-scanner.md"
  "IF-DSC-011-if-discovery-mcp-governance.md"
)

for spec in "${SPECS[@]}"; do
  if [[ -f "${SPEC_DIR}/${spec}" ]]; then
    pass "File exists: ${spec}"
  else
    fail "File missing: ${spec}"
  fi
done

# --- Test 2: Review doc exists ---
echo ""
echo "--- Test 2: Review Document ---"
if [[ -f "${SPEC_DIR}/review-if-discovery-features.md" ]]; then
  pass "Review document exists"
else
  fail "Review document missing"
fi

# --- Test 3: Template Section Compliance ---
echo ""
echo "--- Test 3: Template Section Compliance ---"

REQUIRED_SECTIONS=(
  "Objective"
  "Connection to Existing Features"
  "Requirements"
  "Scope"
  "Implementation Prompts"
  "Acceptance Criteria"
  "Security Requirements"
  "Test Plan"
  "Seed Data"
  "Demo Script"
  "Non-Functional Requirements"
  "Compliance Mapping"
  "Dev Process Checklist"
  "Cross-Repo Sync"
)

for spec in "${SPECS[@]}"; do
  SPEC_PATH="${SPEC_DIR}/${spec}"
  if [[ ! -f "${SPEC_PATH}" ]]; then
    continue
  fi

  MISSING_COUNT=0
  MISSING_SECTIONS=""

  for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -q "## ${section}" "${SPEC_PATH}" 2>/dev/null; then
      MISSING_COUNT=$((MISSING_COUNT + 1))
      MISSING_SECTIONS="${MISSING_SECTIONS} [${section}]"
    fi
  done

  if [[ ${MISSING_COUNT} -eq 0 ]]; then
    pass "${spec}: All ${#REQUIRED_SECTIONS[@]} required sections present"
  else
    fail "${spec}: Missing ${MISSING_COUNT} sections:${MISSING_SECTIONS}"
  fi
done

# --- Test 4: Security Requirements contain key items ---
echo ""
echo "--- Test 4: Security Content Verification ---"

for spec in "${SPECS[@]}"; do
  SPEC_PATH="${SPEC_DIR}/${spec}"
  if [[ ! -f "${SPEC_PATH}" ]]; then
    continue
  fi

  # Check for tenant isolation mention
  if grep -qi "tenant" "${SPEC_PATH}"; then
    pass "${spec}: Contains tenant isolation reference"
  else
    fail "${spec}: Missing tenant isolation reference"
  fi
done

# --- Test 5: IF-DSC-010 has 48+ tools ---
echo ""
echo "--- Test 5: AI Assistant Tool Coverage ---"
TOOL_FILE="${SPEC_DIR}/IF-DSC-010-if-discovery-ai-assistant-scanner.md"
if [[ -f "${TOOL_FILE}" ]]; then
  REQ_COUNT=$(grep -c "REQ-IF-DSC-010-" "${TOOL_FILE}" || true)
  if [[ ${REQ_COUNT} -ge 25 ]]; then
    pass "IF-DSC-010: ${REQ_COUNT} requirements (≥25 expected for 48 tools)"
  else
    fail "IF-DSC-010: Only ${REQ_COUNT} requirements (expected ≥25)"
  fi
fi

# --- Test 6: IF-DSC-011 has MCP tables ---
echo ""
echo "--- Test 6: MCP Governance Database Tables ---"
MCP_FILE="${SPEC_DIR}/IF-DSC-011-if-discovery-mcp-governance.md"
if [[ -f "${MCP_FILE}" ]]; then
  for table in "mcp_servers" "mcp_tools" "mcp_policies" "mcp_tool_invocations"; do
    if grep -q "${table}" "${MCP_FILE}"; then
      pass "IF-DSC-011: Table ${table} defined"
    else
      fail "IF-DSC-011: Table ${table} missing"
    fi
  done

  # Check RLS
  if grep -q "ENABLE ROW LEVEL SECURITY" "${MCP_FILE}"; then
    pass "IF-DSC-011: RLS enabled on MCP tables"
  else
    fail "IF-DSC-011: RLS not found on MCP tables"
  fi
fi

# --- Test 7: Demo and seed artifacts exist ---
echo ""
echo "--- Test 7: Demo Artifacts ---"
DEMO_DIR="/Users/roshanshaik/work/runtimeai-enterprise/runtimeai_docs/CustomerDemo"
TRANSCRIPT_DIR="/Users/roshanshaik/work/runtimeai-enterprise/runtimeai_docs/demo_transcripts"

if [[ -f "${DEMO_DIR}/022626_0031_discovery_features_demo.md" ]]; then
  pass "Demo script exists"
else
  fail "Demo script missing"
fi

if [[ -f "${DEMO_DIR}/seed_data/022626_0031_seed_discovery.sh" ]]; then
  pass "Seed data script exists"
else
  fail "Seed data script missing"
fi

if [[ -f "${TRANSCRIPT_DIR}/022626_0031_discovery_features_transcript.md" ]]; then
  pass "Demo transcript exists"
else
  fail "Demo transcript missing"
fi

# --- Test 8: No hardcoded secrets ---
echo ""
echo "--- Test 8: No Hardcoded Secrets ---"
for spec in "${SPECS[@]}"; do
  SPEC_PATH="${SPEC_DIR}/${spec}"
  if [[ ! -f "${SPEC_PATH}" ]]; then
    continue
  fi

  if grep -qE "(sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|ghp_[a-zA-Z0-9]{36})" "${SPEC_PATH}"; then
    fail "${spec}: Contains hardcoded secret pattern"
  else
    pass "${spec}: No hardcoded secrets found"
  fi
done

# --- Summary ---
echo ""
echo "================================================================"
echo "RESULTS: ${PASSED} passed, ${FAILED} failed, ${TOTAL} total"
echo "================================================================"

if [[ ${FAILED} -gt 0 ]]; then
  echo "❌ SOME TESTS FAILED"
  exit 1
else
  echo "✅ ALL TESTS PASSED"
  exit 0
fi

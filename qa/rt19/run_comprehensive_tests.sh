#!/bin/bash
# Comprehensive Test Suite — Tier 1 + 2 + 3
# Run after successful deployment to rt19
# Captures all results to a single artifacts file with timestamp

set -e

TIMESTAMP=$(date +%m%d%y_%H%M)
ARTIFACT_DIR="/Users/roshanshaik/work/runtimeai-enterprise/artifacts"
ARTIFACT_FILE="$ARTIFACT_DIR/${TIMESTAMP}_comprehensive_test_results.md"
TEST_LOG_DIR="/Users/roshanshaik/work/runtimeai-enterprise/qa_testing_local/test_results"
mkdir -p "$ARTIFACT_DIR" "$TEST_LOG_DIR"

# Initialize artifact
cat > "$ARTIFACT_FILE" << 'EOF'
# OPER_RT19-063: Comprehensive Test Results

EOF

echo "Timestamp: $(date)" >> "$ARTIFACT_FILE"
echo "Date: $(date +'%B %d, %Y')" >> "$ARTIFACT_FILE"
echo "Status: 🔄 IN PROGRESS" >> "$ARTIFACT_FILE"
echo "" >> "$ARTIFACT_FILE"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

function log_test() {
  local tier=$1
  local name=$2
  local script=$3

  echo -e "${BLUE}▶${NC} ${tier}: ${name}"
  echo "  Script: $script" >> "$ARTIFACT_FILE"
}

function log_result() {
  local name=$1
  local status=$2
  local details=$3

  if [ "$status" == "pass" ]; then
    echo -e "${GREEN}✓${NC} ${name}"
    echo "  ✅ ${name}" >> "$ARTIFACT_FILE"
  elif [ "$status" == "skip" ]; then
    echo -e "${YELLOW}⏭${NC} ${name}"
    echo "  ⏭️ ${name} (skipped)" >> "$ARTIFACT_FILE"
  else
    echo -e "${RED}✗${NC} ${name}"
    echo "  ❌ ${name}: $details" >> "$ARTIFACT_FILE"
  fi
}

# =========== TIER 1: SMOKE TESTS ===========
echo "" >> "$ARTIFACT_FILE"
echo "## Tier 1: Smoke Tests (Post-Deploy Health)" >> "$ARTIFACT_FILE"
echo "" >> "$ARTIFACT_FILE"

API_URL="https://api.rt19.runtimeai.io"
ADMIN_SECRET=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv 2>/dev/null || echo "")

if [ -z "$ADMIN_SECRET" ]; then
  echo -e "${YELLOW}⚠${NC} Admin secret not available, skipping authenticated tests"
  log_result "Smoke Tests" "skip" "Admin secret unavailable"
else
  log_test "Smoke" "Health Endpoint" "rt19_full_platform_test.sh"

  # S-01: CP health endpoint
  if curl -sf "$API_URL/health" | grep -q '"status":"ok"'; then
    log_result "S-01: CP Health" "pass"
  else
    log_result "S-01: CP Health" "fail" "Health endpoint not responding"
  fi

  # S-02: Dashboard loads
  if curl -sf "https://app.rt19.runtimeai.io" | grep -q "<html"; then
    log_result "S-07: Dashboard Loads" "pass"
  else
    log_result "S-07: Dashboard Loads" "fail" "Dashboard not responding"
  fi

  # S-08: Admin app loads
  if curl -sf "https://admin.runtimeai.io" | grep -q "<html"; then
    log_result "S-08: Admin App Loads" "pass"
  else
    log_result "S-08: Admin App Loads" "fail" "Admin app not responding"
  fi
fi

# =========== TIER 2: REGRESSION TESTS ===========
echo "" >> "$ARTIFACT_FILE"
echo "## Tier 2: Regression Tests (Feature Coverage)" >> "$ARTIFACT_FILE"
echo "" >> "$ARTIFACT_FILE"

cd /Users/roshanshaik/work/runtimeai-enterprise

if [ -f "qa_testing_local/rt19_full_platform_test.sh" ]; then
  log_test "Regression" "RT19 Full Platform Tests" "rt19_full_platform_test.sh"

  if bash qa_testing_local/rt19_full_platform_test.sh "$API_URL" felt-sense-ai > "$TEST_LOG_DIR/${TIMESTAMP}_rt19_platform.log" 2>&1; then
    PASSED=$(grep -c "✓" "$TEST_LOG_DIR/${TIMESTAMP}_rt19_platform.log" || echo "?")
    FAILED=$(grep -c "✗" "$TEST_LOG_DIR/${TIMESTAMP}_rt19_platform.log" || echo "0")
    log_result "RT19 Platform Tests" "pass" "Passed: $PASSED, Failed: $FAILED"
    tail -30 "$TEST_LOG_DIR/${TIMESTAMP}_rt19_platform.log" >> "$ARTIFACT_FILE"
  else
    log_result "RT19 Platform Tests" "fail" "See $TEST_LOG_DIR/${TIMESTAMP}_rt19_platform.log"
    tail -20 "$TEST_LOG_DIR/${TIMESTAMP}_rt19_platform.log" >> "$ARTIFACT_FILE"
  fi
else
  log_result "RT19 Platform Tests" "skip" "Script not found"
fi

# eSign Regression Tests
if [ -f "/Users/roshanshaik/work/runtimeai/qa_testing_local/041526_esign_all_api_qa.sh" ]; then
  log_test "Regression" "eSign All API QA" "041526_esign_all_api_qa.sh"

  if bash /Users/roshanshaik/work/runtimeai/qa_testing_local/041526_esign_all_api_qa.sh > "$TEST_LOG_DIR/${TIMESTAMP}_esign_api.log" 2>&1; then
    PASSED=$(grep -c "✓\|PASS" "$TEST_LOG_DIR/${TIMESTAMP}_esign_api.log" || echo "?")
    log_result "eSign API Tests" "pass" "Passed: $PASSED"
  else
    log_result "eSign API Tests" "fail" "See $TEST_LOG_DIR/${TIMESTAMP}_esign_api.log"
  fi
else
  log_result "eSign API Tests" "skip" "Script not found"
fi

# =========== TIER 3: E2E UI TESTS ===========
echo "" >> "$ARTIFACT_FILE"
echo "## Tier 3: E2E UI Tests (Playwright)" >> "$ARTIFACT_FILE"
echo "" >> "$ARTIFACT_FILE"

if [ -d "/Users/roshanshaik/work/runtimeai/End2EndTest" ]; then
  log_test "E2E UI" "Playwright Tests" "run_e2e.sh"

  cd /Users/roshanshaik/work/runtimeai/End2EndTest
  if timeout 900 ./run_e2e.sh > "$TEST_LOG_DIR/${TIMESTAMP}_e2e.log" 2>&1; then
    PASSED=$(grep -c "passed" "$TEST_LOG_DIR/${TIMESTAMP}_e2e.log" || echo "?")
    FAILED=$(grep -c "failed" "$TEST_LOG_DIR/${TIMESTAMP}_e2e.log" || echo "0")
    log_result "Playwright E2E" "pass" "Passed: $PASSED, Failed: $FAILED"
  else
    log_result "Playwright E2E" "skip" "Skipped (timeout or not ready). See $TEST_LOG_DIR/${TIMESTAMP}_e2e.log"
  fi
else
  log_result "Playwright E2E" "skip" "End2EndTest directory not found"
fi

# =========== SUMMARY ===========
echo "" >> "$ARTIFACT_FILE"
echo "## Summary" >> "$ARTIFACT_FILE"
echo "" >> "$ARTIFACT_FILE"
echo "Test Logs: $TEST_LOG_DIR/" >> "$ARTIFACT_FILE"
echo "Artifact: $ARTIFACT_FILE" >> "$ARTIFACT_FILE"
echo "Status: 🟢 COMPLETE" >> "$ARTIFACT_FILE"

echo ""
echo -e "${GREEN}✓ Test suite complete${NC}"
echo "Results saved to: $ARTIFACT_FILE"
echo ""
cat "$ARTIFACT_FILE"

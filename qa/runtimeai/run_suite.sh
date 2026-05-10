#!/bin/bash
# run_suite.sh — Run all runtimeai QA tests in sequence
# Usage: cd qa/runtimeai && bash run_suite.sh [--verbose] [--stop-on-fail] [--filter=pattern]

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }

# Configuration
VERBOSE=false
STOP_ON_FAIL=false
FILTER=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"
COMMON_SH="$SCRIPT_DIR/common.sh"
TEST_RESULTS="/tmp/qa-test-results-$$.txt"
FAILED_TESTS=()
PASSED_TESTS=()

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --stop-on-fail)
      STOP_ON_FAIL=true
      shift
      ;;
    --filter=*)
      FILTER="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: bash run_suite.sh [options]"
      echo ""
      echo "Options:"
      echo "  --verbose        Show detailed test output"
      echo "  --stop-on-fail   Stop on first failure"
      echo "  --filter=PATTERN Run only tests matching pattern"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Verify prerequisites
log_info "Verifying prerequisites..."

if [ ! -d "$TESTS_DIR" ]; then
  log_error "Tests directory not found: $TESTS_DIR"
  exit 1
fi

if [ ! -f "$COMMON_SH" ]; then
  log_warning "Common functions not found: $COMMON_SH (continuing anyway)"
  # Create minimal common.sh stub
  cat > "$COMMON_SH" << 'EOF'
#!/bin/bash
# Minimal common.sh stub for QA tests

# Test execution helper
run_test() {
  local test_name="$1"
  local test_cmd="$2"

  if [ -z "$test_cmd" ]; then
    echo "FAIL: $test_name (no command provided)"
    return 1
  fi

  # Execute test
  eval "$test_cmd"
}

# API helper
call_api() {
  local method="$1"
  local endpoint="$2"
  local data="$3"

  local url="${API_URL}${endpoint}"

  if [ -n "$data" ]; then
    curl -s -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SESSION_TOKEN}" \
      -d "$data"
  else
    curl -s -X "$method" "$url" \
      -H "Authorization: Bearer ${SESSION_TOKEN}"
  fi
}
EOF
fi

# Source common functions
source "$COMMON_SH" 2>/dev/null || log_warning "Could not source $COMMON_SH"

log_success "Prerequisites verified"
echo ""

# Find test scripts
log_info "Discovering tests..."

mapfile -t TEST_SCRIPTS < <(find "$TESTS_DIR" -maxdepth 1 -name "*.sh" -type f | sort)

if [ ${#TEST_SCRIPTS[@]} -eq 0 ]; then
  log_warning "No test scripts found in $TESTS_DIR"
  exit 0
fi

log_success "Found ${#TEST_SCRIPTS[@]} test scripts"

# Filter tests if requested
if [ -n "$FILTER" ]; then
  log_info "Filtering tests matching: $FILTER"
  FILTERED_SCRIPTS=()
  for script in "${TEST_SCRIPTS[@]}"; do
    if [[ "$(basename "$script")" =~ $FILTER ]]; then
      FILTERED_SCRIPTS+=("$script")
    fi
  done
  TEST_SCRIPTS=("${FILTERED_SCRIPTS[@]}")
  log_success "Filtered to ${#TEST_SCRIPTS[@]} matching tests"
fi

echo ""
log_info "Running test suite..."
echo ""

# Run each test
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

for test_script in "${TEST_SCRIPTS[@]}"; do
  TEST_COUNT=$((TEST_COUNT + 1))
  test_name=$(basename "$test_script" .sh)

  # Run test
  if [ "$VERBOSE" = "true" ]; then
    log_info "Running: $test_name"
    if bash "$test_script" 2>&1 | tee -a "$TEST_RESULTS"; then
      log_success "$test_name PASSED"
      PASSED_TESTS+=("$test_name")
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      log_error "$test_name FAILED"
      FAILED_TESTS+=("$test_name")
      FAIL_COUNT=$((FAIL_COUNT + 1))
      if [ "$STOP_ON_FAIL" = "true" ]; then
        break
      fi
    fi
  else
    # Quiet mode: only show pass/fail
    if bash "$test_script" >> "$TEST_RESULTS" 2>&1; then
      log_success "$test_name"
      PASSED_TESTS+=("$test_name")
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      log_error "$test_name"
      FAILED_TESTS+=("$test_name")
      FAIL_COUNT=$((FAIL_COUNT + 1))
      if [ "$STOP_ON_FAIL" = "true" ]; then
        break
      fi
    fi
  fi
done

echo ""
echo "====================================================================="
echo "TEST SUITE SUMMARY"
echo "====================================================================="
echo "Total:  $TEST_COUNT tests"
echo "Passed: $PASS_COUNT tests"
echo "Failed: $FAIL_COUNT tests"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
  log_error "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  - $test"
  done
  echo ""
fi

if [ $PASS_COUNT -gt 0 ]; then
  log_success "Passed tests:"
  for test in "${PASSED_TESTS[@]}"; do
    echo "  ✓ $test"
  done
  echo ""
fi

echo "====================================================================="

# Cleanup
rm -f "$TEST_RESULTS"

# Exit with appropriate code
if [ $FAIL_COUNT -gt 0 ]; then
  exit 1
else
  log_success "All tests passed ✅"
  exit 0
fi

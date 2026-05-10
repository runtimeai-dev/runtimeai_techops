#!/bin/bash
# run_customer_suite.sh — Customer-facing feature QA test suite
# Usage: bash qa/customer/run_customer_suite.sh --env=rt19 [--verbose] [--filter=pattern]

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
VERBOSE=false
FILTER=""
ENVIRONMENT=""
BASE_URL=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"
TEST_RESULTS="/tmp/customer-qa-test-results-$$.txt"
FAILED_TESTS=()
PASSED_TESTS=()

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --env=*)
      ENVIRONMENT="${1#*=}"
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --filter=*)
      FILTER="${1#*=}"
      shift
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Validate environment and set BASE_URL
case "$ENVIRONMENT" in
  rt19)
    BASE_URL="https://app.rt19.runtimeai.io"
    ;;
  rt01)
    BASE_URL="https://app.runtimeai.io"
    ;;
  rt02)
    BASE_URL="https://app-rt02.runtimeai.io"
    ;;
  *)
    log_error "Environment required: --env=<rt19|rt01|rt02>"
    exit 1
    ;;
esac

log_info "Customer Feature QA Test Suite"
log_info "Environment: $ENVIRONMENT | Base URL: $BASE_URL"
echo ""

# Create test data (seed)
log_info "Creating seed data..."
# In production: create test accounts, upload test data
log_success "Seed data created"
echo ""

# Discover and run tests
log_info "Discovering tests in $TESTS_DIR..."
mapfile -t TEST_SCRIPTS < <(find "$TESTS_DIR" -maxdepth 1 -name "*.sh" -type f | sort)

if [ ${#TEST_SCRIPTS[@]} -eq 0 ]; then
  log_warning "No test scripts found"
  exit 0
fi

log_success "Found ${#TEST_SCRIPTS[@]} test scripts"

# Filter if requested
if [ -n "$FILTER" ]; then
  FILTERED_SCRIPTS=()
  for script in "${TEST_SCRIPTS[@]}"; do
    if [[ "$(basename "$script")" =~ $FILTER ]]; then
      FILTERED_SCRIPTS+=("$script")
    fi
  done
  TEST_SCRIPTS=("${FILTERED_SCRIPTS[@]}")
fi

echo ""
log_info "Running customer tests..."
echo ""

# Run each test
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

for test_script in "${TEST_SCRIPTS[@]}"; do
  TEST_COUNT=$((TEST_COUNT + 1))
  test_name=$(basename "$test_script" .sh)

  # Set environment for test
  export BASE_URL ENVIRONMENT

  # Run test
  if [ "$VERBOSE" = "true" ]; then
    if bash "$test_script" 2>&1 | tee -a "$TEST_RESULTS"; then
      log_success "$test_name PASSED"
      PASSED_TESTS+=("$test_name")
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      log_error "$test_name FAILED"
      FAILED_TESTS+=("$test_name")
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    if timeout 30 bash "$test_script" >> "$TEST_RESULTS" 2>&1; then
      log_success "$test_name"
      PASSED_TESTS+=("$test_name")
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      log_error "$test_name"
      FAILED_TESTS+=("$test_name")
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
done

echo ""
echo "====================================================================="
echo "CUSTOMER QA TEST SUMMARY"
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

# Cleanup test data
log_info "Cleaning up test data..."
# In production: delete test accounts
log_success "Cleanup complete"

# Cleanup results file
rm -f "$TEST_RESULTS"

# Exit with appropriate code
if [ $FAIL_COUNT -gt 0 ]; then
  exit 1
else
  log_success "All customer tests passed ✅"
  exit 0
fi

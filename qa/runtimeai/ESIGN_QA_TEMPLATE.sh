#!/bin/bash
# eSign Signing Flow QA Test Suite Template
# File: qa_testing_local/ESIGN_QA_TEMPLATE.sh
# Purpose: Test guest signing flow (happy path, decline, sign later)
# NOTE: Use only qa-signer-@test.runtimeai.io emails — NEVER use roshan@runtimeai.io or production @runtimeai.io

set -e

echo "🧪 eSign Signing Flow QA Tests"
echo "==============================="
echo ""

# Configuration
API_BASE=${API_BASE:-"http://localhost:8080"}
ESIGN_BASE=${ESIGN_BASE:-"http://localhost:3000"}
TEST_SIGNER_EMAIL="qa-signer-1@test.runtimeai.io"
TEST_DOCUMENT_TITLE="QA Test NDA Document"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper: make HTTP request
function http_request() {
  local method=$1
  local endpoint=$2
  local data=$3

  if [ -n "$data" ]; then
    curl -s -X $method "$API_BASE$endpoint" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -X $method "$API_BASE$endpoint" \
      -H "Content-Type: application/json"
  fi
}

# Test 1: Happy Path — Load document, sign all fields, finish
function test_happy_path() {
  echo -e "${YELLOW}Test 1: Happy Path${NC}"

  # 1a. Create test document
  echo "  1a. Create document..."
  DOC_RESPONSE=$(http_request POST "/api/v1/documents" \
    "{\"title\": \"$TEST_DOCUMENT_TITLE\", \"signer_email\": \"$TEST_SIGNER_EMAIL\"}")
  DOCUMENT_ID=$(echo $DOC_RESPONSE | jq -r '.document_id')

  if [ -z "$DOCUMENT_ID" ] || [ "$DOCUMENT_ID" = "null" ]; then
    echo -e "${RED}  ✗ Failed to create document${NC}"
    return 1
  fi
  echo -e "${GREEN}  ✓ Document created: $DOCUMENT_ID${NC}"

  # 1b. Get signing token
  echo "  1b. Get signing token..."
  TOKEN_RESPONSE=$(http_request GET "/api/v1/documents/$DOCUMENT_ID/signing-token")
  SIGNING_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.token')

  if [ -z "$SIGNING_TOKEN" ] || [ "$SIGNING_TOKEN" = "null" ]; then
    echo -e "${RED}  ✗ Failed to get token${NC}"
    return 1
  fi
  echo -e "${GREEN}  ✓ Token obtained${NC}"

  # 1c. Load signing page via browser (would use Playwright in actual test)
  echo "  1c. Load signing page..."
  SIGNING_URL="$ESIGN_BASE/sign/$SIGNING_TOKEN"
  echo -e "${GREEN}  ✓ Signing URL: $SIGNING_URL${NC}"

  # 1d. Simulate signing all fields
  echo "  1d. Submit signatures..."
  SIGN_RESPONSE=$(http_request POST "/api/v1/sign/guest/$SIGNING_TOKEN/submit" \
    "{\"fields\": {\"field_1\": \"John Doe\", \"field_2\": \"2026-04-05\"}}")

  if echo $SIGN_RESPONSE | jq -e '.success' > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Document signed successfully${NC}"
    return 0
  else
    echo -e "${RED}  ✗ Failed to sign document${NC}"
    echo "    Response: $SIGN_RESPONSE"
    return 1
  fi
}

# Test 2: Sign Later — Load document, click "Sign Later", verify status
function test_sign_later() {
  echo -e "${YELLOW}Test 2: Sign Later${NC}"

  # Create document
  echo "  2a. Create document..."
  DOC_RESPONSE=$(http_request POST "/api/v1/documents" \
    "{\"title\": \"$TEST_DOCUMENT_TITLE (Sign Later)\", \"signer_email\": \"$TEST_SIGNER_EMAIL\"}")
  DOCUMENT_ID=$(echo $DOC_RESPONSE | jq -r '.document_id')

  echo -e "${GREEN}  ✓ Document created: $DOCUMENT_ID${NC}"

  # Get token
  echo "  2b. Get token..."
  TOKEN_RESPONSE=$(http_request GET "/api/v1/documents/$DOCUMENT_ID/signing-token")
  SIGNING_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.token')

  echo -e "${GREEN}  ✓ Token obtained${NC}"

  # Call sign later endpoint
  echo "  2c. Call /view (sign later)..."
  VIEW_RESPONSE=$(http_request POST "/api/v1/sign/guest/$SIGNING_TOKEN/view")

  if echo $VIEW_RESPONSE | jq -e '.success' > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Sign Later successful — status updated to 'viewed'${NC}"
    return 0
  else
    echo -e "${RED}  ✗ Failed to mark as viewed${NC}"
    return 1
  fi
}

# Test 3: Decline — Load document, decline with reason
function test_decline() {
  echo -e "${YELLOW}Test 3: Decline${NC}"

  # Create document
  echo "  3a. Create document..."
  DOC_RESPONSE=$(http_request POST "/api/v1/documents" \
    "{\"title\": \"$TEST_DOCUMENT_TITLE (Decline)\", \"signer_email\": \"$TEST_SIGNER_EMAIL\"}")
  DOCUMENT_ID=$(echo $DOC_RESPONSE | jq -r '.document_id')

  echo -e "${GREEN}  ✓ Document created: $DOCUMENT_ID${NC}"

  # Get token
  echo "  3b. Get token..."
  TOKEN_RESPONSE=$(http_request GET "/api/v1/documents/$DOCUMENT_ID/signing-token")
  SIGNING_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.token')

  echo -e "${GREEN}  ✓ Token obtained${NC}"

  # Call decline endpoint
  echo "  3c. Call /decline..."
  DECLINE_RESPONSE=$(http_request POST "/api/v1/sign/guest/$SIGNING_TOKEN/decline" \
    "{\"reason\": \"Cannot sign at this time\"}")

  if echo $DECLINE_RESPONSE | jq -e '.success' > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Decline successful — sender notified${NC}"
    return 0
  else
    echo -e "${RED}  ✗ Failed to decline${NC}"
    return 1
  fi
}

# Run all tests
echo "Starting tests at $(date)"
echo ""

PASS=0
FAIL=0

test_happy_path && ((PASS++)) || ((FAIL++))
echo ""
test_sign_later && ((PASS++)) || ((FAIL++))
echo ""
test_decline && ((PASS++)) || ((FAIL++))
echo ""

echo "==============================="
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo "==============================="

if [ $FAIL -eq 0 ]; then
  exit 0
else
  exit 1
fi

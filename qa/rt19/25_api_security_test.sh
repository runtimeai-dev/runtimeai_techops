#!/bin/bash
# 25_api_security_test.sh - Verify Sequence Modeler (API Security)

set -e

MODELER_URL="http://localhost:8105"
SESSION_ID="test-session-$(date +%s)"

# Pre-check: Verify Sequence Modeler is running
if ! curl -s --connect-timeout 2 "$MODELER_URL/health" > /dev/null 2>&1; then
    echo "SKIP: Sequence Modeler (port 8105) is not running."
    exit 0
fi

echo "--- Feature 25: API Security Verification (Sequence Modeler) ---"

# 1. Normal traffic
echo "1. Sending normal traffic..."
for i in {1..3}; do
  curl -s -X POST "$MODELER_URL/analyze" \
    -H "Content-Type: application/json" \
    -d "{
      \"session_id\": \"$SESSION_ID\",
      \"method\": \"GET\",
      \"path\": \"/products/item-$i\",
      \"timestamp\": $(date +%s)
    }" | jq
done

# 2. Triggering Scraping Pattern (Repeated access to /api/*)
# Pattern: name: data_scraping, sequence: ["GET /api/*"], min_repeat: 5
echo "2. Triggering Data Scraping pattern..."
for i in {1..5}; do
  RESP=$(curl -s -X POST "$MODELER_URL/analyze" \
    -H "Content-Type: application/json" \
    -d "{
      \"session_id\": \"$SESSION_ID\",
      \"method\": \"GET\",
      \"path\": \"/api/user/details-$i\",
      \"timestamp\": $(date +%s)
    }")
  echo "Request $i: $(echo $RESP | jq -r .allow)"
  if [[ "$RESP" == *"Abuse Pattern Detected"* ]]; then
    echo "PASS: Scraping detected!"
    break
  fi
done

# 3. Triggering Flow Sequence
# Pattern: name: checkout_abuse, sequence: ["GET /cart", "POST /checkout"], min_repeat: 2
echo "3. Triggering Checkout Abuse sequence..."
SESSION_ID_2="abuse-session-$(date +%s)"
for i in {1..2}; do
  curl -s -X POST "$MODELER_URL/analyze" -H "Content-Type: application/json" -d "{\"session_id\": \"$SESSION_ID_2\", \"method\": \"GET\", \"path\": \"/cart\", \"timestamp\": $(date +%s)}" > /dev/null
  RESP=$(curl -s -X POST "$MODELER_URL/analyze" -H "Content-Type: application/json" -d "{\"session_id\": \"$SESSION_ID_2\", \"method\": \"POST\", \"path\": \"/checkout\", \"timestamp\": $(date +%s)}")
  echo "Iteration $i Result: $(echo $RESP | jq -r .reason)"
done

echo "--- API Security Verification Complete ---"

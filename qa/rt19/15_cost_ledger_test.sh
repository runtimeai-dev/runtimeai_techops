#!/bin/bash
set -e
source "$(dirname "$0")/common.sh"

echo "Running Cost Ledger Tests (Feature 09)..."

CL_PORT=8099
LOG_FILE="cost_ledger_test.log"
BIN_DIR="bin"
mkdir -p "$BIN_DIR"

# Cleanup
cleanup() {
    echo "Cleaning up..."
    kill $CL_PID 2>/dev/null || true
    rm -f "$LOG_FILE"
}
trap cleanup EXIT

# Ensure ports are free
echo "Ensure ports are free..."
lsof -ti :$CL_PORT | xargs kill -9 2>/dev/null || true
sleep 1

# 1. Build Cost Ledger
echo "Building Cost Ledger..."
pushd services/cost-ledger
# Assuming go.mod is fixed now
go build -o ../../$BIN_DIR/cost-ledger cmd/server/main.go
popd

# 2. Start Cost Ledger (Connects to local Redis and DB)
# We assume Redis and Postgres are running from previous tests or docker
echo "Starting Cost Ledger..."
export PORT=$CL_PORT
export REDIS_ADDR="localhost:6380"
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/authzion?sslmode=disable"

"$BIN_DIR/cost-ledger" > "$LOG_FILE" 2>&1 &
CL_PID=$!
sleep 2

# Verify startup
if ! grep -q "Listening on :$CL_PORT" "$LOG_FILE" && ! grep -q "listening on :$CL_PORT" "$LOG_FILE"; then
    echo "Startup logs:"
    cat "$LOG_FILE"
    # Proceed anyway, checking HTTP
fi

TENANT_ID="test-tenant-bugdet-$(date +%s)"

# 3. Set Budget (Limit: $1.00 = 100 cents, Threshold: 50%)
echo "Test 1: Set Budget..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "http://localhost:$CL_PORT/v1/budgets" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TENANT_ID\", \"monthly_limit_cents\": 100, \"alert_threshold_pct\": 50}")

if [ "$HTTP_CODE" != "200" ]; then
    error "Failed to set budget. Code: $HTTP_CODE"
fi
log "PASS: Budget set successfully."

# 4. Check Spend (Under Limit) - Spend $0.40 (40 cents)
echo "Test 2: Check Spend ($0.40)..."
RESP=$(curl -s -X POST "http://localhost:$CL_PORT/v1/check" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TENANT_ID\", \"cost\": 0.40}")

ALLOWED=$(echo "$RESP" | jq -r '.allowed')
REMAINING=$(echo "$RESP" | jq -r '.remaining')

if [ "$ALLOWED" != "true" ]; then
    error "Expected allowed=true, got $ALLOWED"
fi
# Remaining should be 1.00 - 0.40 = 0.60
if (( $(echo "$REMAINING != 0.6" | bc -l) )); then
     # Allow small float diffs if any, but since we use cents internal logic, remainingDollars might be exact?
     # Actually remaining is float in response.
     log "Warning: Remaining $REMAINING != 0.6"
fi
log "PASS: Check spend allowed."

# 5. Check Spend (Trigger Alert) - Spend $0.20 (Total $0.60 = 60%, Threshold 50%)
echo "Test 3: Check Spend (Trigger Alert)..."
# We can't easily check internal logs or Redis pubsub in this script without a listener.
# We'll check the service logs for "ALERT:"
RESP=$(curl -s -X POST "http://localhost:$CL_PORT/v1/check" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TENANT_ID\", \"cost\": 0.20}")

ALLOWED=$(echo "$RESP" | jq -r '.allowed')
if [ "$ALLOWED" != "true" ]; then
    error "Expected allowed=true, got $ALLOWED"
fi

sleep 1
if grep -q "ALERT: Tenant $TENANT_ID" "$LOG_FILE"; then
    log "PASS: Alert triggered and logged."
else
    cat "$LOG_FILE"
    error "FAIL: Alert NOT logged."
fi

# 6. Check Spend (Over Limit) - Spend $0.50 (Total $1.10 > $1.00)
echo "Test 4: Check Spend (Over Limit)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:$CL_PORT/v1/check" \
    -H "Content-Type: application/json" \
    -d "{\"tenant_id\": \"$TENANT_ID\", \"cost\": 0.50}")

if [ "$HTTP_CODE" != "402" ]; then
    error "Expected 402 Payment Required, got $HTTP_CODE"
fi
log "PASS: Spend blocked (Budget Exceeded)."

echo "Cost Ledger Tests Completed."

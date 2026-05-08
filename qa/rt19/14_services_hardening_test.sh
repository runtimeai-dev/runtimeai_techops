#!/bin/bash
set -e
source "$(dirname "$0")/common.sh"

echo "Running Vendor Wrapper Hardening Tests (Feature 07)..."

VW_PORT=8099
OPA_PORT=8199
LOG_FILE="vendor_wrapper_test.log"
BIN_DIR="bin"
mkdir -p "$BIN_DIR"
# Pre-test Cleanup (ONLY kill our own test processes, never Docker proxies)
echo "Ensure ports are free..."
lsof -ti :$VW_PORT -c vendor-wrapper | xargs kill -9 2>/dev/null || true
lsof -ti :$OPA_PORT -c python3 -c Python | xargs kill -9 2>/dev/null || true
sleep 1

# 1. Build Vendor Wrapper
echo "Building Vendor Wrapper..."
pushd services/vendor-wrapper
go build -o ../../$BIN_DIR/vendor-wrapper cmd/server/main.go
popd

# 2. Start Mock OPA (Python simple HTTP server that always returns 200 Allow by default, but we can kill it)
# Actually, let's just run it, verify success, then kill it.
echo "Starting Mock OPA on port $OPA_PORT..."
python3 -c "
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class OPAHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        body = self.rfile.read(content_length)
        print(f'OPA Received: {body.decode()}')
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {'result': True}
        self.wfile.write(json.dumps(response).encode())

httpd = HTTPServer(('localhost', $OPA_PORT), OPAHandler)
print('Mock OPA running...')
httpd.serve_forever()
" > opa_mock.log 2>&1 &
OPA_PID=$!

# Ensure cleanup (only kill our test processes, verify Docker is OK after)
cleanup() {
    echo "Cleaning up test processes..."
    kill $VW_PID 2>/dev/null || true
    kill $OPA_PID 2>/dev/null || true
    wait $VW_PID 2>/dev/null || true
    wait $OPA_PID 2>/dev/null || true
    # Verify Docker containers survived our test
    if ! docker info &>/dev/null; then
        echo "WARNING: Docker daemon is not responding after test cleanup!"
    fi
}
trap cleanup EXIT

# 3. Start Vendor Wrapper pointing to Mock OPA and Self as Target (just for connectivity)
echo "Starting Vendor Wrapper..."
export VENDOR_WRAPPER_PORT=$VW_PORT
export OPA_URL="http://localhost:$OPA_PORT/v1/data/vendor/allow"
export TARGET_URL="http://google.com" # Just need a valid proxy target, response doesn't matter much for this test
export REQUEST_TIMEOUT="2" 

"$BIN_DIR/vendor-wrapper" > "$LOG_FILE" 2>&1 &
VW_PID=$!

sleep 2
echo "Vendor Wrapper Started (PID $VW_PID). Startup Logs:"
head -n 20 "$LOG_FILE"
echo "------------------------------------------------"

# 4. Test Normal Operation (OPA Up)
echo "Test 1: Normal Request (Should Pass OPA, Proxy might return 200 or 404/502 but OPA worked)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$VW_PORT/test")
echo "HTTP Code: $HTTP_CODE"

# If 200, 404, or anything other than 503/403 (Forbidden), it passed OPA
if [ "$HTTP_CODE" == "503" ] || [ "$HTTP_CODE" == "403" ]; then
    grep "Error querying OPA" "$LOG_FILE" || true
    error "Test 1 Failed. Expected normal proxy response, got $HTTP_CODE"
fi
log "PASS: Normal request processed."

# 5. Simulate OPA Outage (Kill Mock OPA)
echo "Test 2: Simulating OPA Outage..."
kill -9 $OPA_PID
wait $OPA_PID 2>/dev/null || true
echo "Killed OPA PID $OPA_PID"
sleep 2

# Verify OPA port is closed
if nc -z localhost $OPA_PORT; then
    echo "ERROR: OPA Port $OPA_PORT is still open!"
    lsof -i :$OPA_PORT
    exit 1
else
    echo "OPA Port $OPA_PORT is closed."
fi

# 6. Trip the Circuit Breaker (Threshold = 5)
echo "Sending requests to trip CB..."
for i in {1..5}; do
    echo "Request $i..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$VW_PORT/fail-$i")
    if [ "$HTTP_CODE" != "503" ]; then
       echo "=== Vendor Wrapper Log (Failure) ==="
       cat "$LOG_FILE"
       echo "===================================="
       error "Expected 503 during OPA outage, got $HTTP_CODE"
    fi
done

# 7. Verify Circuit Breaker Open
echo "Test 3: Verify Circuit Breaker Open (Request 6)"
HTTP_CODE=$(curl -s -I "http://localhost:$VW_PORT/cb-test" | grep "HTTP" | awk '{print $2}')
RETRY_AFTER=$(curl -s -I "http://localhost:$VW_PORT/cb-test" | grep -i "Retry-After" | awk '{print $2}' | tr -d '\r')

echo "Code: $HTTP_CODE, Retry-After: $RETRY_AFTER"

if [ "$HTTP_CODE" != "503" ]; then
     grep "Error querying OPA" "$LOG_FILE" || true
     error "CB Test Failed. Expected 503, got $HTTP_CODE"
fi

# Check for "circuit breaker open" in logs
if grep -q "circuit breaker open" "$LOG_FILE"; then
    log "PASS: Found 'circuit breaker open' in logs."
else
    echo "=== Vendor Wrapper Log ==="
    cat "$LOG_FILE"
    echo "=========================="
    error "FAIL: Did not find 'circuit breaker open' log message."
fi

echo "Vendor Wrapper Hardening Tests Completed."

# Cleanup only if successful or manually handled
rm -f "$LOG_FILE" opa_mock.log

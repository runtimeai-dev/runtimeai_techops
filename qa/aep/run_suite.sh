#!/bin/bash
# AEP Automated Test Suite — All Services

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "AEP QA Test Suite"
echo "=========================================="
echo ""

API_BASE="${API_BASE:-http://localhost}"

test_health() {
	local port=$1
	response=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE:$port/healthz" 2>/dev/null || echo "000")
	[ "$response" = "200" ]
}

test_jwt() {
	local port=$1
	response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_BASE:$port/api/v1/test" \
		-H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
	[ "$response" = "401" ] || [ "$response" = "403" ]
}

declare -A SERVICE_PORTS=(
	[kya]=8301
	[cost-control]=8302
	[audit-black-box]=8303
	[pii-shield]=8304
	[observability]=8305
	[fraud-shield]=8306
	[memory-vault]=8307
	[commerce-rails]=8308
	[commerce-protocol]=8309
	[marketplace]=8310
	[developer-hub]=8311
	[contract-manager]=8312
	[procurement-hub]=8313
	[finance-rail]=8314
)

PASSED=0
FAILED=0

for service in "${!SERVICE_PORTS[@]}"; do
	port=${SERVICE_PORTS[$service]}
	
	if test_health "$port"; then
		echo -e "${GREEN}✓${NC} $service (port $port): health OK"
		PASSED=$((PASSED + 1))
	else
		echo -e "${RED}✗${NC} $service (port $port): health FAILED"
		FAILED=$((FAILED + 1))
	fi
done

echo ""
echo "=========================================="
echo "Results: ${PASSED} passed, ${FAILED} failed"
echo "=========================================="

if [ $FAILED -eq 0 ]; then
	exit 0
else
	exit 1
fi

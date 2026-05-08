#!/bin/bash
# rt19_health_check.sh — Automated health monitoring
# Run periodically: `watch -n 300 bash health_check.sh`
# Or: `0 */5 * * * bash /path/to/health_check.sh >> /tmp/rt19_health.log`

set +e

API_URL="https://api.rt19.runtimeai.io"
DASHBOARD_URL="https://app.rt19.runtimeai.io"
ADMIN_URL="https://admin.runtimeai.io"
ESIGN_URL="https://esign.rt19.runtimeai.io"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ALERT_EMAIL="oncall@runtimeai.io"
LOG_FILE="/tmp/rt19_health_$(date +%Y%m%d).log"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

function check_endpoint() {
  local name=$1
  local url=$2
  local expected_code=${3:-200}

  local status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)

  if [ "$status" == "$expected_code" ]; then
    echo -e "${GREEN}✓${NC} $name ($status)"
    echo "[$TIMESTAMP] ✓ $name: $status" >> "$LOG_FILE"
    return 0
  else
    echo -e "${RED}✗${NC} $name (expected $expected_code, got $status)"
    echo "[$TIMESTAMP] ✗ $name: expected $expected_code, got $status" >> "$LOG_FILE"
    return 1
  fi
}

function check_json_endpoint() {
  local name=$1
  local url=$2
  local query=$3

  local result=$(curl -s "$url" | jq "$query" 2>/dev/null)

  if [ -n "$result" ] && [ "$result" != "null" ]; then
    echo -e "${GREEN}✓${NC} $name: $result"
    echo "[$TIMESTAMP] ✓ $name: $result" >> "$LOG_FILE"
    return 0
  else
    echo -e "${RED}✗${NC} $name: no response"
    echo "[$TIMESTAMP] ✗ $name: no response" >> "$LOG_FILE"
    return 1
  fi
}

function check_pod_health() {
  local namespace=${1:-rt19}
  local pod_name=$2

  local status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)
  local restarts=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)

  if [ "$status" == "Running" ]; then
    if [ "$restarts" -gt 0 ]; then
      echo -e "${YELLOW}⚠${NC} $pod_name: Running but $restarts restarts"
      return 1
    else
      echo -e "${GREEN}✓${NC} $pod_name: Healthy (0 restarts)"
      return 0
    fi
  else
    echo -e "${RED}✗${NC} $pod_name: $status"
    return 1
  fi
}

# ========== HEADER ==========
echo ""
echo "========== rt19 HEALTH CHECK =========="
echo "Timestamp: $TIMESTAMP"
echo "======================================"
echo ""

# ========== API HEALTH ==========
echo "## API Endpoints"
FAIL_COUNT=0
check_endpoint "Control Plane Health" "$API_URL/health" 200 || ((FAIL_COUNT++))
check_json_endpoint "CP Status" "$API_URL/health" '.status' || ((FAIL_COUNT++))

echo ""
echo "## Dashboard & Admin"
check_endpoint "Dashboard Frontend" "$DASHBOARD_URL" 200 || ((FAIL_COUNT++))
check_endpoint "Admin App" "$ADMIN_URL" 200 || ((FAIL_COUNT++))
check_endpoint "eSign Frontend" "$ESIGN_URL" 200 || ((FAIL_COUNT++))

echo ""
echo "## Critical Service Pods (rt19)"

# Get pod list
PODS=$(kubectl get pods -n rt19 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
RUNNING=0
FAILED=0

for pod in $PODS; do
  status=$(kubectl get pod "$pod" -n rt19 -o jsonpath='{.status.phase}' 2>/dev/null)
  if [ "$status" == "Running" ]; then
    ((RUNNING++))
  else
    ((FAILED++))
    echo -e "${RED}✗${NC} $pod: $status"
  fi
done

echo -e "${GREEN}✓${NC} Pods Running: $RUNNING"
if [ $FAILED -gt 0 ]; then
  echo -e "${RED}✗${NC} Pods Not Running: $FAILED"
  ((FAIL_COUNT++))
fi

echo ""
echo "## Pod Restart Monitoring"
HIGH_RESTART_PODS=$(kubectl get pods -n rt19 -o json | \
  jq -r '.items[] | select(.status.containerStatuses[0].restartCount > 2) | .metadata.name' 2>/dev/null)

if [ -n "$HIGH_RESTART_PODS" ]; then
  echo -e "${YELLOW}⚠${NC} Pods with >2 restarts:"
  echo "$HIGH_RESTART_PODS" | while read pod; do
    restarts=$(kubectl get pod "$pod" -n rt19 -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    echo "  - $pod ($restarts restarts)"
  done
else
  echo -e "${GREEN}✓${NC} No pods with excessive restarts"
fi

echo ""
echo "## Resource Usage"
echo "Top 5 services by CPU:"
kubectl top pods -n rt19 --sort-by=cpu --no-headers 2>/dev/null | head -5 | \
  awk '{printf "  %-30s %6s\n", $1, $3}'

echo ""
echo "Top 5 services by Memory:"
kubectl top pods -n rt19 --sort-by=memory --no-headers 2>/dev/null | head -5 | \
  awk '{printf "  %-30s %6s\n", $1, $4}'

# ========== SUMMARY ==========
echo ""
echo "======================================"
if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
  echo "Status: HEALTHY"
else
  echo -e "${RED}✗ $FAIL_COUNT CHECKS FAILED${NC}"
  echo "Status: DEGRADED"
  echo "Review: kubectl describe pod <name> -n rt19"
  echo "Logs: kubectl logs deployment/<svc> -n rt19 --tail=50"
fi
echo "======================================"
echo ""

exit $FAIL_COUNT

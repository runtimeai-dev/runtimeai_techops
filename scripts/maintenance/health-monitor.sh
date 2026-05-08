#!/usr/bin/env bash
# =============================================================================
# RuntimeAI rt19 — Health Monitor
#
# Checks all public endpoints, internal services, databases, and TLS certs.
# Can run as a cron job or one-shot.
#
# USAGE:
#   ./health-monitor.sh              # One-shot check
#   ./health-monitor.sh --watch      # Continuous monitoring (30s interval)
#   ./health-monitor.sh --json       # Output JSON (for alerting pipelines)
#   ./health-monitor.sh --slack      # Post to Slack webhook
# =============================================================================
set -eo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
DOMAIN="${DOMAIN:-runtimeai.io}"
POD_ID="${POD_ID:-rt19}"
NAMESPACE="${NAMESPACE:-rt19}"
LANDING_NAMESPACE="${LANDING_NAMESPACE:-runtimeai-landing}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
TIMEOUT=10
INTERVAL=30

# ── Colors ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Public Endpoints ───────────────────────────────────────────────────────
PUBLIC_ENDPOINTS=(
  "https://www.${DOMAIN}|Landing Page"
  "https://admin.${DOMAIN}|SaaS Admin"
  "https://app.${POD_ID}.${DOMAIN}|Dashboard"
  "https://api.${POD_ID}.${DOMAIN}/health|Control Plane API"
  "https://esign.${POD_ID}.${DOMAIN}|eSign Landing"
  "https://auditor.${POD_ID}.${DOMAIN}|Auditor Dashboard"
  "https://marketplace.${POD_ID}.${DOMAIN}/healthz|Agent Marketplace"
  "https://finops.${POD_ID}.${DOMAIN}/healthz|AI FinOps"
)

# ── Internal Services (checked via kubectl) ────────────────────────────────
RT19_SERVICES=(
  "control-plane"
  "dashboard"
  "auth-svc"
  "mcp-gateway"
  "discovery"
  "esign-service"
  "esign-landing"
  "aaic-service"
  "auditor-dashboard"
  "marketplace-service"
  "ai-finops-service"
  "postgres"
  "redis"
)

LANDING_SERVICES=(
  "runtimeai-landing"
  "landing-backend"
  "saas-admin-app"
)

# ── State ──────────────────────────────────────────────────────────────────
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0
RESULTS=()

# ── Functions ──────────────────────────────────────────────────────────────

check_public_endpoint() {
  local url="$1"
  local name="$2"
  TOTAL=$((TOTAL + 1))

  local http_code
  local response_time
  local start_time end_time

  start_time=$(date +%s%N 2>/dev/null || date +%s)
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")
  end_time=$(date +%s%N 2>/dev/null || date +%s)

  # Calculate response time in ms (fallback to seconds if nanoseconds not available)
  if [[ "$start_time" =~ ^[0-9]{10,}$ ]]; then
    response_time=$(( (end_time - start_time) / 1000000 ))
  else
    response_time=$(( (end_time - start_time) * 1000 ))
  fi

  if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
    PASSED=$((PASSED + 1))
    if [[ "$response_time" -gt 3000 ]]; then
      WARNINGS=$((WARNINGS + 1))
      printf "  ${YELLOW}⚠${NC}  %-25s HTTP %s  %4dms (SLOW)\n" "$name" "$http_code" "$response_time"
      RESULTS+=("{\"name\":\"$name\",\"status\":\"slow\",\"code\":$http_code,\"ms\":$response_time}")
    else
      printf "  ${GREEN}✓${NC}  %-25s HTTP %s  %4dms\n" "$name" "$http_code" "$response_time"
      RESULTS+=("{\"name\":\"$name\",\"status\":\"up\",\"code\":$http_code,\"ms\":$response_time}")
    fi
  else
    FAILED=$((FAILED + 1))
    printf "  ${RED}✗${NC}  %-25s HTTP %s  FAILED\n" "$name" "$http_code"
    RESULTS+=("{\"name\":\"$name\",\"status\":\"down\",\"code\":$http_code,\"ms\":0}")
  fi
}

check_tls_expiry() {
  local host="$1"
  local name="$2"
  TOTAL=$((TOTAL + 1))

  local expiry_date days_left
  expiry_date=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | \
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

  if [[ -z "$expiry_date" ]]; then
    FAILED=$((FAILED + 1))
    printf "  ${RED}✗${NC}  %-25s TLS: Could not check\n" "$name"
    return
  fi

  # Cross-platform date handling
  if date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s &>/dev/null; then
    local expiry_epoch
    expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
    days_left=$(( (expiry_epoch - $(date +%s)) / 86400 ))
  else
    days_left=30  # Can't parse, assume OK
  fi

  if [[ "$days_left" -lt 7 ]]; then
    FAILED=$((FAILED + 1))
    printf "  ${RED}✗${NC}  %-25s TLS: Expires in ${days_left}d — RENEW NOW\n" "$name"
  elif [[ "$days_left" -lt 30 ]]; then
    WARNINGS=$((WARNINGS + 1))
    PASSED=$((PASSED + 1))
    printf "  ${YELLOW}⚠${NC}  %-25s TLS: Expires in ${days_left}d\n" "$name"
  else
    PASSED=$((PASSED + 1))
    printf "  ${GREEN}✓${NC}  %-25s TLS: Valid for ${days_left}d\n" "$name"
  fi
}

check_k8s_pods() {
  local namespace="$1"
  local label="$2"

  shift 2
  local services=("$@")

  for svc in "${services[@]}"; do
    TOTAL=$((TOTAL + 1))
    local pod_status
    pod_status=$(kubectl get pods -n "$namespace" -l "app=$svc" \
      -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

    local restarts
    restarts=$(kubectl get pods -n "$namespace" -l "app=$svc" \
      -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")

    if [[ "$pod_status" == "Running" ]]; then
      PASSED=$((PASSED + 1))
      if [[ "$restarts" != "?" && "$restarts" -gt 5 ]]; then
        WARNINGS=$((WARNINGS + 1))
        printf "  ${YELLOW}⚠${NC}  %-25s %s (%s restarts)\n" "$svc" "$pod_status" "$restarts"
      else
        printf "  ${GREEN}✓${NC}  %-25s %s (%s restarts)\n" "$svc" "$pod_status" "$restarts"
      fi
    else
      FAILED=$((FAILED + 1))
      printf "  ${RED}✗${NC}  %-25s %s\n" "$svc" "$pod_status"
    fi
  done
}

check_database() {
  TOTAL=$((TOTAL + 1))
  local db_pod
  db_pod=$(kubectl get pods -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [[ -z "$db_pod" ]]; then
    FAILED=$((FAILED + 1))
    printf "  ${RED}✗${NC}  %-25s Pod not found\n" "PostgreSQL"
    return
  fi

  local ready
  ready=$(kubectl exec -n "$NAMESPACE" "$db_pod" -- pg_isready -U runtimeai 2>/dev/null || echo "FAIL")

  if [[ "$ready" == *"accepting"* ]]; then
    PASSED=$((PASSED + 1))
    printf "  ${GREEN}✓${NC}  %-25s Accepting connections\n" "PostgreSQL"
  else
    FAILED=$((FAILED + 1))
    printf "  ${RED}✗${NC}  %-25s Not ready: %s\n" "PostgreSQL" "$ready"
  fi
}

check_redis() {
  TOTAL=$((TOTAL + 1))
  local redis_pod
  redis_pod=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [[ -z "$redis_pod" ]]; then
    FAILED=$((FAILED + 1))
    printf "  ${RED}✗${NC}  %-25s Pod not found\n" "Redis"
    return
  fi

  local pong
  pong=$(kubectl exec -n "$NAMESPACE" "$redis_pod" -- redis-cli ping 2>/dev/null || echo "FAIL")

  if [[ "$pong" == "PONG" ]]; then
    PASSED=$((PASSED + 1))
    printf "  ${GREEN}✓${NC}  %-25s PONG\n" "Redis"
  else
    FAILED=$((FAILED + 1))
    printf "  ${RED}✗${NC}  %-25s No response\n" "Redis"
  fi
}

check_node_resources() {
  echo ""
  printf "${CYAN}── Node Resources ──────────────────────────────────────────${NC}\n"
  kubectl top nodes 2>/dev/null || echo "  (metrics-server not available — install it for resource metrics)"
}

check_pv_usage() {
  echo ""
  printf "${CYAN}── Persistent Volume Claims ────────────────────────────────${NC}\n"
  kubectl get pvc -A --no-headers 2>/dev/null | while read -r ns name status vol capacity access sc age; do
    printf "  %-20s %-25s %s  %s\n" "$ns" "$name" "$status" "$capacity"
  done
}

print_summary() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ "$FAILED" -eq 0 ]]; then
    printf "  ${GREEN}ALL CHECKS PASSED${NC}  —  %d/%d passed" "$PASSED" "$TOTAL"
    if [[ "$WARNINGS" -gt 0 ]]; then
      printf ", ${YELLOW}%d warnings${NC}" "$WARNINGS"
    fi
    echo ""
  else
    printf "  ${RED}%d CHECKS FAILED${NC}  —  %d/%d passed, %d failed" "$FAILED" "$PASSED" "$TOTAL" "$FAILED"
    if [[ "$WARNINGS" -gt 0 ]]; then
      printf ", ${YELLOW}%d warnings${NC}" "$WARNINGS"
    fi
    echo ""
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

output_json() {
  local status="healthy"
  [[ "$FAILED" -gt 0 ]] && status="unhealthy"
  [[ "$WARNINGS" -gt 0 && "$FAILED" -eq 0 ]] && status="degraded"

  echo "{"
  echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"pod\": \"$POD_ID\","
  echo "  \"status\": \"$status\","
  echo "  \"total\": $TOTAL,"
  echo "  \"passed\": $PASSED,"
  echo "  \"failed\": $FAILED,"
  echo "  \"warnings\": $WARNINGS,"
  echo "  \"checks\": [$(IFS=,; echo "${RESULTS[*]}")]"
  echo "}"
}

send_slack() {
  local status_emoji="✅"
  [[ "$FAILED" -gt 0 ]] && status_emoji="🔴"
  [[ "$WARNINGS" -gt 0 && "$FAILED" -eq 0 ]] && status_emoji="⚠️"

  local text="$status_emoji *rt19 Health Check* — $PASSED/$TOTAL passed"
  [[ "$FAILED" -gt 0 ]] && text="$text, *$FAILED FAILED*"
  [[ "$WARNINGS" -gt 0 ]] && text="$text, $WARNINGS warnings"

  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "{\"text\": \"$text\"}" > /dev/null
}

# ── Main ───────────────────────────────────────────────────────────────────

run_checks() {
  TOTAL=0; PASSED=0; FAILED=0; WARNINGS=0; RESULTS=()

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  RuntimeAI rt19 — Health Monitor"
  echo "  $(date)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # ── Public Endpoints ──
  echo ""
  printf "${CYAN}── Public Endpoints ────────────────────────────────────────${NC}\n"
  for entry in "${PUBLIC_ENDPOINTS[@]}"; do
    IFS='|' read -r url name <<< "$entry"
    check_public_endpoint "$url" "$name"
  done

  # ── TLS Certificates ──
  echo ""
  printf "${CYAN}── TLS Certificates ────────────────────────────────────────${NC}\n"
  check_tls_expiry "www.${DOMAIN}" "www.${DOMAIN}"
  check_tls_expiry "admin.${DOMAIN}" "admin.${DOMAIN}"
  check_tls_expiry "app.${POD_ID}.${DOMAIN}" "app.${POD_ID}.${DOMAIN}"
  check_tls_expiry "api.${POD_ID}.${DOMAIN}" "api.${POD_ID}.${DOMAIN}"
  check_tls_expiry "esign.${POD_ID}.${DOMAIN}" "esign.${POD_ID}.${DOMAIN}"
  check_tls_expiry "auditor.${POD_ID}.${DOMAIN}" "auditor.${POD_ID}.${DOMAIN}"
  check_tls_expiry "marketplace.${POD_ID}.${DOMAIN}" "marketplace.${POD_ID}.${DOMAIN}"
  check_tls_expiry "finops.${POD_ID}.${DOMAIN}" "finops.${POD_ID}.${DOMAIN}"

  # ── Kubernetes Pods ──
  echo ""
  printf "${CYAN}── rt19 Pods ───────────────────────────────────────────────${NC}\n"
  check_k8s_pods "$NAMESPACE" "app" "${RT19_SERVICES[@]}"

  echo ""
  printf "${CYAN}── Landing Pods ────────────────────────────────────────────${NC}\n"
  check_k8s_pods "$LANDING_NAMESPACE" "app" "${LANDING_SERVICES[@]}"

  # ── Database & Redis ──
  echo ""
  printf "${CYAN}── Data Layer ──────────────────────────────────────────────${NC}\n"
  check_database
  check_redis

  # ── Node Resources ──
  check_node_resources

  # ── PVC Usage ──
  check_pv_usage

  # ── Summary ──
  print_summary
}

# ── Argument Parsing ───────────────────────────────────────────────────────
case "${1:-}" in
  --json)
    run_checks > /dev/null 2>&1
    output_json
    ;;
  --slack)
    run_checks
    if [[ -n "$SLACK_WEBHOOK" ]]; then
      send_slack
      echo "  Slack notification sent."
    else
      echo "  Set SLACK_WEBHOOK env var to enable Slack alerts."
    fi
    ;;
  --watch)
    echo "Monitoring rt19 every ${INTERVAL}s... (Ctrl+C to stop)"
    while true; do
      clear
      run_checks
      sleep "$INTERVAL"
    done
    ;;
  *)
    run_checks
    ;;
esac

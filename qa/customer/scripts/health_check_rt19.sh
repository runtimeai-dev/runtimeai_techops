#!/bin/bash
# health_check_rt19.sh — Check all rt19 service health endpoints
# Usage: ./health_check_rt19.sh
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_url() {
  local name="$1"
  local url="$2"
  local expected="${3:-200}"

  STATUS=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")

  if [ "$STATUS" = "$expected" ]; then
    echo -e "  ${GREEN}✅${NC} $name → $STATUS"
    PASS=$((PASS + 1))
  elif [ "$STATUS" = "000" ]; then
    echo -e "  ${RED}❌${NC} $name → UNREACHABLE"
    FAIL=$((FAIL + 1))
  else
    echo -e "  ${YELLOW}⚠️${NC}  $name → $STATUS (expected $expected)"
    WARN=$((WARN + 1))
  fi
}

echo "============================================"
echo "  RuntimeAI rt19 Health Check"
echo "  $(date)"
echo "============================================"
echo ""

echo "--- Public Endpoints (via Ingress) ---"
check_url "Landing Page       " "https://runtimeai.io"
check_url "SaaS Admin         " "https://admin.runtimeai.io"
check_url "Dashboard          " "https://app.rt19.runtimeai.io"
check_url "Control Plane API  " "https://api.rt19.runtimeai.io/health"
check_url "eSign Landing      " "https://esign.rt19.runtimeai.io"
check_url "Auditor Dashboard  " "https://auditor.rt19.runtimeai.io"
check_url "Marketplace API    " "https://marketplace.rt19.runtimeai.io/healthz"
check_url "FinOps API         " "https://finops.rt19.runtimeai.io/healthz"

echo ""
echo "--- Internal Services (via kubectl port-forward or cluster DNS) ---"

# Check if we can access the K8s cluster
if kubectl get nodes &>/dev/null; then
  echo "  (K8s access available — checking pod status)"
  echo ""

  for ns in rt19 runtimeai-landing; do
    echo "  Namespace: $ns"
    kubectl get pods -n "$ns" --no-headers 2>/dev/null | while read -r line; do
      POD_NAME=$(echo "$line" | awk '{print $1}')
      READY=$(echo "$line" | awk '{print $2}')
      STATUS=$(echo "$line" | awk '{print $3}')

      if [ "$STATUS" = "Running" ]; then
        echo -e "    ${GREEN}✅${NC} $POD_NAME ($READY) — $STATUS"
        PASS=$((PASS + 1))
      elif [ "$STATUS" = "CrashLoopBackOff" ] || [ "$STATUS" = "Error" ]; then
        echo -e "    ${RED}❌${NC} $POD_NAME ($READY) — $STATUS"
        FAIL=$((FAIL + 1))
      else
        echo -e "    ${YELLOW}⚠️${NC}  $POD_NAME ($READY) — $STATUS"
        WARN=$((WARN + 1))
      fi
    done
    echo ""
  done

  # Check database
  echo "  Database & Cache:"
  if kubectl exec postgres-0 -n rt19 -- pg_isready -U authzion &>/dev/null; then
    echo -e "    ${GREEN}✅${NC} PostgreSQL — Ready"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}❌${NC} PostgreSQL — Not Ready"
    FAIL=$((FAIL + 1))
  fi

  if kubectl exec deployment/redis -n rt19 -- redis-cli ping 2>/dev/null | grep -q PONG; then
    echo -e "    ${GREEN}✅${NC} Redis — PONG"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}❌${NC} Redis — Not responding"
    FAIL=$((FAIL + 1))
  fi

  echo ""
  echo "  Ingress & TLS:"
  kubectl get certificates -n rt19 --no-headers 2>/dev/null | while read -r line; do
    CERT_NAME=$(echo "$line" | awk '{print $1}')
    CERT_READY=$(echo "$line" | awk '{print $2}')
    if [ "$CERT_READY" = "True" ]; then
      echo -e "    ${GREEN}✅${NC} $CERT_NAME — Ready"
    else
      echo -e "    ${RED}❌${NC} $CERT_NAME — Not Ready"
    fi
  done
else
  echo -e "  ${YELLOW}⚠️${NC}  kubectl not available — skipping internal checks"
  echo "  Run: az aks get-credentials --resource-group runtimeai-rg --name runtimeai-aks"
fi

echo ""
echo "============================================"
echo "  Results: ✅ $PASS passed | ❌ $FAIL failed | ⚠️ $WARN warnings"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

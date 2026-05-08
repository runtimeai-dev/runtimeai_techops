#!/bin/bash
# status.sh — Check the status of all rt19 services
set -eo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════"
echo "  RuntimeAI rt19 Pod — Status Check"
echo "═══════════════════════════════════════════════════"

# Nodes
echo ""
echo "Nodes:"
kubectl get nodes -o wide 2>/dev/null | head -5

# Pods
echo ""
echo "Pods (rt19):"
kubectl get pods -n rt19 --no-headers 2>/dev/null | while read line; do
  if echo "$line" | grep -q "Running"; then
    echo -e "  ${GREEN}$line${NC}"
  else
    echo -e "  ${RED}$line${NC}"
  fi
done

echo ""
echo "Pods (runtimeai-landing):"
kubectl get pods -n runtimeai-landing --no-headers 2>/dev/null | grep -v "cm-acme" | while read line; do
  if echo "$line" | grep -q "Running"; then
    echo -e "  ${GREEN}$line${NC}"
  else
    echo -e "  ${RED}$line${NC}"
  fi
done

# Certificates
echo ""
echo "TLS Certificates:"
kubectl get certificate -A 2>/dev/null | head -10

# Ingress
echo ""
echo "Ingress:"
kubectl get ingress -A 2>/dev/null | head -10

# Health checks
echo ""
echo "Health Checks:"
for url in "https://runtimeai.io" "https://app.rt19.runtimeai.io" "https://api.rt19.runtimeai.io" "https://admin.runtimeai.io"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
  if [ "$STATUS" == "200" ] || [ "$STATUS" == "308" ]; then
    echo -e "  ${GREEN}✅ $url → HTTP $STATUS${NC}"
  else
    echo -e "  ${RED}❌ $url → HTTP $STATUS${NC}"
  fi
done

echo ""
echo "═══════════════════════════════════════════════════"

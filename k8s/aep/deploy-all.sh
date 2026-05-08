#!/usr/bin/env bash
# Deploy all AEP services to the 'aep' namespace on rt19.
# Usage: bash deploy-all.sh [--dry-run]
set -euo pipefail

DRY_RUN=""
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN="--dry-run=client"; fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="runtimeaicr.azurecr.io/aep"

SERVICES=(
  "kya:8301"
  "cost-control:8302"
  "audit-black-box:8303"
  "pii-shield:8304"
  "observability:8305"
  "fraud-shield:8306"
  "memory-vault:8307"
  "commerce-rails:8308"
  "commerce-protocol:8309"
  "marketplace:8310"
  "developer-hub:8311"
  "contract-manager:8312"
  "procurement-hub:8313"
  "finance-rail:8314"
  "agent-builder-factory:8316"
)

echo "=== AEP K8s Deploy ==="
echo "Namespace: aep | Registry: $REGISTRY"
echo ""

# Namespace + config
kubectl apply $DRY_RUN -f "$SCRIPT_DIR/namespace.yaml"
kubectl apply $DRY_RUN -f "$SCRIPT_DIR/configmap.yaml"
kubectl apply $DRY_RUN -f "$SCRIPT_DIR/network-policy.yaml"

echo ""
echo "Apply secret.yaml manually with real values before deploying:"
echo "  kubectl apply -f $SCRIPT_DIR/secret.yaml"
echo ""

# Services
for PAIR in "${SERVICES[@]}"; do
  SVC="${PAIR%%:*}"
  PORT="${PAIR##*:}"
  echo "  deploying $SVC (port $PORT)..."
  kubectl apply $DRY_RUN -f "$SCRIPT_DIR/services/$SVC.yaml"
done

echo ""
echo "=== Rollout status ==="
for PAIR in "${SERVICES[@]}"; do
  SVC="${PAIR%%:*}"
  if [ -z "$DRY_RUN" ]; then
    kubectl rollout status deployment/"$SVC" -n aep --timeout=120s || echo "  WARN: $SVC rollout did not complete"
  fi
done

echo ""
echo "=== Health checks ==="
for PAIR in "${SERVICES[@]}"; do
  SVC="${PAIR%%:*}"
  PORT="${PAIR##*:}"
  if [ -z "$DRY_RUN" ]; then
    POD=$(kubectl get pod -n aep -l app="$SVC" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD" ]; then
      STATUS=$(kubectl exec -n aep "$POD" -- wget -qO- "http://localhost:$PORT/healthz" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "error")
      [ "$STATUS" = "ok" ] && echo "  ✓ $SVC" || echo "  ✗ $SVC (got: $STATUS)"
    else
      echo "  ✗ $SVC (no pod found)"
    fi
  fi
done

echo ""
echo "Deploy complete."

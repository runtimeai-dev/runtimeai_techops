#!/usr/bin/env bash
# Verifies that Control Plane components are running exclusively on CP nodes
# and Data Plane components are running exclusively on DP nodes.

set -euo pipefail

NAMESPACE="rt01"

echo "=== RuntimeAI Node Separation Verifier ==="

# Get nodes by label
CP_NODES=$(kubectl get nodes -l runtimeai-tier=cp -o jsonpath='{.items[*].metadata.name}')
DP_NODES=$(kubectl get nodes -l runtimeai-tier=dp -o jsonpath='{.items[*].metadata.name}')

if [ -z "$CP_NODES" ] || [ -z "$DP_NODES" ]; then
  echo "ERROR: Could not find distinct CP and DP nodes. Ensure nodepool labels are applied."
  exit 1
fi

echo "CP Nodes detected:"
for n in $CP_NODES; do echo "  - $n"; done
echo "DP Nodes detected:"
for n in $DP_NODES; do echo "  - $n"; done

echo ""
echo "=== Checking Component Node Assignment ==="

# Define expected DP components
DP_COMPONENTS="flow-enforcer mcp-gateway ai-finops-service billing-service bot-ca data-proxy discovery drift-engine marketplace-service ml-intelligence-service network-analyzer policy-manager sequence-modeler vault-broker vendor-wrapper verifier waf"

FAIL_COUNT=0
PASS_COUNT=0

# Loop all running pods in namespace
PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name,:spec.nodeName")

while read -r pod node; do
  [ -z "$pod" ] && continue

  IS_DP=0
  for dp_comp in $DP_COMPONENTS; do
    if [[ "$pod" == "$dp_comp"* ]]; then
      IS_DP=1
      break
    fi
  done

  # Determine if node is in CP or DP list
  NODE_TIER="unknown"
  if [[ "$CP_NODES" == *"$node"* ]]; then
    NODE_TIER="cp"
  elif [[ "$DP_NODES" == *"$node"* ]]; then
    NODE_TIER="dp"
  fi

  if [ "$IS_DP" -eq 1 ]; then
    if [ "$NODE_TIER" == "dp" ]; then
      echo "  [PASS] DP Pod: $pod -> Node: $node (DP Tier)"
      PASS_COUNT=$((PASS_COUNT+1))
    else
      echo "  [FAIL] DP Pod: $pod -> Node: $node (Expected DP, found $NODE_TIER)"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
  else
    if [ "$NODE_TIER" == "cp" ]; then
      echo "  [PASS] CP Pod: $pod -> Node: $node (CP Tier)"
      PASS_COUNT=$((PASS_COUNT+1))
    else
      echo "  [FAIL] CP Pod: $pod -> Node: $node (Expected CP, found $NODE_TIER)"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
  fi
done <<< "$PODS"

echo "================================================="
echo "Verification Complete. $PASS_COUNT pods correctly assigned."
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAILURE: $FAIL_COUNT pods are running on the WRONG nodepool."
  exit 1
else
  echo "SUCCESS: 100% strict CP/DP node separation verified."
  exit 0
fi

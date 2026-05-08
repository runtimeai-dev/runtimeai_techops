#!/bin/bash
set -e
source "$(dirname "$0")/common.sh"

echo "Running Backend API Tests..."

# 1. Login (Azure-aware via common.sh)
login

# 2. Control Plane Health / Dashboard Summary
echo "--- Dashboard Summary (Control Plane) ---"
auth_curl "${CONTROL_PLANE_URL}/api/dashboard/summary" | jq .

# 3. Discovery Findings (via Control Plane proxy on Azure)
echo "--- Discovery Findings ---"
auth_curl "${CONTROL_PLANE_URL}/api/discovery/findings" | jq .

# 4. Drift Engine (via Control Plane)
echo "--- Drift Engine (via Control Plane) ---"
echo "Checking Drift Findings..."
auth_curl "${CONTROL_PLANE_URL}/api/dashboard/drift?status=OPEN" | jq .

# 5. Policy Guardrails (via Control Plane)
echo "--- Policy Guardrails ---"
auth_curl "${CONTROL_PLANE_URL}/api/policy/guardrails" | jq .

echo "Backend API Tests Completed."

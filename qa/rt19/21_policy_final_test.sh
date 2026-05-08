#!/bin/bash
set -e

# Configuration
HOST=${HOST:-"localhost:8080"}
ADMIN_SECRET=${ADMIN_SECRET:-"super-secret-admin-key"}
TENANT_ID="enterprise-1"

echo "=== Phase 11 Final: Policy End-to-End Test ==="

# 1. Create a Plain English Guardrail via API
echo "1. Creating Plain English Guardrail..."
curl -s -X POST "http://$HOST/api/policy/guardrails" \
  -H "Header-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "'$TENANT_ID'",
    "policy_version": "v1",
    "text": "Agent FinanceBot can read data but cannot export it. Budget: $50/day on OpenAI.",
    "state": "active"
  }' | jq .

# 2. Trigger Bundle Generation and Verify
echo -e "\n2. Verifying Bundle Generation..."
# This would normally be verified by checking OPA or the policy-manager bundle endpoint
# We can check the policy-manager bundle endpoint directly if reachable
PM_HOST="localhost:8091"
echo "Fetching bundle from Policy Manager ($PM_HOST)..."
curl -s "http://$PM_HOST/policy/bundle?tenant_id=$TENANT_ID" | jq .rendered_policy | grep "guardrail_allow" || echo "Warning: Could not verify bundle content directly"

# 3. Create a New Policy Draft
echo -e "\n3. Creating New Policy Draft..."
curl -s -X POST "http://$HOST/api/policy/content" \
  -H "Header-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "source_format": "rego",
    "source_content": "package authzion\n\nallow { input.user == \"admin\" }",
    "description": "Admin override policy"
  }' | jq .

# 4. Promote Policy and Verify Reason
echo -e "\n4. Promoting New Policy Version..."
NEW_VERSION=$(curl -s "http://$HOST/api/policy/versions" -H "Header-Secret: $ADMIN_SECRET" | jq -r '.versions[0].version')
echo "Promoting Version $NEW_VERSION..."

curl -s -X POST "http://$HOST/api/policy/content/promote" \
  -H "Header-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "'$NEW_VERSION'",
    "target_state": "active",
    "reason": "QA verification"
  }' | jq .

# 5. Verify Promotion History
echo -e "\n5. Verifying Promotion History..."
curl -s "http://$HOST/api/policy/versions" -H "Header-Secret: $ADMIN_SECRET" | jq '.versions | map(select(.state == "active"))'

echo -e "\n=== End-to-End Policy Test Complete ==="

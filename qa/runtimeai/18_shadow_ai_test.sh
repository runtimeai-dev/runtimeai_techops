#!/bin/bash

# Configuration
API_KEY_SECRET="dev-secret-key"
DISCOVERY_URL="http://localhost:8090"
TENANT_ID="bank-a"

log() {
    echo "[$(date +'%H:%M:%S')] $1"
}

fail() {
    log "❌ $1"
    exit 1
}

# 1. Health Check
log "Checking Discovery Service Health..."
curl -s "$DISCOVERY_URL/health" | grep "ok" || fail "Discovery Service not healthy"

# 2. Set Discovery Mode to Active
log "Setting Discovery Mode to ACTIVE..."
curl -s -X PUT "$DISCOVERY_URL/v1/discovery/settings?tenant_id=$TENANT_ID" \
  -H "Authorization: Bearer $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"mode": "active"}' | jq .

# Verify Mode
MODE=$(curl -s "$DISCOVERY_URL/v1/discovery/settings?tenant_id=$TENANT_ID" \
  -H "Authorization: Bearer $API_KEY_SECRET" | jq -r .mode)

if [ "$MODE" != "active" ]; then
  fail "Failed to set Discovery Mode to Active (Got: $MODE)"
fi
log "✅ Discovery Mode is ACTIVE"

# 3. Simulate Shadow AI Traffic (OpenAI)
log "Simulating unauthorized OpenAI traffic..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

curl -s -X POST "$DISCOVERY_URL/simulate/network_traffic?tenant_id=$TENANT_ID" \
  -H "Authorization: Bearer $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d "[
    {
      \"domain\": \"api.openai.com\",
      \"path\": \"/v1/chat/completions\",
      \"method\": \"POST\",
      \"headers\": {
        \"Authorization\": \"Bearer sk-...\",
        \"OpenAI-Organization\": \"org-123\",
        \"Content-Type\": \"application/json\"
      },
      \"user_agent\": \"openai-python/1.3.0\",
      \"timestamp\": \"$TIMESTAMP\"
    }
  ]" | jq .

# 4. Check Inbox for Shadow AI Finding
log "Checking Discovery Inbox for findings..."
sleep 2

INBOX=$(curl -s "$DISCOVERY_URL/v1/discovery/inbox?tenant_id=$TENANT_ID" \
  -H "Authorization: Bearer $API_KEY_SECRET")

# Look for agent with name 'Shadow Openai' and status 'UNREGISTERED'
FOUND=$(echo "$INBOX" | jq '.inbox[] | select(.name == "Shadow Openai" and .status == "UNREGISTERED")')

if [ -z "$FOUND" ]; then
  log "Inbox content: $INBOX"
  fail "Shadow AI agent (Shadow Openai) not found in Inbox!"
else
  log "✅ Shadow AI agent detected in Inbox"
fi

# 5. Review Findings Details
echo "$FOUND" | jq .

# 6. Reset Discovery Mode to Passive
log "Resetting Discovery Mode to PASSIVE..."
curl -s -X PUT "$DISCOVERY_URL/v1/discovery/settings?tenant_id=$TENANT_ID" \
  -H "Authorization: Bearer $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"mode": "passive"}' | jq .

log "✅ Shadow AI Verification Complete"
exit 0

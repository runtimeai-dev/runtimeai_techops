#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Verifying Identity DNS ===${NC}"

# 0. Check dependencies
if ! command -v dig &> /dev/null; then
    echo -e "${RED}[ERROR] 'dig' command not found. Please install dnsutils or bind-tools.${NC}"
    exit 1
fi

DNS_PORT=1053
DNS_SERVER="127.0.0.1"

# 1. Setup: Create a valid agent
AGENT_ID="dns-test-agent"
TENANT="${TENANT_ID:-bank-a}"

log() {
    echo -e "${GREEN}[QA] $1${NC}"
}

log "Ensuring agent '$AGENT_ID' exists and is ACTIVE..."
docker exec docker-compose-postgres-1 psql -U postgres -d authzion -c "INSERT INTO agents (tenant_id, agent_id, name, owner, environment, skills, source, last_seen, status, verification_status, endpoint) VALUES ('$TENANT', '$AGENT_ID', 'DNS Test Agent', 'alice@company.com', 'prod', '[]', 'manual', now(), 'active', 'verified', '10.0.0.100') ON CONFLICT (tenant_id, agent_id) DO UPDATE SET status='active', verification_status='verified', endpoint='10.0.0.100';" > /dev/null

# 2. Test 1: Resolve Custom Domain
DOMAIN="$AGENT_ID.runtimeai.io"
log "Querying $DOMAIN @ $DNS_SERVER:$DNS_PORT..."

# Use +short to just get the IP
IP=$(dig @$DNS_SERVER -p $DNS_PORT +short $DOMAIN)
log "Result: $IP"

if [[ "$IP" == "10.0.0.100" ]]; then
    echo -e "${GREEN}[PASS] Resolved $DOMAIN to Mock IP 10.0.0.100${NC}"
else
    echo -e "${RED}[FAIL] Expected 10.0.0.100, got '$IP'${NC}"
    exit 1
fi

# 3. Test 2: Forwarding (Recursive)
EXTERNAL_DOMAIN="google.com"
log "Querying $EXTERNAL_DOMAIN (Forwarding Test)..."

IP_EXT=$(dig @$DNS_SERVER -p $DNS_PORT +short $EXTERNAL_DOMAIN | head -n 1)
log "Result: $IP_EXT"

if [[ -n "$IP_EXT" && "$IP_EXT" != "10.0.0.100" ]]; then
     echo -e "${GREEN}[PASS] Forwarded $EXTERNAL_DOMAIN to real IP ($IP_EXT)${NC}"
else
     echo -e "${RED}[FAIL] Forwarding failed or returned mock IP. Got: '$IP_EXT'${NC}"
     exit 1
fi

log "Identity DNS Verification Complete!"
exit 0

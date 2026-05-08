#!/bin/bash
# seed.sh — Seed demo tenants into rt19 via control-plane admin API
# Usage:
#   ./seed.sh                    # Seed all demo tenants
#   ./seed.sh --delete TENANT_ID # Delete a specific tenant
set -eo pipefail

# ─── Configuration ──────────────────────────────────────────────────
CP_URL="${CP_URL:-https://api.rt19.runtimeai.io}"

# Get admin secret from the running pod
ADMIN_SECRET="${ADMIN_SECRET:-$(kubectl exec deploy/control-plane -n rt19 -- cat /tmp/runtimeai-admin-secret.txt 2>/dev/null || echo "")}"

if [ -z "$ADMIN_SECRET" ]; then
  echo "❌ Could not retrieve admin secret. Set ADMIN_SECRET env var or ensure control-plane is running."
  exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

api() {
  local method=$1 endpoint=$2 data=${3:-}
  curl -s -X "$method" "$CP_URL$endpoint" \
    -H "Content-Type: application/json" \
    -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
    ${data:+-d "$data"}
}

echo "═══════════════════════════════════════════════════"
echo "  RuntimeAI rt19 — Demo Tenant Seeding"
echo "  Target: $CP_URL"
echo "═══════════════════════════════════════════════════"

# ─── Delete mode ────────────────────────────────────────────────────
if [ "${1:-}" = "--delete" ] && [ -n "${2:-}" ]; then
  echo "Deleting tenant: $2"
  api DELETE "/api/admin/tenants/$2"
  echo ""
  exit 0
fi

# ─── Seed demo tenants (bash 3.2 compatible — no associative arrays) ─
# Format: TENANT_ID|JSON_PAYLOAD
TENANTS=(
  'felt-sense-ai|{"tenant_id":"felt-sense-ai","name":"Felt Sense AI","owner_id":"felt-sense-owner","environment":"production","admin_email":"admin@felt-sense-ai.ai"}'
  'bank-a|{"tenant_id":"bank-a","name":"Bank A (Enterprise Demo)","owner_id":"bank-a-owner","environment":"production","admin_email":"a-operator@bank-a.local"}'
  'qa-testing|{"tenant_id":"qa-testing","name":"QA Testing","owner_id":"qa-owner","environment":"staging","admin_email":"qa@runtimeai.io"}'
  'acme-corp|{"tenant_id":"acme-corp","name":"Acme Corporation","owner_id":"acme-owner","environment":"production","admin_email":"admin@acme-corp.io"}'
)

CREDENTIALS_FILE="./rt19_demo_credentials.json"
echo "[" > "$CREDENTIALS_FILE"
FIRST=true

for entry in "${TENANTS[@]}"; do
  tenant_id="${entry%%|*}"
  tenant_data="${entry#*|}"

  echo ""
  echo "Creating tenant: $tenant_id"
  RESPONSE=$(api POST "/api/admin/tenants" "$tenant_data")

  if echo "$RESPONSE" | grep -q '"error"'; then
    echo -e "${RED}  ❌ Failed: $RESPONSE${NC}"
  else
    PASSWORD=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('password','N/A'))" 2>/dev/null || echo "N/A")
    EMAIL=$(echo "$tenant_data" | python3 -c "import sys,json; print(json.load(sys.stdin)['admin_email'])")
    echo -e "${GREEN}  ✅ Created: $tenant_id ($EMAIL / $PASSWORD)${NC}"

    if [ "$FIRST" = true ]; then FIRST=false; else echo "," >> "$CREDENTIALS_FILE"; fi
    cat >> "$CREDENTIALS_FILE" <<EOF
  {"tenant_id":"$tenant_id","email":"$EMAIL","password":"$PASSWORD"}
EOF
  fi
done

echo "]" >> "$CREDENTIALS_FILE"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ Seeding complete. Credentials: $CREDENTIALS_FILE"
echo "═══════════════════════════════════════════════════"
cat "$CREDENTIALS_FILE"

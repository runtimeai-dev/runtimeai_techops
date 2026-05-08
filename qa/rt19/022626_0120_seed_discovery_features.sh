#!/usr/bin/env bash
# IF-DSC-002 through IF-DSC-011: Seed Discovery Features Data
# Idempotent: Safe to run multiple times
set -eo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
TENANT_ID="${TENANT_ID:-bank-a}"
EMAIL="${EMAIL:-a-operator@bank-a.local}"
PASSWORD="${PASSWORD:-password123}"

echo "=== Seeding Discovery Features Data ==="
echo "Base URL: $BASE_URL | Tenant: $TENANT_ID"

# Login
TOKEN=$(curl -s -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | jq -r '.token // empty')

if [ -z "$TOKEN" ]; then
  COOKIE_AUTH=true
  AUTH_HEADER="-b /tmp/auth_cookies.txt"
  curl -s -c /tmp/auth_cookies.txt -X POST "$BASE_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" > /dev/null
else
  AUTH_HEADER="-H \"Authorization: Bearer $TOKEN\""
fi

do_curl() {
  local method=$1 url=$2 data=${3:-}
  if [ "$COOKIE_AUTH" = "true" ] 2>/dev/null; then
    if [ -n "$data" ]; then
      curl -s -b /tmp/auth_cookies.txt -X "$method" "$BASE_URL$url" -H "Content-Type: application/json" -d "$data"
    else
      curl -s -b /tmp/auth_cookies.txt -X "$method" "$BASE_URL$url"
    fi
  else
    if [ -n "$data" ]; then
      curl -s -H "Authorization: Bearer $TOKEN" -X "$method" "$BASE_URL$url" -H "Content-Type: application/json" -d "$data"
    else
      curl -s -H "Authorization: Bearer $TOKEN" -X "$method" "$BASE_URL$url"
    fi
  fi
}

# Seed discovery findings (IF-DSC-002)
echo "--- Seeding discovery findings ---"
FINDINGS=(
  '{"scanner_id":"aws","finding_type":"shadow_agent","severity":"critical","title":"Unregistered Lambda AI agent in us-east-1","description":"Detected an AI agent running in Lambda function processing customer data without registration","agent_fingerprint":"sha256:aws-lambda-ai-001"}'
  '{"scanner_id":"azure","finding_type":"compliance_gap","severity":"high","title":"Azure AI Studio model without governance policy","description":"AI model deployed in Azure AI Studio lacks required RuntimeAI governance policy","agent_fingerprint":"sha256:azure-ai-studio-002"}'
  '{"scanner_id":"vscode","finding_type":"shadow_extension","severity":"medium","title":"Unauthorized Copilot extension detected","description":"GitHub Copilot extension installed outside of approved channels","agent_fingerprint":"sha256:vscode-copilot-003"}'
  '{"scanner_id":"process","finding_type":"unknown_framework","severity":"high","title":"LangChain process on production server","description":"LangChain framework detected running on production endpoint without agent registration"}'
  '{"scanner_id":"github","finding_type":"automation_script","severity":"low","title":"AI-assisted CI/CD pipeline script","description":"GitHub Actions workflow using AI for code review suggestions"}'
  '{"scanner_id":"mcp","finding_type":"ungoverned_tool","severity":"critical","title":"MCP server with filesystem access unrestricted","description":"MCP Filesystem server running without RuntimeAI governance wrapper"}'
  '{"scanner_id":"ai_assistant","finding_type":"desktop_app","severity":"medium","title":"Claude Desktop app with corporate data access","description":"Claude Desktop detected with access to shared network drives"}'
  '{"scanner_id":"aws","finding_type":"data_exfil_risk","severity":"high","title":"SageMaker endpoint sending data to external API","description":"AI model on SageMaker sending inference results to unauthorized endpoint"}'
)

for finding in "${FINDINGS[@]}"; do
  result=$(do_curl POST "/api/discovery/findings" "$finding" 2>/dev/null)
  title=$(echo "$finding" | jq -r '.title // "unknown"')
  if echo "$result" | jq -e '.id' > /dev/null 2>&1; then
    echo "  ✓ Finding created: $title"
  else
    echo "  ⚠ Finding may already exist: $title"
  fi
done

echo "✓ Discovery findings seeded via API"

# Seed scanner configs (IF-DSC-003)
echo "--- Seeding scanner configs ---"
SCANNERS=("aws" "azure" "gcp" "vscode" "process" "network" "github" "mcp" "ai_assistant")
SCHEDULES=('0 */6 * * *' '0 */12 * * *' '0 0 * * *' '0 0 * * 1' '*/30 * * * *' '0 */6 * * *' '0 0 * * *' '0 */12 * * *' '0 0 * * 1')

for i in "${!SCANNERS[@]}"; do
  scanner="${SCANNERS[$i]}"
  schedule="${SCHEDULES[$i]}"
  do_curl PUT "/api/discovery/scanner-configs/$scanner" "{\"enabled\":true,\"schedule_cron\":\"$schedule\",\"config\":{\"auto_register\":false}}" > /dev/null 2>&1 || true
  echo "  ✓ Configured scanner: $scanner ($schedule)"
done

# Seed import data (IF-DSC-009)
echo "--- Seeding third-party import data ---"
do_curl POST "/api/discovery/import" '{
  "source": "wiz",
  "format": "json",
  "agents": [
    {"name":"wiz-detected-lambda-agent","fingerprint":"wiz-import-001","owner":"cloud-team@example.com"},
    {"name":"wiz-sagemaker-model","fingerprint":"wiz-import-002","owner":"ml-team@example.com"},
    {"name":"wiz-bedrock-app","fingerprint":"wiz-import-003","owner":"app-team@example.com"}
  ]
}' | jq -r '. | "  ✓ Imported: \(.imported), Skipped: \(.skipped)"' 2>/dev/null || echo "  ✓ Import seeded"

# Seed pipeline registrations (IF-DSC-004)
echo "--- Seeding pipeline registrations ---"
do_curl POST "/api/discovery/register-from-blueprint" '{
  "fingerprint":"sha256:aws-lambda-ai-001",
  "name":"Finance Copilot Agent",
  "sponsor_email":"ciso@bank-a.local",
  "justification":"Critical business process agent",
  "environment":"production"
}' | jq -r '. | "  ✓ Registered: \(.agent_id)"' 2>/dev/null || echo "  ✓ Registration seeded"

echo ""
echo "=== Discovery Features Seeding Complete ==="
echo "Verify at: $BASE_URL/discovery/findings"
echo "Verify at: $BASE_URL/discovery/scanner-config"
echo "Verify at: $BASE_URL/discovery/registrations"
echo "Verify at: $BASE_URL/discovery/scanner-types"
echo "Verify at: $BASE_URL/discovery/import"

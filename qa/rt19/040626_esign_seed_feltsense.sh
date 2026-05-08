#!/bin/bash
set -euo pipefail

##############################################################################
# OPER-RT19-036 GAP-6: eSign Dashboard Seed Data for Felt Sense Demo
#
# Creates seed data via eSign API endpoints for the Felt Sense tenant.
# This ensures the dashboard pages have realistic demo data.
##############################################################################

BASE="${1:-http://localhost:4000}"
TENANT_ID="${2:-feltsense}"
COOKIE="/tmp/esign_seed_cookies.txt"

CREATED=0
SKIPPED=0
ERRORS=0

created() { echo -e "\033[0;32m  + CREATED\033[0m $1"; CREATED=$((CREATED + 1)); }
skipped() { echo -e "\033[0;33m  ○ SKIPPED\033[0m $1"; SKIPPED=$((SKIPPED + 1)); }
errored() { echo -e "\033[0;31m  ✗ ERROR\033[0m $1 — $2"; ERRORS=$((ERRORS + 1)); }

# Helper: POST to create seed data
seed_post() {
  local path="$1"
  local label="$2"
  local data="$3"

  RESULT=$(curl -sk -b "$COOKIE" -X POST "$BASE/api/proxy/esign$path" \
    -H "Content-Type: application/json" \
    -d "$data" 2>&1)
  HTTP=$(curl -sk -o /dev/null -w '%{http_code}' -b "$COOKIE" -X POST "$BASE/api/proxy/esign$path" \
    -H "Content-Type: application/json" \
    -d "$data")

  if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ]; then
    created "$label"
  elif [ "$HTTP" = "409" ] || [ "$HTTP" = "422" ]; then
    skipped "$label (already exists or invalid)"
  else
    errored "$label" "HTTP $HTTP"
  fi
}

echo -e "\n\033[1;34m━━━ OPER-RT19-036 GAP-6: eSign Seed Data for Felt Sense ━━━\033[0m"
echo -e "Base: $BASE | Tenant: $TENANT_ID\n"

# ── Login ──
echo -e "\033[1;33m▸ Authenticating...\033[0m"
curl -sk -c "$COOKIE" -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"tenant_id\": \"$TENANT_ID\", \"email\": \"a-operator@bank-a.local\", \"password\": \"password123\"}" > /dev/null 2>&1
echo -e "\033[0;32m  ✓\033[0m Logged in\n"

# ── Contacts ──
echo -e "\033[1;33m▸ Seeding Contacts\033[0m"
seed_post "/api/v1/sign/contacts" "Contact: Sarah Chen (VP Legal)" \
  '{"name":"Sarah Chen","email":"sarah.chen@feltsense.io","company":"Felt Sense Inc","title":"VP Legal","phone":"+1-555-0101"}'
seed_post "/api/v1/sign/contacts" "Contact: James Wilson (CFO)" \
  '{"name":"James Wilson","email":"james.wilson@feltsense.io","company":"Felt Sense Inc","title":"CFO","phone":"+1-555-0102"}'
seed_post "/api/v1/sign/contacts" "Contact: Maria Rodriguez (External Counsel)" \
  '{"name":"Maria Rodriguez","email":"maria@bakermckenzie.example","company":"Baker McKenzie","title":"Senior Partner","phone":"+1-555-0200"}'
seed_post "/api/v1/sign/contacts" "Contact: Alex Park (Vendor)" \
  '{"name":"Alex Park","email":"alex.park@acme-vendor.example","company":"Acme Vendor Corp","title":"Account Manager","phone":"+1-555-0301"}'
seed_post "/api/v1/sign/contacts" "Contact: Priya Patel (Board Member)" \
  '{"name":"Priya Patel","email":"priya.patel@feltsense.io","company":"Felt Sense Inc","title":"Board Member","phone":"+1-555-0103"}'

# ── Folders ──
echo -e "\n\033[1;33m▸ Seeding Folders\033[0m"
seed_post "/api/v1/sign/folders" "Folder: Contracts" \
  '{"name":"Contracts","description":"All active contracts and agreements"}'
seed_post "/api/v1/sign/folders" "Folder: NDAs" \
  '{"name":"NDAs","description":"Non-disclosure agreements"}'
seed_post "/api/v1/sign/folders" "Folder: Board Resolutions" \
  '{"name":"Board Resolutions","description":"Board meeting resolutions and minutes"}'
seed_post "/api/v1/sign/folders" "Folder: Vendor Agreements" \
  '{"name":"Vendor Agreements","description":"Third-party vendor contracts"}'
seed_post "/api/v1/sign/folders" "Folder: HR Documents" \
  '{"name":"HR Documents","description":"Employee onboarding and HR paperwork"}'

# ── Notification Templates ──
echo -e "\n\033[1;33m▸ Seeding Notification Templates\033[0m"
seed_post "/api/v1/sign/notifications/templates" "Template: Document Ready for Signature" \
  '{"name":"document_ready","subject":"{{document_name}} is ready for your signature","body":"Hi {{signer_name}},\n\n{{sender_name}} has sent you {{document_name}} for your signature.\n\nPlease review and sign at your earliest convenience.\n\nBest regards,\n{{company_name}}","type":"email"}'
seed_post "/api/v1/sign/notifications/templates" "Template: Signing Completed" \
  '{"name":"signing_completed","subject":"{{document_name}} has been signed by all parties","body":"Hi {{sender_name}},\n\nAll parties have signed {{document_name}}.\n\nYou can download the completed package from your dashboard.\n\nBest regards,\n{{company_name}}","type":"email"}'
seed_post "/api/v1/sign/notifications/templates" "Template: Signature Reminder" \
  '{"name":"signing_reminder","subject":"Reminder: {{document_name}} awaits your signature","body":"Hi {{signer_name}},\n\nThis is a friendly reminder that {{document_name}} is still waiting for your signature.\n\nThe document was sent on {{sent_date}}.\n\nBest regards,\n{{company_name}}","type":"email"}'

# ── Reminders ──
echo -e "\n\033[1;33m▸ Seeding Reminder Schedules\033[0m"
seed_post "/api/v1/sign/reminders" "Reminder: Daily pending docs" \
  '{"name":"daily_reminder","frequency":"daily","template_name":"signing_reminder","enabled":true}'

# ── Agent Keys (if agent signing is enabled) ──
echo -e "\n\033[1;33m▸ Seeding Agent Signing Keys\033[0m"
seed_post "/api/v1/sign/agent/keys" "Agent Key: Compliance Bot" \
  '{"name":"compliance-bot","algorithm":"ed25519","metadata":{"purpose":"automated_compliance_signing","owner":"platform"}}'
seed_post "/api/v1/sign/agent/keys" "Agent Key: HR Automation" \
  '{"name":"hr-automation","algorithm":"ed25519","metadata":{"purpose":"hr_document_signing","owner":"hr_department"}}'

# ── Agent Signing Policies ──
echo -e "\n\033[1;33m▸ Seeding Agent Signing Policies\033[0m"
seed_post "/api/v1/sign/agent/policies" "Policy: NDA Auto-sign" \
  '{"name":"nda-auto-sign","document_types":["nda"],"max_value_usd":0,"require_human_review":false,"allowed_key_names":["compliance-bot"]}'
seed_post "/api/v1/sign/agent/policies" "Policy: Contracts Require Review" \
  '{"name":"contract-review","document_types":["contract","agreement"],"max_value_usd":50000,"require_human_review":true,"allowed_key_names":["compliance-bot","hr-automation"]}'

# ── In-App Notifications ──
echo -e "\n\033[1;33m▸ Seeding In-App Notifications\033[0m"
seed_post "/api/v1/sign/notifications/inapp" "Notification: Welcome" \
  '{"title":"Welcome to Felt Sense eSign","message":"Your eSign workspace is ready. Start by uploading your first document.","type":"info","priority":"normal"}'
seed_post "/api/v1/sign/notifications/inapp" "Notification: Compliance Update" \
  '{"title":"SOC 2 Compliance: All checks passed","message":"Your latest compliance audit has verified all eSign operations meet SOC 2 requirements.","type":"success","priority":"normal"}'

# ── Summary ──
echo -e "\n\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;32m  CREATED: $CREATED\033[0m"
if [ "$SKIPPED" -gt 0 ]; then
  echo -e "\033[1;33m  SKIPPED: $SKIPPED\033[0m"
fi
if [ "$ERRORS" -gt 0 ]; then
  echo -e "\033[1;31m  ERRORS:  $ERRORS\033[0m"
fi
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

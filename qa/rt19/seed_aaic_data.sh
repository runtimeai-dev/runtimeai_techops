#!/bin/bash
# ============================================================
# AAIC Seed Data — API-Only
# Seeds demo audit firms, auditors, engagements, evidence,
# findings, and certificates using AAIC API endpoints exclusively.
#
# NO DIRECT SQL — all data flows through the service layer,
# respecting RLS, validation, and audit logging.
#
# Usage: ./qa_testing_local/seed_aaic_data.sh
# Env:   AAIC_URL (default: http://localhost:5056)
# ============================================================
set -euo pipefail

AAIC_URL="${AAIC_URL:-http://localhost:5056}"

echo "═══════════════════════════════════════"
echo "  AAIC Seed Data — API-Only"
echo "  Target: ${AAIC_URL}"
echo "═══════════════════════════════════════"
echo ""

# Helper: POST JSON and extract field from response
api_post() {
  local endpoint="$1"
  local data="$2"
  local url="${AAIC_URL}${endpoint}"
  local response
  response=$(curl -sf -X POST "${url}" \
    -H "Content-Type: application/json" \
    -d "${data}" 2>/dev/null) || {
    echo "  ❌ FAILED: POST ${endpoint}"
    echo "     Response: $(curl -s -X POST "${url}" -H "Content-Type: application/json" -d "${data}" 2>&1)"
    return 1
  }
  echo "${response}"
}

# Helper: PATCH endpoint
api_patch() {
  local endpoint="$1"
  local url="${AAIC_URL}${endpoint}"
  curl -sf -X PATCH "${url}" -H "Content-Type: application/json" 2>/dev/null || {
    echo "  ❌ FAILED: PATCH ${endpoint}"
    return 1
  }
}

# ── 1. Register Audit Firms ──
echo "📋 Registering Audit Firms..."

FIRM1=$(api_post "/api/aaic/auditor/firms/register" '{
  "firm_name": "CyberAudit Partners",
  "contact_email": "contact@cyberaudit.example.com",
  "contact_phone": "+1-555-0101",
  "firm_country": "US",
  "audit_firm_type": "boutique",
  "specializations": ["SOC2_TYPE1", "SOC2_TYPE2", "ISO27001", "ISO42001", "HIPAA"],
  "industries": ["fintech", "healthcare", "saas"],
  "admin_full_name": "Jane Smith, CPA, CISA",
  "admin_email": "jane.smith@cyberaudit.example.com",
  "admin_password": "CyberAudit2026!Secure"
}')
FIRM1_ID=$(echo "${FIRM1}" | jq -r '.id // empty')
echo "  ✅ CyberAudit Partners: ${FIRM1_ID}"

FIRM2=$(api_post "/api/aaic/auditor/firms/register" '{
  "firm_name": "Deloitte AI Risk Advisory",
  "contact_email": "ai-advisory@deloitte.example.com",
  "contact_phone": "+1-555-0102",
  "firm_country": "US",
  "audit_firm_type": "big4",
  "specializations": ["SOC2_TYPE2", "ISO27001", "ISO42001", "EU_AI_ACT", "FEDRAMP_HIGH", "NIST_AI_RMF"],
  "industries": ["finance", "government", "defense", "healthcare"],
  "admin_full_name": "Mike Johnson, CPA",
  "admin_email": "mike.johnson@deloitte.example.com",
  "admin_password": "Deloitte2026!Secure"
}')
FIRM2_ID=$(echo "${FIRM2}" | jq -r '.id // empty')
echo "  ✅ Deloitte AI Risk Advisory: ${FIRM2_ID}"

FIRM3=$(api_post "/api/aaic/auditor/firms/register" '{
  "firm_name": "AI Compliance Solutions",
  "contact_email": "info@aicompliance.example.com",
  "contact_phone": "+1-555-0103",
  "firm_country": "US",
  "audit_firm_type": "mid_tier",
  "specializations": ["SOC2_TYPE2", "ISO42001", "EU_AI_ACT", "NIST_AI_RMF"],
  "industries": ["technology", "fintech", "energy"],
  "admin_full_name": "Sarah Chen, CRISC",
  "admin_email": "sarah.chen@aicompliance.example.com",
  "admin_password": "AICompliance2026!Secure"
}')
FIRM3_ID=$(echo "${FIRM3}" | jq -r '.id // empty')
echo "  ✅ AI Compliance Solutions: ${FIRM3_ID}"

FIRM4=$(api_post "/api/aaic/auditor/firms/register" '{
  "firm_name": "EU AI Act Specialists GmbH",
  "contact_email": "contact@euaiact.example.com",
  "contact_phone": "+49-30-555-0104",
  "firm_country": "DE",
  "audit_firm_type": "boutique",
  "specializations": ["EU_AI_ACT", "ISO42001", "GDPR"],
  "industries": ["automotive", "manufacturing", "fintech"],
  "admin_full_name": "Hans Mueller, ISO Lead",
  "admin_email": "hans.mueller@euaiact.example.com",
  "admin_password": "EUAIAct2026!Secure"
}')
FIRM4_ID=$(echo "${FIRM4}" | jq -r '.id // empty')
echo "  ✅ EU AI Act Specialists GmbH: ${FIRM4_ID}"

FIRM5=$(api_post "/api/aaic/auditor/firms/register" '{
  "firm_name": "Federal Compliance Corp",
  "contact_email": "info@fedcompliance.example.com",
  "contact_phone": "+1-555-0105",
  "firm_country": "US",
  "audit_firm_type": "mid_tier",
  "specializations": ["FEDRAMP_LOW", "FEDRAMP_MODERATE", "FEDRAMP_HIGH", "NIST_CSF", "SOC2_TYPE2"],
  "industries": ["government", "defense", "healthcare"],
  "admin_full_name": "Jennifer Martinez, CISM",
  "admin_email": "jennifer.martinez@fedcompliance.example.com",
  "admin_password": "FedCompliance2026!Secure"
}')
FIRM5_ID=$(echo "${FIRM5}" | jq -r '.id // empty')
echo "  ✅ Federal Compliance Corp: ${FIRM5_ID}"

echo ""

# ── 2. Verify Firms ──
echo "✅ Verifying Firms..."
for fid in "${FIRM1_ID}" "${FIRM2_ID}" "${FIRM3_ID}" "${FIRM4_ID}" "${FIRM5_ID}"; do
  if [ -n "${fid}" ] && [ "${fid}" != "null" ]; then
    api_patch "/api/aaic/admin/firms/${fid}/verify" > /dev/null 2>&1
    echo "  ✅ Verified: ${fid}"
  fi
done
echo ""

# ── 3. Login as Firm 1 Admin (for JWT token) ──
echo "🔑 Authenticating Firm 1 Admin..."
LOGIN_RESP=$(api_post "/api/aaic/auditor/firms/login" '{
  "email": "jane.smith@cyberaudit.example.com",
  "password": "CyberAudit2026!Secure"
}')
JWT=$(echo "${LOGIN_RESP}" | jq -r '.access_token // empty')
if [ -n "${JWT}" ] && [ "${JWT}" != "null" ]; then
  echo "  ✅ JWT obtained for jane.smith@cyberaudit.example.com"
else
  echo "  ⚠️  JWT not obtained (DB may not be available) — continuing without auth"
  JWT=""
fi
echo ""

# ── 4. Create Audit Engagements ──
echo "📝 Creating Audit Engagements..."

if [ -n "${FIRM1_ID}" ] && [ "${FIRM1_ID}" != "null" ]; then
  ENG1=$(api_post "/api/aaic/enterprise/audit-requests" "{
    \"audit_firm_id\": \"${FIRM1_ID}\",
    \"framework\": \"SOC2_TYPE2\",
    \"audit_scope\": \"All AI agents and supporting infrastructure\",
    \"enterprise_contact_name\": \"David Kim\",
    \"enterprise_contact_email\": \"compliance@feltsense.ai\",
    \"tenant_id\": \"feltsense\",
    \"contract_value\": 45000.00
  }")
  ENG1_ID=$(echo "${ENG1}" | jq -r '.id // empty')
  echo "  ✅ SOC2 Type II engagement: ${ENG1_ID}"
fi

if [ -n "${FIRM4_ID}" ] && [ "${FIRM4_ID}" != "null" ]; then
  ENG2=$(api_post "/api/aaic/enterprise/audit-requests" "{
    \"audit_firm_id\": \"${FIRM4_ID}\",
    \"framework\": \"EU_AI_ACT\",
    \"audit_scope\": \"High-risk AI classification assessment for EU market entry\",
    \"enterprise_contact_name\": \"David Kim\",
    \"enterprise_contact_email\": \"compliance@feltsense.ai\",
    \"tenant_id\": \"feltsense\",
    \"contract_value\": 35000.00
  }")
  ENG2_ID=$(echo "${ENG2}" | jq -r '.id // empty')
  echo "  ✅ EU AI Act engagement: ${ENG2_ID}"
fi

if [ -n "${FIRM2_ID}" ] && [ "${FIRM2_ID}" != "null" ]; then
  ENG3=$(api_post "/api/aaic/enterprise/audit-requests" "{
    \"audit_firm_id\": \"${FIRM2_ID}\",
    \"framework\": \"ISO42001\",
    \"audit_scope\": \"AI management system certification\",
    \"enterprise_contact_name\": \"David Kim\",
    \"enterprise_contact_email\": \"compliance@feltsense.ai\",
    \"tenant_id\": \"feltsense\",
    \"contract_value\": 75000.00
  }")
  ENG3_ID=$(echo "${ENG3}" | jq -r '.id // empty')
  echo "  ✅ ISO 42001 engagement: ${ENG3_ID}"
fi

if [ -n "${FIRM5_ID}" ] && [ "${FIRM5_ID}" != "null" ]; then
  ENG4=$(api_post "/api/aaic/enterprise/audit-requests" "{
    \"audit_firm_id\": \"${FIRM5_ID}\",
    \"framework\": \"FEDRAMP_MODERATE\",
    \"audit_scope\": \"FedRAMP Moderate baseline for government AI deployment\",
    \"enterprise_contact_name\": \"Jennifer Martinez\",
    \"enterprise_contact_email\": \"security@bank-a.local\",
    \"tenant_id\": \"bank-a\",
    \"contract_value\": 120000.00
  }")
  ENG4_ID=$(echo "${ENG4}" | jq -r '.id // empty')
  echo "  ✅ FedRAMP Moderate engagement: ${ENG4_ID}"
fi

echo ""

# ── 5. Submit Evidence ──
echo "📎 Submitting Evidence..."

if [ -n "${ENG1_ID}" ] && [ "${ENG1_ID}" != "null" ]; then
  for control in "CC6.1:Logical and Physical Access Controls" "CC6.3:Role-Based Access" "CC7.2:System Monitoring" "CC8.1:Change Management"; do
    CID="${control%%:*}"
    CNAME="${control#*:}"
    api_post "/api/aaic/enterprise/evidence" "{
      \"engagement_id\": \"${ENG1_ID}\",
      \"tenant_id\": \"feltsense\",
      \"control_id\": \"${CID}\",
      \"control_name\": \"${CNAME}\",
      \"evidence_type\": \"auto_generated\",
      \"submitted_by\": \"RuntimeAI Platform\"
    }" > /dev/null 2>&1
    echo "  ✅ Evidence: ${CID} — ${CNAME}"
  done
fi

if [ -n "${ENG2_ID}" ] && [ "${ENG2_ID}" != "null" ]; then
  api_post "/api/aaic/enterprise/evidence" "{
    \"engagement_id\": \"${ENG2_ID}\",
    \"tenant_id\": \"feltsense\",
    \"control_id\": \"ART9\",
    \"control_name\": \"Risk Management System\",
    \"evidence_type\": \"auto_generated\",
    \"submitted_by\": \"RuntimeAI Platform\"
  }" > /dev/null 2>&1
  echo "  ✅ Evidence: ART9 — Risk Management System"
fi

echo ""

# ── 6. Create Findings ──
echo "⚠️  Creating Audit Findings..."

if [ -n "${ENG1_ID}" ] && [ "${ENG1_ID}" != "null" ]; then
  api_post "/api/aaic/auditor/findings" "{
    \"engagement_id\": \"${ENG1_ID}\",
    \"tenant_id\": \"feltsense\",
    \"control_id\": \"CC6.1\",
    \"severity\": \"deficiency\",
    \"finding_title\": \"Incomplete access review for AI model endpoints\",
    \"finding_description\": \"Access reviews for 3 AI model API endpoints were not completed in Q4 2025. The access review process does not currently include API-level access controls for model inference endpoints.\"
  }" > /dev/null 2>&1
  echo "  ✅ Finding: CC6.1 — deficiency"

  api_post "/api/aaic/auditor/findings" "{
    \"engagement_id\": \"${ENG1_ID}\",
    \"tenant_id\": \"feltsense\",
    \"control_id\": \"CC8.1\",
    \"severity\": \"observation\",
    \"finding_title\": \"Change management documentation gaps\",
    \"finding_description\": \"Change management policy document does not explicitly address AI model retraining procedures. Minor gap in documentation.\"
  }" > /dev/null 2>&1
  echo "  ✅ Finding: CC8.1 — observation"

  api_post "/api/aaic/auditor/findings" "{
    \"engagement_id\": \"${ENG1_ID}\",
    \"tenant_id\": \"feltsense\",
    \"control_id\": \"CC3.1\",
    \"severity\": \"material_weakness\",
    \"finding_title\": \"Risk assessment does not cover supply chain AI dependencies\",
    \"finding_description\": \"The enterprise risk assessment does not evaluate risks from third-party AI model providers and their supply chain. This is a material gap given reliance on external AI models.\"
  }" > /dev/null 2>&1
  echo "  ✅ Finding: CC3.1 — material_weakness"
fi

echo ""

# ── 7. Issue Certificate ──
echo "📜 Issuing Certificate..."

if [ -n "${ENG1_ID}" ] && [ "${ENG1_ID}" != "null" ] && [ -n "${FIRM1_ID}" ] && [ "${FIRM1_ID}" != "null" ]; then
  api_post "/api/aaic/auditor/certificates" "{
    \"engagement_id\": \"${ENG1_ID}\",
    \"tenant_id\": \"feltsense\",
    \"audit_firm_id\": \"${FIRM1_ID}\",
    \"framework\": \"SOC2_TYPE2\",
    \"certificate_type\": \"initial\"
  }" > /dev/null 2>&1
  echo "  ✅ Certificate: SOC2_TYPE2 (draft)"
fi

echo ""

# ── 8. Create Framework Bundles (Phase 3 — AAIC-019) ──
echo "📦 Creating Framework Bundle Requests..."

if [ -n "${FIRM2_ID}" ] && [ "${FIRM2_ID}" != "null" ]; then
  api_post "/api/aaic/enterprise/bundles/request" "{
    \"tenant_id\": \"feltsense\",
    \"audit_firm_id\": \"${FIRM2_ID}\",
    \"framework_ids\": [\"SOC2_TYPE2\", \"ISO27001\", \"ISO42001\"],
    \"contact_name\": \"David Kim\",
    \"contact_email\": \"compliance@feltsense.ai\",
    \"notes\": \"Multi-framework bundle for comprehensive AI governance audit\"
  }" > /dev/null 2>&1
  echo "  ✅ Bundle request: SOC2 + ISO27001 + ISO42001 → Deloitte"
fi

if [ -n "${FIRM4_ID}" ] && [ "${FIRM4_ID}" != "null" ] && [ -n "${FIRM5_ID}" ] && [ "${FIRM5_ID}" != "null" ]; then
  api_post "/api/aaic/enterprise/bundles/request" "{
    \"tenant_id\": \"feltsense\",
    \"audit_firm_id\": \"${FIRM4_ID}\",
    \"framework_ids\": [\"EU_AI_ACT\", \"GDPR\"],
    \"contact_name\": \"David Kim\",
    \"contact_email\": \"compliance@feltsense.ai\",
    \"notes\": \"EU market entry compliance bundle\"
  }" > /dev/null 2>&1
  echo "  ✅ Bundle request: EU AI Act + GDPR → EU AI Act Specialists"

  api_post "/api/aaic/enterprise/bundles/request" "{
    \"tenant_id\": \"bank-a\",
    \"audit_firm_id\": \"${FIRM5_ID}\",
    \"framework_ids\": [\"FEDRAMP_MODERATE\", \"NIST_CSF\", \"SOC2_TYPE2\"],
    \"contact_name\": \"Jennifer Martinez\",
    \"contact_email\": \"security@bank-a.local\",
    \"notes\": \"Federal compliance bundle for government AI deployment\"
  }" > /dev/null 2>&1
  echo "  ✅ Bundle request: FedRAMP + NIST CSF + SOC2 → Federal Compliance Corp"
fi

echo ""

# ── 9. Create Framework Assessments (Phase 3 — AAIC-017/018) ──
echo "🔍 Creating Framework Assessments..."

if [ -n "${ENG2_ID}" ] && [ "${ENG2_ID}" != "null" ]; then
  api_post "/api/aaic/enterprise/assessments" "{
    \"engagement_id\": \"${ENG2_ID}\",
    \"tenant_id\": \"feltsense\",
    \"framework_id\": \"eu-ai-act\",
    \"assessment_type\": \"conformity\",
    \"risk_level\": \"High\",
    \"system_category\": \"Credit scoring and risk assessment AI\"
  }" > /dev/null 2>&1
  echo "  ✅ Assessment: EU AI Act conformity (High risk — credit scoring)"
fi

if [ -n "${ENG4_ID}" ] && [ "${ENG4_ID}" != "null" ]; then
  api_post "/api/aaic/enterprise/assessments" "{
    \"engagement_id\": \"${ENG4_ID}\",
    \"tenant_id\": \"bank-a\",
    \"framework_id\": \"fedramp-moderate\",
    \"assessment_type\": \"gap_analysis\",
    \"risk_level\": \"High\",
    \"system_category\": \"Government AI agent management platform\"
  }" > /dev/null 2>&1
  echo "  ✅ Assessment: FedRAMP Moderate gap analysis"
fi

echo ""
echo "═══════════════════════════════════════"
echo "  AAIC Seed Data Complete (API-Only)"
echo "  5 Audit Firms (registered + verified)"
echo "  5 Admin Auditors (via firm registration)"
echo "  4 Engagements"
echo "  5 Evidence Submissions"
echo "  3 Findings"
echo "  1 Certificate (draft)"
echo "  3 Bundle Requests (Phase 3)"
echo "  2 Framework Assessments (Phase 3)"
echo "═══════════════════════════════════════"

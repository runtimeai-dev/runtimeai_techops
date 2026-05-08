# 14 — Auto AI Compliance Hub (AAIC) Guide

**Product**: AI Compliance Hub (AAIC)
**Audience**: Customer Compliance Officer / Auditor
**API Base**: `https://api.rt19.runtimeai.io`
**Auditor Dashboard**: `https://auditor.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-26

---

## What Is the AI Compliance Hub?

Automated compliance management from gap analysis to audit certificate:

- **Framework Management** — SOC 2, FedRAMP, EU AI Act, HIPAA, eIDAS, and more
- **Gap Tracking** — Identify compliance gaps with remediation guidance
- **Evidence Auto-Generation** — Pull evidence from platform data
- **Audit Marketplace** — Connect with compliance audit firms
- **Certificate Issuance** — Manage compliance certificates
- **Auditor Dashboard** — External auditor collaboration portal
- **AI Firm Matching** — Match with audit firms specializing in AI compliance

---

## Architecture: Auth Flow

Auditor authentication uses a **magic link** pattern via the auth-service:

```
Auditor → auditor.rt19.runtimeai.io/login
  → POST /api/aaic/auditor/magic-link {email, persona:"auditor"}
  → aaic-service (port 5056) proxies to auth-service (port 8097)
  → auth-service generates token, sends email via SendGrid
  → Auditor clicks link in email
  → auth-service verifies token, creates session, redirects to auditor dashboard
```

### Required Environment Variables (aaic-service)

| Variable | Source | Purpose |
|----------|--------|---------|
| `DATABASE_URL` | `rt19-db-secret` | PostgreSQL connection |
| `AAIC_PORT` | `5056` | Service port |
| `AUTH_SERVICE_URL` | `http://auth-svc:8097` | Auth-service proxy for magic links |

### Required Environment Variables (auth-service)

| Variable | Source | Purpose |
|----------|--------|---------|
| `SENDGRID_API_KEY` | `rt19-email-secrets` | Email delivery |
| `AUDITOR_URL` | `https://auditor.rt19.runtimeai.io` | Post-login redirect |
| `JWT_SECRET` | `rt19-app-secrets` | Session tokens |

---

## Setting Up AAIC on rt19

### Step 1: Select Compliance Frameworks

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Enable frameworks relevant to your business
for framework in "soc2" "fedramp" "hipaa" "eu_ai_act" "gdpr" "nist_ai_rmf" "iso27001"; do
  curl -sf -b "$COOKIE" -X POST "$API/api/aaic/frameworks" \
    -H "Content-Type: application/json" \
    -d "{\"framework\": \"$framework\", \"enabled\": true}"
  echo "  ✅ Enabled: $framework"
done

# List enabled frameworks
curl -sf -b "$COOKIE" "$API/api/aaic/frameworks" | jq '.frameworks[] | {name, controls_count, enabled}'
```

### Step 2: Run Gap Analysis

```bash
# Run gap analysis across all enabled frameworks
curl -sf -b "$COOKIE" -X POST "$API/api/aaic/gap-analysis" | jq '{
  overall_score: .overall_score,
  frameworks: [.frameworks[] | {
    name: .name,
    score: .score,
    total_controls: .total_controls,
    met: .controls_met,
    gaps: .gaps_count,
    critical_gaps: .critical_gaps
  }]
}'
```

### Step 3: View and Address Gaps

```bash
# List all gaps
curl -sf -b "$COOKIE" "$API/api/aaic/gaps" | jq '.gaps[] | {
  framework: .framework,
  control_id: .control_id,
  control_name: .control_name,
  severity: .severity,
  remediation: .remediation,
  status: .status
}'

# Update gap status
curl -sf -b "$COOKIE" -X PUT "$API/api/aaic/gaps/<gap_id>" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "in_progress",
    "assignee": "security-lead@acme-corp.com",
    "notes": "Implementing MFA for all agent access",
    "due_date": "2026-04-15"
  }'
```

### Step 4: Auto-Generate Evidence

The platform can automatically generate compliance evidence from operational data.

```bash
# Generate evidence for a specific control
curl -sf -b "$COOKIE" -X POST "$API/api/aaic/evidence/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "framework": "soc2",
    "control_id": "CC6.1",
    "evidence_type": "auto",
    "date_range": {
      "start": "2026-01-01",
      "end": "2026-03-17"
    }
  }'

# List all evidence
curl -sf -b "$COOKIE" "$API/api/aaic/evidence" | jq '.evidence[] | {
  framework: .framework,
  control: .control_id,
  type: .evidence_type,
  status: .status,
  generated_at: .generated_at
}'

# Upload manual evidence
curl -sf -b "$COOKIE" -X POST "$API/api/aaic/evidence/upload" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@/path/to/evidence.pdf" \
  -F "framework=soc2" \
  -F "control_id=CC6.1" \
  -F "description=Network diagram showing agent isolation"
```

### Step 5: Connect with Audit Firms

```bash
# Browse audit firm marketplace
curl -sf -b "$COOKIE" "$API/api/aaic/firms" | jq '.firms[] | {
  name: .firm_name,
  specializations: .specializations,
  rating: .avg_rating,
  ai_experience: .ai_compliance_experience
}'

# Request engagement with a firm
curl -sf -b "$COOKIE" -X POST "$API/api/aaic/engagements" \
  -H "Content-Type: application/json" \
  -d '{
    "firm_id": "<firm_id>",
    "frameworks": ["soc2", "hipaa"],
    "scope": "full_audit",
    "target_date": "2026-06-30",
    "notes": "Looking for SOC 2 Type II + HIPAA certification"
  }'
```

### Step 6: Auditor Collaboration

External auditors access `https://auditor.rt19.runtimeai.io` with limited, read-only access.

```bash
# Invite auditor
curl -sf -b "$COOKIE" -X POST "$API/api/aaic/auditors/invite" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "auditor@bigfour.com",
    "firm": "Big Four Audit",
    "access_scope": ["soc2", "hipaa"],
    "access_level": "read_only",
    "expires_at": "2026-06-30"
  }'
```

### Step 7: Certificate Management

```bash
# View compliance certificates
curl -sf -b "$COOKIE" "$API/api/aaic/certificates" | jq '.certificates[] | {
  framework: .framework,
  issued_by: .issuing_firm,
  valid_from: .valid_from,
  valid_until: .valid_until,
  status: .status
}'
```

---

## Supported Compliance Frameworks

| Framework | Controls | Focus Area |
|-----------|----------|------------|
| **SOC 2 Type II** | 65+ | Security, availability, confidentiality |
| **FedRAMP** | 325+ | Federal cloud security |
| **HIPAA** | 75+ | Healthcare data protection |
| **EU AI Act** | 40+ | AI risk management |
| **GDPR** | 50+ | Data privacy |
| **NIST AI RMF** | 70+ | AI risk management framework |
| **ISO 27001** | 114 | Information security management |
| **PCI DSS** | 250+ | Payment card security |
| **CCPA** | 30+ | California consumer privacy |
| **NIST CSF 2.0** | 100+ | Cybersecurity framework |
| **CIS Controls** | 153 | Security best practices |
| **COBIT** | 40 | IT governance |
| **ITIL** | 34 | IT service management |

---

## Troubleshooting

**Magic link email not received?**
1. Verify `AUTH_SERVICE_URL` is set in the AAIC service deployment
2. Check auth-service logs: `kubectl logs -l app=auth-service`
3. Verify `SENDGRID_API_KEY` is configured in auth-service
4. Check for rate limiting (3 per email per 15 min)

**Auditor login redirect fails?**
1. Verify `AUDITOR_URL` is set correctly in auth-service
2. Check `COOKIE_DOMAIN` is set to `runtimeai.io` for cross-subdomain cookies
3. Verify `COOKIE_SECURE=true` in production

**Database unavailable errors?**
1. Verify `DATABASE_URL` secret exists: `kubectl get secret rt19-db-secret`
2. Check AAIC service health: `curl https://api.rt19.runtimeai.io/api/aaic/info`

---

## FAQ

**Q: How does evidence auto-generation work?**
A: The platform pulls data from the audit trail, agent registry, governance policies, and firewall logs to automatically populate evidence for compliance controls.

**Q: Can I use AAIC without an external audit firm?**
A: Yes. Self-assessment mode allows you to track compliance internally. The audit firm marketplace is optional.

**Q: How long does a typical audit take?**
A: Depends on scope. SOC 2 Type I: 4-8 weeks. SOC 2 Type II: 3-6 months observation + 4-8 weeks audit. With auto-evidence, preparation time is significantly reduced.

**Q: Can auditors see all my data?**
A: No. Auditor access is scoped to specific frameworks and limited to compliance-relevant data (policies, audit trails, evidence). They cannot see agent details or business data. Row-Level Security (RLS) enforces tenant isolation at the database level.

**Q: How do I track remediation progress?**
A: Gap items have status tracking (open, in_progress, resolved, deferred). Dashboard shows completion percentage per framework.

**Q: Can I schedule recurring compliance assessments?**
A: Yes. Set up a workflow (see [08_aiops_workflows_guide.md](08_aiops_workflows_guide.md)) to run gap analysis quarterly.

**Q: How does the magic link login work for auditors?**
A: Auditors enter their email at `auditor.rt19.runtimeai.io/login`. A one-time login link is sent via SendGrid email (valid for 15 minutes). Clicking the link authenticates the auditor and creates a session cookie. No password needed.

### Advanced Setup Questions

**Q: How does real-time chat work for auditor communication?**
A: The auditor dashboard includes a secure chat feature. Messages are encrypted and logged to the audit trail. Useful for Q&A during the audit process.

**Q: Can I generate multi-framework compliance bundles?**
A: Yes. If you're pursuing SOC 2 + HIPAA simultaneously, the platform identifies overlapping controls and generates a unified evidence bundle.

**Q: How does AI firm matching work?**
A: The platform analyzes your compliance requirements, industry, and company size, then recommends audit firms with relevant AI compliance experience.

**Q: Can I export compliance reports for board presentations?**
A: Yes. Export compliance posture, gap analysis, and trend reports via API or dashboard export (PDF, CSV).

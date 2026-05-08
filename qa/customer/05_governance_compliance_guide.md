# 05 — AI Governance & Compliance Guide

**Product**: AI Control Plane (Governance)
**Audience**: Customer Security / Compliance Officer
**API Base**: `https://api.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is AI Governance?

The AI Control Plane provides policy-as-code governance for every AI agent action. It covers:

- **Guardrail Policies** — PII blocking, toxicity filtering, prompt injection detection
- **Separation of Duties (SoD)** — Prevent conflicting permissions
- **Conditional Access** — Time-of-day, IP range, environment restrictions
- **Egress Rules** — Control what agents can connect to
- **Compliance Frameworks** — SOC 2, FedRAMP, EU AI Act, HIPAA, and more
- **Policy Versioning** — Signed, auditable policy bundles

---

## Setting Up Governance on rt19

### Step 1: Create Guardrail Policies

Guardrails are real-time enforcement rules that block dangerous content.

#### Via Dashboard
1. Navigate to **Governance** → **Guardrails**
2. Click **Create Guardrail**
3. Configure:
   - Name: `pii-blocker`
   - Type: `dlp`
   - Rules: Block SSN, Credit Card, Phone Number
   - Action: `block` (or `redact`, `alert`)
   - Apply to: All agents (or specific blueprints)

#### Via API

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Create PII blocking guardrail
curl -sf -b "$COOKIE" -X POST "$API/api/guardrails" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "pii-blocker",
    "type": "dlp",
    "description": "Block PII in agent responses",
    "rules": [
      {"pattern": "ssn", "action": "block", "severity": "critical"},
      {"pattern": "credit_card", "action": "redact", "severity": "high"},
      {"pattern": "phone_number", "action": "redact", "severity": "medium"},
      {"pattern": "email_address", "action": "alert", "severity": "low"}
    ],
    "scope": "all_agents",
    "enabled": true
  }'

# Create toxicity filter
curl -sf -b "$COOKIE" -X POST "$API/api/guardrails" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "toxicity-filter",
    "type": "content_safety",
    "description": "Block toxic or harmful content",
    "rules": [
      {"category": "hate_speech", "action": "block", "threshold": 0.8},
      {"category": "violence", "action": "block", "threshold": 0.9},
      {"category": "self_harm", "action": "block", "threshold": 0.7}
    ],
    "scope": "all_agents",
    "enabled": true
  }'

# Create prompt injection detector
curl -sf -b "$COOKIE" -X POST "$API/api/guardrails" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prompt-injection-detector",
    "type": "security",
    "description": "Detect and block prompt injection attempts",
    "rules": [
      {"pattern": "ignore_previous_instructions", "action": "block"},
      {"pattern": "system_prompt_override", "action": "block"},
      {"pattern": "jailbreak_attempt", "action": "alert"}
    ],
    "scope": "all_agents",
    "enabled": true
  }'
```

### Step 2: Configure Separation of Duties (SoD)

SoD rules prevent a single agent from having conflicting permissions.

```bash
# Prevent agent from having both "approve_payment" and "initiate_payment"
curl -sf -b "$COOKIE" -X POST "$API/api/sod-rules" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "payment-segregation",
    "description": "No agent can both initiate and approve payments",
    "conflicting_permissions": ["initiate_payment", "approve_payment"],
    "enforcement": "hard_block",
    "remediation": "Split into two agents with separate sponsors"
  }'

# Prevent agent from having both "deploy_code" and "approve_deploy"
curl -sf -b "$COOKIE" -X POST "$API/api/sod-rules" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "deploy-segregation",
    "description": "No agent can both deploy and approve deployments",
    "conflicting_permissions": ["deploy_code", "approve_deploy"],
    "enforcement": "hard_block"
  }'
```

### Step 3: Set Up Conditional Access Policies

Restrict when and where agents can operate.

```bash
# Business hours only
curl -sf -b "$COOKIE" -X POST "$API/api/policies/conditional-access" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "business-hours-only",
    "description": "Restrict high-risk agents to business hours",
    "conditions": {
      "time_window": {"start": "08:00", "end": "18:00", "timezone": "America/Los_Angeles"},
      "days": ["monday", "tuesday", "wednesday", "thursday", "friday"]
    },
    "applies_to": {"risk_tier": "high"},
    "action": "block_outside_window"
  }'

# IP range restriction
curl -sf -b "$COOKIE" -X POST "$API/api/policies/conditional-access" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "corporate-network-only",
    "description": "Agents can only operate from corporate IP ranges",
    "conditions": {
      "allowed_ip_ranges": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    },
    "applies_to": {"environment": "production"},
    "action": "block"
  }'
```

### Step 4: Configure Egress Rules

Control what external services agents can communicate with.

```bash
# Allow only approved AI providers
curl -sf -b "$COOKIE" -X POST "$API/api/policies/egress" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "approved-ai-providers",
    "description": "Only allow traffic to approved AI provider endpoints",
    "rules": [
      {"destination": "api.openai.com", "port": 443, "action": "allow"},
      {"destination": "api.anthropic.com", "port": 443, "action": "allow"},
      {"destination": "*.bedrock.*.amazonaws.com", "port": 443, "action": "allow"},
      {"destination": "*", "port": "*", "action": "deny"}
    ],
    "applies_to": "all_agents"
  }'
```

### Step 5: Enable Compliance Frameworks

RuntimeAI supports 13+ compliance frameworks.

```bash
# Enable SOC 2
curl -sf -b "$COOKIE" -X POST "$API/api/compliance/frameworks" \
  -H "Content-Type: application/json" \
  -d '{"framework": "soc2", "enabled": true}'

# Enable EU AI Act
curl -sf -b "$COOKIE" -X POST "$API/api/compliance/frameworks" \
  -H "Content-Type: application/json" \
  -d '{"framework": "eu_ai_act", "enabled": true}'

# Enable FedRAMP
curl -sf -b "$COOKIE" -X POST "$API/api/compliance/frameworks" \
  -H "Content-Type: application/json" \
  -d '{"framework": "fedramp", "enabled": true}'

# Enable HIPAA
curl -sf -b "$COOKIE" -X POST "$API/api/compliance/frameworks" \
  -H "Content-Type: application/json" \
  -d '{"framework": "hipaa", "enabled": true}'

# List all available frameworks
curl -sf -b "$COOKIE" "$API/api/compliance/frameworks" | jq '.frameworks[] | {name, enabled, controls_count}'
```

### Step 6: Map Controls to Frameworks

```bash
# View controls for SOC 2
curl -sf -b "$COOKIE" "$API/api/compliance/frameworks/soc2/controls" | jq .

# Check compliance posture
curl -sf -b "$COOKIE" "$API/api/compliance/posture" | jq '{
  overall_score: .overall_score,
  frameworks: [.frameworks[] | {name, score, gaps_count}]
}'
```

---

## Policy Lifecycle

```
Draft → Review → Sign → Publish → Enforce → Audit → Version → Retire
```

1. **Draft**: Create policy via API or UI
2. **Review**: Stakeholders review and approve
3. **Sign**: Policy is cryptographically signed (integrity guarantee)
4. **Publish**: Policy is deployed to enforcement points
5. **Enforce**: Active enforcement on all matching agents
6. **Audit**: Every enforcement action is logged to immutable audit trail
7. **Version**: New versions can be created without disrupting existing enforcement
8. **Retire**: Old policies can be deactivated but remain in audit history

---

## Immutable Audit Trail

Every governance action is recorded in the Merkle-chain audit trail.

```bash
# View audit events
curl -sf -b "$COOKIE" "$API/api/audit/events?limit=20" | jq '.events[] | {timestamp, actor, action, resource, result}'

# Verify chain integrity
curl -sf -b "$COOKIE" -X POST "$API/api/audit/verify-chain" | jq .
# Response: {"verified": true, "chain_length": 1234, "last_hash": "sha256:..."}

# Export audit trail
curl -sf -b "$COOKIE" "$API/api/audit/export?format=csv&start_date=2026-03-01" > audit_march.csv
```

---

## FAQ

**Q: What's the difference between a guardrail and a policy?**
A: Guardrails are real-time content rules (block PII, filter toxicity). Policies are broader access and behavioral rules (time-of-day access, egress control, SoD).

**Q: How do I know if a guardrail is blocking legitimate traffic?**
A: Check the audit trail for `guardrail_block` events. Each event includes the blocked content (redacted), the rule that triggered, and the agent involved.

**Q: Can I run policies in audit mode (log but don't block)?**
A: Yes. Set `"enforcement": "audit_only"` on any policy. It will log violations without blocking.

**Q: How many compliance frameworks can I enable simultaneously?**
A: All 13. There's no limit. Controls may overlap across frameworks (e.g., access control appears in SOC 2, FedRAMP, and HIPAA).

**Q: How is compliance posture calculated?**
A: Score = (controls_met / total_controls) × 100. Each framework is scored independently. The overall score is a weighted average.

**Q: Can I add custom compliance frameworks?**
A: Not yet. Custom frameworks are on the roadmap. Currently, you can map custom requirements to existing framework controls.

### Advanced Setup Questions

**Q: How does OPA policy evaluation work?**
A: Policies are compiled to Rego (OPA's policy language). The control plane includes an embedded OPA engine that evaluates policies in sub-millisecond time. Policy bundles can be signed and distributed via OCI registries.

**Q: Can I enforce policies at the data plane level?**
A: Yes. The Flow Enforcer (Envoy + Wasm sidecar) enforces policies at the network level. Policies are synced from the control plane every 30 seconds. This requires the data plane components (not currently deployed on rt19 — see [gaps_issues.md](gaps_issues.md)).

**Q: How does the audit chain prevent tampering?**
A: Each audit event includes a SHA-256 hash of the previous event, forming a Merkle chain. The chain can be verified at any time. In production, chain roots are periodically written to S3 Object Lock for immutability.

**Q: Can I integrate governance policies with my existing GRC tool?**
A: Compliance posture data can be exported via API. Direct integrations with GRC tools (ServiceNow, Archer) are on the roadmap.

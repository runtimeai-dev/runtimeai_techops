# 03 — Agent Identity Fabric Guide

**Product**: Agent Identity Fabric
**Audience**: Customer Admin / Security Engineer
**API Base**: `https://api.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is Agent Identity Fabric?

Every AI agent in your organization gets a verified, cryptographic identity — just like employees get badges. This product handles:

- **Agent Registry** — Central catalog of all AI agents
- **Agent Blueprints** — Templates defining expected behavior
- **Agent Sponsors** — Human accountability for each agent
- **Trust Scores** — Dynamic 0–100 trust rating
- **Risk Tiers** — EU AI Act alignment (Minimal, Limited, High, Unacceptable)
- **Supply Chain Security** — SBOM tracking, CVE scanning, provenance
- **TPM Hardware Attestation** — Hardware-level integrity verification
- **OAuth2 Credentials** — Agent-to-service authentication (JWT RS256)

---

## Setting Up Agent Identity on rt19

### Step 1: Create Agent Blueprints

Blueprints define what an agent "should" look like — its expected tools, data access, and behavior.

#### Via Dashboard
1. Navigate to **Agents** → **Blueprints**
2. Click **Create Blueprint**
3. Define:
   - Name: `customer-support-agent`
   - Allowed Tools: `read_ticket`, `update_ticket`, `search_kb`
   - Data Access: `customer_records (read-only)`
   - Risk Tier: `Limited`
   - Max Token Budget: `10,000 tokens/day`

#### Via API

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

curl -sf -b "$COOKIE" -X POST "$API/api/blueprints" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "customer-support-agent",
    "description": "Blueprint for customer-facing support agents",
    "risk_tier": "limited",
    "allowed_tools": ["read_ticket", "update_ticket", "search_kb"],
    "data_access": ["customer_records:read"],
    "max_daily_tokens": 10000,
    "requires_human_approval": false
  }'
```

### Step 2: Register AI Agents

#### Via Dashboard
1. Navigate to **Agents** → **Registry**
2. Click **Register Agent**
3. Fill in:
   - Name: `acme-support-bot-1`
   - Type: `chatbot`
   - Blueprint: `customer-support-agent`
   - Model: `gpt-4o`
   - Department: `Customer Support`
   - Environment: `production`
   - Sponsor: (assign a human sponsor)

#### Via API

```bash
# Register an agent
curl -sf -b "$COOKIE" -X POST "$API/api/agents" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-support-bot-1",
    "type": "chatbot",
    "model": "gpt-4o",
    "provider": "openai",
    "department": "customer-support",
    "environment": "production",
    "blueprint_id": "<blueprint_id_from_step_1>",
    "description": "Customer support chatbot for Acme Corp ticket system",
    "metadata": {
      "version": "2.1.0",
      "repository": "github.com/acme-corp/support-bot",
      "owner_team": "ai-platform"
    }
  }'
```

### Step 3: Assign Agent Sponsors

Every agent needs a human sponsor — the accountable person for that agent's behavior.

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/sponsor" \
  -H "Content-Type: application/json" \
  -d '{
    "sponsor_email": "alice@acme-corp.com",
    "sponsor_name": "Alice Chen",
    "sponsor_role": "VP Engineering",
    "responsibilities": ["behavior_review", "incident_response", "compliance_sign_off"]
  }'
```

### Step 4: Issue OAuth2 Credentials

Agents authenticate to services using OAuth2 client credentials (JWT RS256).

```bash
# Create OAuth credential for the agent
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/credentials" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "oauth2_client_credentials",
    "name": "support-bot-prod-cred",
    "scopes": ["read:tickets", "write:tickets", "read:kb"],
    "expires_in_days": 90,
    "auto_rotate": true
  }'
# Response includes client_id and client_secret — store securely!
```

### Step 5: Supply Chain Security (SBOM)

Upload the agent's Software Bill of Materials for vulnerability tracking.

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/sbom" \
  -H "Content-Type: application/json" \
  -d '{
    "format": "cyclonedx",
    "version": "1.4",
    "components": [
      {"name": "langchain", "version": "0.1.5", "type": "library"},
      {"name": "openai-sdk", "version": "1.12.0", "type": "library"},
      {"name": "fastapi", "version": "0.109.0", "type": "framework"}
    ]
  }'
```

### Step 6: TPM Hardware Attestation (Advanced)

For high-security environments, enable TPM 2.0 hardware verification.

```bash
# Submit TPM attestation evidence
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/tpm/attest" \
  -H "Content-Type: application/json" \
  -d '{
    "tpm_version": "2.0",
    "pcr_measurements": {
      "pcr0": "sha256:abc123...",
      "pcr7": "sha256:def456..."
    },
    "ak_cert": "<attestation_key_certificate>",
    "quote": "<tpm_quote_base64>"
  }'

# Set golden baseline
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/tpm/baseline" \
  -H "Content-Type: application/json" \
  -d '{
    "pcr_policy": {
      "pcr0": {"expected": "sha256:abc123...", "action_on_mismatch": "quarantine"},
      "pcr7": {"expected": "sha256:def456...", "action_on_mismatch": "alert"}
    },
    "attestation_interval_seconds": 3600
  }'
```

---

## Viewing Agent Identity

### Dashboard Views

- **Agent Registry**: List all registered agents with trust scores, risk tiers, status
- **Agent Detail**: Deep dive into a single agent — credentials, SBOM, sponsor, drift history
- **Identity Graph**: Visual graph showing agent relationships, data flows, trust chains
- **Trust Score Trend**: Historical trust score chart with events that caused changes

### API Queries

```bash
# List all agents
curl -sf -b "$COOKIE" "$API/api/agents" | jq '.agents[] | {name, trust_score, risk_tier, status}'

# Get agent detail
curl -sf -b "$COOKIE" "$API/api/agents/<agent_id>" | jq .

# Get trust score history
curl -sf -b "$COOKIE" "$API/api/agents/<agent_id>/trust-score/history" | jq .

# List all blueprints
curl -sf -b "$COOKIE" "$API/api/blueprints" | jq .

# List all sponsors
curl -sf -b "$COOKIE" "$API/api/sponsors" | jq .
```

---

## Testing Agent Identity on rt19

```bash
# Run the identity fabric test
./scripts/test_all_products.sh identity

# Expected:
#   ✅ Create blueprint
#   ✅ Register agent
#   ✅ Assign sponsor
#   ✅ Issue credentials
#   ✅ Upload SBOM
#   ✅ Verify trust score
#   ✅ List agents
#   ✅ Agent detail view
```

---

## FAQ

**Q: What trust score does a new agent start with?**
A: New agents start with a trust score of 50 (neutral). The score increases with compliance adherence and decreases with policy violations or drift.

**Q: Can I bulk-register agents?**
A: Yes, use the seed script (`scripts/seed_rt19_customer.sh`) which registers multiple agents via API. For custom bulk import, loop through your agent inventory and POST to `/api/agents`.

**Q: What happens when an agent's trust score drops below threshold?**
A: Configurable — options include: alert only, restrict tool access, suspend agent, or full quarantine (kill switch).

**Q: How often are trust scores recalculated?**
A: Trust scores update in real-time based on events (policy violations, drift detections, access review results). A full recalculation runs hourly.

**Q: Can I integrate with my existing CMDB?**
A: The API supports full CRUD on agents. Build a sync job that reads from your CMDB and POSTs to `/api/agents`. Custom metadata fields allow mapping to your internal IDs.

**Q: How do agent credentials rotate?**
A: When `auto_rotate: true`, credentials are rotated before expiry. You can also manually rotate: `POST /api/agents/<id>/credentials/<cred_id>/rotate`.

### Advanced Setup Questions

**Q: How does SPIFFE identity work with RuntimeAI?**
A: Each registered agent can be issued a SPIFFE ID (`spiffe://runtimeai.io/tenant/acme-corp/agent/<agent_id>`). This enables mTLS between agents and services. Requires the identity-dns service in the data plane.

**Q: Can I enforce that all agents must have a blueprint?**
A: Yes. Set a governance policy: `POST /api/policies` with type `agent_registration_requires_blueprint`. Unblueprinted agent registrations will be rejected.

**Q: How does cascade disable work?**
A: Disabling a blueprint cascades to all agents using it. They transition to `suspended` state. Re-enabling the blueprint restores agents to their previous state.

**Q: What's the difference between risk tier and trust score?**
A: Risk tier is a static classification (EU AI Act alignment) set at registration. Trust score is dynamic (0–100) and changes based on agent behavior. A "High" risk tier agent can have a high trust score if it's well-behaved.

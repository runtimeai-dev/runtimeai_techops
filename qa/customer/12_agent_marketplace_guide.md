# 12 — Agent Marketplace Guide

**Product**: Agent Marketplace (AMKT)
**Audience**: Customer IT Admin / Developer
**API Base**: `https://api.rt19.runtimeai.io`
**Marketplace API**: `https://marketplace.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is the Agent Marketplace?

A curated catalog where enterprises can discover, evaluate, install, and govern certified AI agents:

- **Browse & Search** — Full-text search across 100+ agent listings
- **One-Click Install** — Install agents with pre-configured guardrails
- **Builder Portal** — Publish agents to the marketplace
- **Risk Scoring** — Independent risk assessment per agent
- **SBOM Registry** — Supply chain transparency for every agent
- **Behavior Certificates** — Verified behavioral compliance
- **Stripe Billing** — Usage-based or subscription pricing

---

## Using the Marketplace on rt19

### Step 1: Browse the Agent Catalog

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Browse all agents
curl -sf -b "$COOKIE" "$API/api/marketplace/catalog" | jq '.agents[] | {
  name: .name,
  category: .category,
  rating: .avg_rating,
  installs: .install_count,
  risk_score: .risk_score,
  verified: .verified
}'

# Search by keyword
curl -sf -b "$COOKIE" "$API/api/marketplace/catalog?search=customer+support" | jq .

# Filter by category
curl -sf -b "$COOKIE" "$API/api/marketplace/catalog?category=analytics" | jq .

# Get agent details
curl -sf -b "$COOKIE" "$API/api/marketplace/agents/<agent_listing_id>" | jq '{
  name: .name,
  description: .description,
  capabilities: .capabilities,
  requirements: .requirements,
  sbom: .sbom,
  behavior_certificate: .behavior_cert,
  pricing: .pricing
}'
```

### Step 2: Install an Agent

```bash
# Install an agent from the marketplace
curl -sf -b "$COOKIE" -X POST "$API/api/marketplace/install" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_listing_id": "<listing_id>",
    "name": "acme-support-agent",
    "environment": "production",
    "blueprint_id": "<blueprint_id>",
    "sponsor_email": "alice@acme-corp.com",
    "guardrails": {
      "dlp_enabled": true,
      "max_daily_tokens": 50000,
      "allowed_data_access": ["customer_records:read"]
    }
  }'
# The agent is registered in your Agent Registry with pre-configured settings
```

### Step 3: Review Installed Agents

```bash
# List installed marketplace agents
curl -sf -b "$COOKIE" "$API/api/marketplace/installed" | jq '.installed[] | {
  name: .name,
  listing: .listing_name,
  version: .version,
  installed_at: .installed_at,
  status: .status,
  update_available: .update_available
}'
```

### Step 4: Agent Builder Portal

If you want to publish agents to the marketplace:

```bash
# Register as a builder
curl -sf -b "$COOKIE" -X POST "$API/api/marketplace/builders/register" \
  -H "Content-Type: application/json" \
  -d '{
    "company_name": "Acme Corp",
    "contact_email": "dev@acme-corp.com",
    "website": "https://acme-corp.com"
  }'

# Publish an agent listing
curl -sf -b "$COOKIE" -X POST "$API/api/marketplace/publish" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Acme Analytics Agent",
    "description": "Automated analytics and reporting agent",
    "category": "analytics",
    "capabilities": ["data_analysis", "report_generation", "anomaly_detection"],
    "requirements": {
      "models": ["gpt-4o", "claude-sonnet-4-6"],
      "data_access": ["analytics_db:read"]
    },
    "pricing": {
      "type": "per_request",
      "price_per_1000_requests": 5.00
    },
    "sbom": {
      "format": "cyclonedx",
      "components": [
        {"name": "langchain", "version": "0.1.5"},
        {"name": "pandas", "version": "2.1.0"}
      ]
    }
  }'
```

### Step 5: Agent Sandbox Testing

Test marketplace agents in a sandboxed environment before production deployment.

```bash
# Create sandbox instance
curl -sf -b "$COOKIE" -X POST "$API/api/marketplace/sandbox" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_listing_id": "<listing_id>",
    "test_duration_hours": 24,
    "synthetic_data": true,
    "guardrails": "strict"
  }'
```

---

## Marketplace Dashboard

| View | Purpose |
|------|---------|
| **Catalog** | Browse and search available agents |
| **Installed** | Manage installed agents, check for updates |
| **Builder Portal** | Publish and manage your agent listings |
| **Analytics** | Usage metrics for installed agents |
| **Reviews** | Read and write agent reviews |

---

## FAQ

**Q: How are marketplace agents different from manually registered agents?**
A: Marketplace agents come with pre-validated SBOMs, behavior certificates, and risk scores. They also receive automatic updates from the publisher.

**Q: Who curates the marketplace?**
A: RuntimeAI reviews all listings for security and compliance before publishing. Verified agents get a "Verified" badge.

**Q: Can I create a private marketplace for my organization?**
A: Yes. Private agents are only visible to your tenant. Use `"visibility": "private"` when publishing.

**Q: How does sandbox testing work?**
A: The sandbox creates an isolated instance with synthetic data. The agent runs for a configurable period, and you can observe its behavior before deploying to production.

**Q: Can I roll back an agent update?**
A: Yes. Installed agents maintain version history. Roll back via `POST /api/marketplace/installed/<id>/rollback?version=<prev_version>`.

**Q: How does billing work?**
A: Agent publishers set pricing (free, per-request, or subscription). Billing is processed via Stripe. See [13_billing_saas_admin_guide.md](13_billing_saas_admin_guide.md).

### Advanced Setup Questions

**Q: Can I import shadow AI findings into the marketplace?**
A: Yes. Discovery findings can be matched against marketplace listings. If a shadow AI tool has a governed marketplace equivalent, one-click migration is possible.

**Q: How does the EU AI Act compliance work in the marketplace?**
A: All marketplace agents include EU AI Act risk classification. High-risk agents require additional documentation and human oversight. The compliance badge shows framework adherence.

**Q: Can I enforce that all agents must come from the marketplace?**
A: Yes. Set a governance policy: "All agent registrations must reference a marketplace listing." This prevents ungoverned agent deployment.

**Q: How does A2A (Agent-to-Agent) protocol work?**
A: A2A enables marketplace agents to communicate with each other via a standardized protocol. The MCP gateway facilitates A2A routing with full audit logging.

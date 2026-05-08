# 13 — Billing & SaaS Admin Guide

**Product**: SaaS Admin Platform
**Audience**: RuntimeAI Operations / Customer Billing
**SaaS Admin**: `https://admin.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is the SaaS Admin App?

The SaaS Admin App (`admin.runtimeai.io`) is the internal platform for managing RuntimeAI as a service:

- **Tenant Management** — Create, configure, and monitor customer tenants
- **Billing & Subscriptions** — Stripe-powered billing
- **Pricing Tiers** — Configure pricing plans
- **Monitoring** — Service health and uptime
- **Deployment** — Pod management and releases
- **Security** — Platform-wide security settings
- **Audit** — Admin-level audit logs

---

## SaaS Admin Pages (25 Pages)

| Page | Purpose |
|------|---------|
| Dashboard | Admin overview & KPIs |
| Tenants | Tenant CRUD |
| Tenant Details | Per-tenant deep dive |
| Tenant Management | Bulk operations |
| Users | Admin user management |
| Partners | Partner inquiry management |
| Demo Requests | Demo request processing |
| Billing | Tenant billing & subscriptions |
| Pricing Management | Pricing tier configuration |
| Audit | Admin audit logs |
| Monitoring | Service health & uptime |
| Deployment | Pipeline & release management |
| Settings | Platform settings |
| Security | Security configuration |
| Inventory | Asset inventory |
| Global Entitlements | Platform-wide entitlements |
| Notifications | Notification rules & templates |
| Identity Fabric Admin | Identity fabric config |
| MCP Gateway Admin | MCP gateway management |
| Marketplace Admin | Marketplace curation |
| Onboarding Wizard | Customer onboarding flow |
| eSign Admin | eSign service admin |
| AAIC Admin | Auto AI Compliance admin |
| FinOps Admin | AI Cost Intelligence admin |

---

## Billing Setup

### Step 1: Configure Stripe

```bash
# Stripe is configured via environment variables on the billing-service
# In K8s: kubectl edit deployment/control-plane -n rt19
# Add env vars:
#   STRIPE_SECRET_KEY=sk_live_...
#   STRIPE_WEBHOOK_SECRET=whsec_...
#   STRIPE_PRICE_ID_STARTER=price_...
#   STRIPE_PRICE_ID_PROFESSIONAL=price_...
#   STRIPE_PRICE_ID_ENTERPRISE=price_...
```

### Step 2: Define Pricing Tiers

#### Via SaaS Admin

1. Navigate to `https://admin.runtimeai.io`
2. Go to **Pricing Management**
3. Create tiers:

| Tier | Monthly Price | Agents | Users | Features |
|------|--------------|--------|-------|----------|
| **Starter** | $299/mo | 10 | 5 | Identity, Discovery, Governance |
| **Professional** | $999/mo | 100 | 25 | All products except ML Intel |
| **Enterprise** | Custom | Unlimited | Unlimited | All products + SLA |

#### Via API

```bash
ADMIN_SECRET="<admin_secret>"
API="https://api.rt19.runtimeai.io"

curl -sf -X POST "$API/api/admin/pricing" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d '{
    "tier": "professional",
    "price_monthly": 999,
    "currency": "USD",
    "limits": {
      "max_agents": 100,
      "max_users": 25,
      "features": ["identity", "discovery", "governance", "firewall", "mcp", "finops", "compliance", "marketplace", "esign", "behavioral", "aiops"]
    }
  }'
```

### Step 3: Assign Billing to a Tenant

```bash
curl -sf -X PUT "$API/api/admin/tenants/acme-corp/billing" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d '{
    "plan": "professional",
    "billing_email": "billing@acme-corp.com",
    "payment_method": "stripe",
    "stripe_customer_id": "cus_..."
  }'
```

---

## Tenant Entitlements

Control what features each tenant can access.

```bash
# Set tenant entitlements
curl -sf -X PUT "$API/api/admin/tenants/acme-corp/entitlements" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d '{
    "features": {
      "identity_fabric": true,
      "discovery": true,
      "governance": true,
      "firewall": true,
      "behavioral_intel": true,
      "aiops": true,
      "mcp_gateway": true,
      "compliance_hub": true,
      "marketplace": true,
      "finops": true,
      "esign": true,
      "ml_intelligence": false
    },
    "limits": {
      "max_agents": 100,
      "max_users": 25,
      "max_mcp_connections": 20,
      "max_documents_per_month": 1000,
      "storage_gb": 50
    }
  }'
```

---

## Monitoring

### Service Health Dashboard

Available at **Monitoring** page in SaaS Admin. Also accessible via API:

```bash
# Check all service health
curl -sf -X GET "$API/api/admin/health" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" | jq '.services[] | {name, status, latency_ms, last_check}'
```

### Tenant Usage Metrics

```bash
curl -sf -X GET "$API/api/admin/tenants/acme-corp/usage" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" | jq '{
  agents: .agent_count,
  users: .user_count,
  api_calls_mtd: .api_calls,
  storage_used_gb: .storage_gb,
  documents_mtd: .document_count
}'
```

---

## FAQ

**Q: How do I access the SaaS Admin App?**
A: Navigate to `https://admin.runtimeai.io`. Authentication uses the `X-RuntimeAI-Admin-Secret` header for API access, or magic-link login for the web UI.

**Q: Can I run the SaaS Admin App locally?**
A: Yes. `cd SaaSAdminApp && npm install && npm run dev`. Set `VITE_API_URL` to point to the rt19 control plane.

**Q: How do I add a new admin user?**
A: Via the Users page in SaaS Admin, or via API: `POST /api/admin/users` with `X-RuntimeAI-Admin-Secret` header.

**Q: Can I white-label the dashboard for customers?**
A: Not yet. Custom branding is on the roadmap. Currently, all tenants see the RuntimeAI branding.

**Q: How does multi-pod management work?**
A: The SaaS Admin App can manage multiple pods. Each pod has its own API endpoint. The admin app routes requests to the correct pod based on the tenant's pod assignment.

**Q: How do I handle billing disputes?**
A: Access the Billing page in SaaS Admin, view the tenant's billing history, and manage refunds via Stripe dashboard.

### Advanced Setup Questions

**Q: Can I set up usage-based billing?**
A: Yes. Configure Stripe metered billing with usage records reported via `POST /api/admin/billing/usage-record`. Supports per-agent, per-API-call, and per-document pricing.

**Q: How do I onboard a new customer end-to-end?**
A: Use the Onboarding Wizard page: 1) Create tenant 2) Configure entitlements 3) Create admin user 4) Send welcome email 5) Seed initial data. Or use `scripts/seed_rt19_customer.sh` for automated onboarding.

**Q: Can I set up partner billing (reseller model)?**
A: Partner management is available via the Partners page. Partners can manage their own customer tenants with delegated billing.

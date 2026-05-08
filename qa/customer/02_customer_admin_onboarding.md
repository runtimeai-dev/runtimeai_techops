# 02 — Customer Admin Onboarding

**Audience**: Customer IT Admin (first-time setup)
**Prerequisite**: rt19 pod is deployed and healthy ([01_azure_rt19_setup.md](01_azure_rt19_setup.md))
**Last Updated**: 2026-03-17

---

## Step 1: Tenant Provisioning (RuntimeAI Implementation Engineer)

Before a customer can log in, the RuntimeAI IE creates their tenant.

### Via SaaS Admin App

1. Navigate to `https://admin.runtimeai.io`
2. Log in with RuntimeAI admin credentials
3. Go to **Tenants** → **Create Tenant**
4. Fill in:
   - Tenant ID: `acme-corp` (lowercase, hyphenated)
   - Display Name: `Acme Corporation`
   - Plan: `enterprise`
   - Contact Email: `admin@acme-corp.com`
5. Click **Create**

### Via API

```bash
# Set admin secret
ADMIN_SECRET="<from rt19-app-secrets>"
API_BASE="https://api.rt19.runtimeai.io"

# Create tenant
curl -sf -X POST "$API_BASE/api/admin/tenants" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d '{
    "tenant_id": "acme-corp",
    "name": "Acme Corporation",
    "plan": "enterprise",
    "contact_email": "admin@acme-corp.com",
    "settings": {
      "max_agents": 500,
      "max_users": 100,
      "features": ["identity", "discovery", "governance", "firewall", "mcp", "finops", "compliance", "marketplace", "esign", "behavioral", "aiops", "ml"]
    }
  }'
```

### Create First Admin User

```bash
# Create admin user
curl -sf -X POST "$API_BASE/api/admin/users" \
  -H "Content-Type: application/json" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d '{
    "tenant_id": "acme-corp",
    "email": "admin@acme-corp.com",
    "display_name": "Acme Admin",
    "role": "admin"
  }'
```

---

## Step 2: First Login (Customer Admin)

### Magic Link (Production)

1. Navigate to `https://app.rt19.runtimeai.io`
2. Enter your email address: `admin@acme-corp.com`
3. Click **Send Magic Link**
4. Check email for the login link (sent via SendGrid from `noreply@runtimeai.io`)
5. Click the link — you're logged in with a 24-hour session

### Password Login (Dev/Demo Mode)

```bash
# Login and capture session cookie
curl -sf -c /tmp/acme_session.txt -X POST "$API_BASE/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "acme-corp",
    "email": "admin@acme-corp.com",
    "password": "password123"
  }'
```

---

## Step 3: Invite Team Members

### Via Dashboard

1. Navigate to **Settings** → **Team Management**
2. Click **Invite User**
3. Enter email and select role:
   - **Admin**: Full platform access
   - **Operator**: Day-to-day management (no settings)
   - **Auditor**: Read-only access to audit/compliance
   - **Developer**: API access for agent integration
4. Click **Send Invite**

### Via API

```bash
COOKIE="/tmp/acme_session.txt"

# Invite operator
curl -sf -b "$COOKIE" -X POST "$API_BASE/api/users/invite" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "ops@acme-corp.com",
    "role": "operator",
    "display_name": "Acme Ops"
  }'

# Invite auditor
curl -sf -b "$COOKIE" -X POST "$API_BASE/api/users/invite" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "auditor@acme-corp.com",
    "role": "auditor",
    "display_name": "Acme Auditor"
  }'
```

---

## Step 4: Configure Tenant Settings

### RBAC & Access Control

```bash
# Set up role-based access
curl -sf -b "$COOKIE" -X PUT "$API_BASE/api/settings/rbac" \
  -H "Content-Type: application/json" \
  -d '{
    "enforce_mfa": true,
    "session_timeout_hours": 24,
    "password_policy": "strong",
    "ip_whitelist": ["10.0.0.0/8", "172.16.0.0/12"]
  }'
```

### Notification Settings

```bash
# Configure alert channels
curl -sf -b "$COOKIE" -X PUT "$API_BASE/api/settings/notifications" \
  -H "Content-Type: application/json" \
  -d '{
    "email_alerts": true,
    "slack_webhook": "https://hooks.slack.com/services/...",
    "alert_on": ["kill_switch", "high_risk_agent", "budget_exceeded", "compliance_gap"]
  }'
```

---

## Step 5: Verify Dashboard Access

After login, verify you can see all product tabs:

| Tab | What You Should See |
|-----|---------------------|
| **Dashboard** | Overview with KPIs, agent count, risk score |
| **Agents** | Agent Registry (empty until you register agents) |
| **Discovery** | Scanner dashboard (configure scanners next) |
| **Governance** | Guardrails, policies, compliance frameworks |
| **Risk** | Risk dashboard with scoring |
| **Firewall** | DLP rules, egress policies, kill switch |
| **MCP Gateway** | Integration catalog, connections |
| **FinOps** | Cost dashboard, budgets |
| **Compliance** | Framework selection, evidence store |
| **Marketplace** | Agent catalog, installations |
| **eSign** | Document management, templates |
| **Workflows** | Lifecycle workflows, access reviews |
| **Audit** | Immutable audit trail |

---

## Step 6: Quick Verification Script

```bash
API_BASE="https://api.rt19.runtimeai.io"
COOKIE="/tmp/acme_session.txt"

echo "=== Verifying Customer Access ==="

# Test authenticated endpoints
for endpoint in \
  "/api/agents" \
  "/api/discovery/scanners" \
  "/api/guardrails" \
  "/api/risk/dashboard" \
  "/api/compliance/frameworks" \
  "/api/workflows" \
  "/api/audit/events"; do
  STATUS=$(curl -so /dev/null -w "%{http_code}" -b "$COOKIE" "$API_BASE$endpoint")
  if [ "$STATUS" = "200" ]; then
    echo "  ✅ $endpoint → $STATUS"
  else
    echo "  ❌ $endpoint → $STATUS"
  fi
done
```

---

## FAQ

**Q: I didn't receive the magic link email. What do I do?**
A: 1) Check spam/junk folder 2) Verify SendGrid is configured (`kubectl get secret rt19-email-secrets -n rt19`) 3) Check auth-service logs: `kubectl logs -n rt19 deployment/auth-svc --tail=50`

**Q: Can a customer have multiple tenants?**
A: Yes. A single email can be associated with multiple tenants. At login, the user selects which tenant to access.

**Q: How do I reset a user's password?**
A: Passwords are optional (magic-link is primary auth). For demo mode, update via admin API: `POST /api/admin/users/{id}/reset-password`

**Q: What happens if I lock myself out?**
A: Use the admin secret to create a new admin user via the API, or access the database directly: `kubectl exec -it postgres-0 -n rt19 -- psql -U authzion -d authzion`

**Q: Can I use SSO (Okta, Azure AD) instead of magic links?**
A: The auth-service supports OIDC/SSO. Configure via `AUTH_OIDC_ISSUER`, `AUTH_OIDC_CLIENT_ID`, `AUTH_OIDC_CLIENT_SECRET` env vars on the auth-svc deployment.

**Q: How do I enable MFA?**
A: MFA is available in the auth-service but requires configuration. Set `MFA_ENABLED=true` on auth-svc and configure TOTP settings.

### Advanced Setup Questions

**Q: Can I federate with my existing IdP?**
A: Yes, via OIDC or SAML. Configure the auth-service with your IdP's discovery URL. SCIM provisioning is also supported for user sync.

**Q: How does multi-tenant isolation work?**
A: Every database table is keyed by `tenant_id` with row-level security (RLS). No cross-tenant data leakage is possible at the DB layer. Each API request is scoped to the authenticated tenant.

**Q: Can I use my own email provider for magic links?**
A: Yes, the auth-service supports SMTP, SendGrid, and Resend. Configure via environment variables on the auth-svc deployment.

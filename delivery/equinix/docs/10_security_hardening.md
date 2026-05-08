# RuntimeAI Platform — Security Hardening Guide

**Version**: 1.0.0  
**Date**: 2026-03-28  
**Classification**: Confidential — Equinix Trial Delivery

---

## Overview

This document describes the security hardening applied to the RuntimeAI platform for production deployment. All changes are mandatory for SOC 2 and FedRAMP compliance.

---

## 1. Row-Level Security (RLS)

### What It Does

Every database table containing a `tenant_id` column is protected by PostgreSQL Row-Level Security (RLS). This means:

- **Tenant A cannot see Tenant B's data**, even if a bug in the application layer omits a `WHERE tenant_id = ?` clause.
- Every query runs within a tenant context set via `SELECT set_tenant_context($1)`.
- RLS is **forced** (`FORCE ROW LEVEL SECURITY`), meaning even the table owner is subject to policies.

### Verification

```bash
# Run this query to verify RLS is enabled on ALL tenant-scoped tables:
kubectl exec -n rt19 deploy/postgres -- psql -U runtimeai -d authzion -c "
SELECT
  schemaname || '.' || tablename AS table_name,
  rowsecurity AS rls_enabled,
  CASE WHEN c.relforcerowsecurity THEN 'YES' ELSE 'NO' END AS force_rls
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE t.schemaname = 'public'
  AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = t.tablename AND column_name = 'tenant_id'
  )
ORDER BY table_name;
"
# Expected: ALL rows show rls_enabled=true, force_rls=YES
```

### How It Works

```
Application Request (tenant X)
    │
    ▼
Control Plane (Go)
    │
    ├── tx.Exec("SELECT set_tenant_context($1)", tenantID)  ← Parameterized
    │
    ├── tx.QueryRow("SELECT * FROM agents WHERE ...")
    │   └── PostgreSQL applies RLS policy: WHERE tenant_id = current_setting('app.tenant_id')
    │
    └── Result: Only tenant X's data returned
```

### Migration 101

Migration `101_rls_comprehensive_audit.sql` programmatically:
1. Iterates all tables with a `tenant_id` column
2. Enables `ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY`
3. Creates `tenant_isolation` policy if missing
4. Grants `SELECT, INSERT, UPDATE, DELETE` to `runtimeai_app` role

This migration runs automatically on service startup.

---

## 2. SQL Injection Prevention

### Before (Vulnerable)
```go
// ❌ String concatenation — SQL injection risk
tx.Exec("SET LOCAL app.tenant_id = '" + tenantID + "'")
```

### After (Hardened)
```go
// ✅ Parameterized — no injection possible
tx.Exec("SELECT set_tenant_context($1)", tenantID)
```

**34 instances** across 10 route files were fixed:
- `routes.go`, `routes_mcp.go`, `routes_governance.go`
- `routes_esign.go`, `routes_audit.go`, `routes_identity.go`
- `routes_compliance.go`, `routes_discovery.go`, `routes_idp.go`

---

## 3. Secrets Management

### Policy

- **NEVER** hardcode secrets in code, environment files, or git
- All secrets MUST be stored in a vault (Azure Key Vault, HashiCorp Vault, or K8s Secrets)
- The `create-secrets.sh` script pulls all 15+ secrets from Azure Key Vault automatically

### Secret Inventory

| Secret | K8s Secret Object | Vault Key |
|--------|--------------------|-----------|
| Database URL | `rt19-db-secret` | `db-connection-string` |
| JWT Secret | `rt19-app-secrets` | `jwt-secret` |
| Admin Secret | `rt19-app-secrets` | `admin-secret` |
| API Key Secret | `rt19-app-secrets` | `api-key-secret` |
| Session Secret | `rt19-app-secrets` | `session-secret` |
| eSign JWT Secret | `rt19-app-secrets` | `esign-jwt-secret` |
| Storage Signing Secret | `rt19-app-secrets` | `storage-signing-secret` |
| Redis URL | `rt19-app-secrets` | `redis-url` |
| SendGrid API Key | `rt19-email-secrets` | `sendgrid-api-key` |
| SMTP Host | `rt19-email-secrets` | `smtp-host` |
| SMTP Port | `rt19-email-secrets` | `smtp-port` |
| SMTP User | `rt19-email-secrets` | `smtp-user` |
| SMTP Pass | `rt19-email-secrets` | `smtp-pass` |
| Backup Storage Account | `rt19-app-secrets` | `backup-azure-storage-account` |
| Backup Storage Key | `rt19-app-secrets` | `backup-azure-storage-key` |

### Vault Integration

```bash
# Pull a secret from Azure Key Vault:
az keyvault secret show --vault-name runtimeai-rt19-kv \
  --name jwt-secret --query value -o tsv

# Set a new secret:
az keyvault secret set --vault-name runtimeai-rt19-kv \
  --name <name> --value <value>
```

For HashiCorp Vault deployments, set `VAULT_PROVIDER=hashicorp-vault` in `.env`.

---

## 4. API-Only Seeding

### Policy

All data seeding MUST use API calls exclusively. Direct SQL (`psql`, `INSERT INTO`) is **strictly prohibited** because:

1. **Bypasses RLS** — direct SQL doesn't set tenant context, creating data accessible to all tenants
2. **Skips validation** — API endpoints validate input, enforce business rules, and create audit trails
3. **Breaks idempotency** — SQL inserts can create duplicates; APIs handle "already exists" gracefully

### Correct Pattern

```bash
# ✅ API-only seeding (exercises RLS)
curl -X POST https://api.runtimeai.io/api/admin/tenants \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "eqx-trial", "name": "Equinix Trial"}'
```

### Anti-Pattern

```bash
# ❌ NEVER do this — bypasses RLS and tenant isolation
psql $DATABASE_URL -c "INSERT INTO tenants (id, name) VALUES ('eqx-trial', 'Equinix Trial')"
```

---

## 5. Admin IdP Hardening

POST operations to admin endpoints now use `BeginTenantTx` to ensure:
- Tenant context is set before any data insertion
- RLS policies are enforced even for admin operations
- SQL injection is impossible via parameterized queries

DELETE operations include explicit `tenant_id` WHERE clauses as defense-in-depth, even though RLS provides the primary isolation.

---

## 6. Compliance Posture

| Standard | Relevant Controls | Coverage |
|----------|-------------------|----------|
| **SOC 2** | CC6.1 (Logical Access), CC6.3 (Unauthorized Access), CC7.1 (Monitoring) | ✅ RLS, parameterized SQL, audit logs |
| **FedRAMP** | AC-3 (Access Enforcement), AC-4 (Information Flow), SI-10 (Input Validation) | ✅ RLS forced, SQL injection prevented |
| **EU AI Act** | Article 9 (Data Governance), Article 12 (Record-Keeping) | ✅ Tenant isolation, immutable audit chain |
| **ISO 27001** | A.8.3 (Access Restriction), A.8.11 (Data Masking) | ✅ RLS, DLP integration |

---

## 7. Security Checklist for Deployment

- [ ] All secrets pulled from vault (no hardcoded values)
- [ ] RLS enabled and forced on all tenant-scoped tables
- [ ] Migration 101 applied (auto-runs on startup)
- [ ] `go build ./...` passes clean (no compilation errors)
- [ ] API-only seeding (zero `psql` commands in seed scripts)
- [ ] TLS enabled on all external endpoints
- [ ] Database user is `runtimeai_app` (not superuser)
- [ ] Redis password-protected and TLS-enabled for external connections
- [ ] Audit logging enabled for all admin operations
- [ ] CORS configured for deployment domain only

---

*This document is part of the RuntimeAI Equinix Delivery Package. Confidential.*

# SaaS Admin Guide

**Product**: Platform Administration | **Version**: 1.0.0

---

## Overview
Multi-tenant platform management for SaaS operators. Manage tenants, billing, users, and quotas.

## Access
- **SaaS Admin UI**: `https://<YOUR_ENDPOINT>:7080/`
- **API Base**: `https://<YOUR_ENDPOINT>/api/tenants`

## Key Features
- Tenant provisioning and deprovisioning
- User management (RBAC: admin, operator, auditor)
- Quota management (agents, API calls, storage)
- Billing and subscription management
- Tenant impersonation for support

## Key APIs

```bash
# List all tenants
curl https://<YOUR_ENDPOINT>/api/tenants \
  -H "X-RuntimeAI-Admin-Secret: <SECRET>"

# Impersonate tenant (support workflow)
# Navigate to SaaS Admin → Tenants → Click "Impersonate"
# This opens the Dashboard UI as the tenant admin
```

## On-Prem Notes
- SaaS Admin (:7080) is for platform operators only
- Restrict access via network policy or VPN

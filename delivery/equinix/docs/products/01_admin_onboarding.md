# Admin Onboarding Guide

**Product**: RuntimeAI Platform Administration | **Version**: 1.0.0

---

## Prerequisites
- Admin credentials (provided during tenant provisioning)
- Access to `https://<YOUR_ENDPOINT>/ui/`

## Step 1: Login to Dashboard

Navigate to `https://<YOUR_ENDPOINT>/ui/` and login with your admin email and password.

## Step 2: Create Tenant

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/tenants \
  -H "X-RuntimeAI-Admin-Secret: <ADMIN_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"name": "My Organization", "slug": "my-org", "admin_email": "admin@myorg.com"}'
```

## Step 3: Create Users

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/users \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"email": "operator@myorg.com", "role": "operator", "name": "Jane Operations"}'
```

## Step 4: Configure Quotas

```bash
curl -X PUT https://<YOUR_ENDPOINT>/api/quotas \
  -H "X-RuntimeAI-Admin-Secret: <ADMIN_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"tenant_id": "my-org", "quota_type": "max_agents", "limit_value": 100}'
```

## Step 5: Register First Agent

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/agents \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-first-agent", "owner": "dev-team", "environment": "staging", "skills": ["data-processing"]}'
```

## On-Prem Notes
- For on-prem, admin secret is set via K8s secret `rt19-app-secrets`
- Use `kubectl get secret rt19-app-secrets -n rt19 -o jsonpath='{.data.ADMIN_SECRET}' | base64 -d` to retrieve

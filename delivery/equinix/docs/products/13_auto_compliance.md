# Auto AI Compliance Guide

**Product**: AAIC (Automated AI Compliance) | **Version**: 1.0.0

---

## Overview
Automated compliance evidence collection and reporting for SOC 2, GDPR, EU AI Act, ISO 27001.

## Components

| Service | Port | Purpose |
|---------|------|---------|
| AAIC Service | 7090 | Compliance automation engine |
| Auditor Dashboard | 7091 | Auditor-facing compliance portal |

## Key Features
- Automated evidence collection from all platform services
- Compliance framework mapping (controls → evidence)
- Audit trail with immutable Merkle hash chain
- SOC 2 Type II evidence bundle generation
- EU AI Act risk assessment automation

## Key APIs

```bash
# Generate compliance report
curl -X POST https://<YOUR_ENDPOINT>/api/compliance/reports \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"framework": "soc2", "period": "2026-Q1"}'

# Get compliance score
curl https://<YOUR_ENDPOINT>/api/compliance/score?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Verify audit chain
curl https://<YOUR_ENDPOINT>/api/audit/verify?tenant_id=<TENANT_ID> \
  -H "X-API-Key: <AUDITOR_KEY>"
```

## On-Prem Notes
- AAIC proxies through the control-plane (no direct external access needed)
- Auditor Dashboard is accessible at `:7091` — restrict via NetworkPolicy
- Evidence is stored in PostgreSQL with RLS tenant isolation

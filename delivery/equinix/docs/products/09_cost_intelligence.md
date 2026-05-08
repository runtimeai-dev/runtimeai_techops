# AI Cost Intelligence Guide

**Product**: FineOps (AI Cost Management) | **Version**: 1.0.0

---

## Overview
Budget tracking, cost allocation, spend alerts, and chargeback for AI workloads.

## Components

| Service | Port | Purpose |
|---------|------|---------|
| Cost Ledger | 8098 | Real-time cost tracking |
| Billing Service | 8101 | Invoice and chargeback |
| AI FinOps Service | 8100 | Budget management |

## Key APIs

```bash
# Get budget overview
curl https://<YOUR_ENDPOINT>/api/cost/budgets?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Set budget alert
curl -X POST https://<YOUR_ENDPOINT>/api/cost/budgets \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "Q1 AI Spend", "amount": 50000, "currency": "USD", "alert_threshold": 80}'

# Get cost breakdown by agent
curl https://<YOUR_ENDPOINT>/api/cost/breakdown?tenant_id=<TENANT_ID>&group_by=agent \
  -H "Authorization: Bearer <TOKEN>"
```

## On-Prem Notes
- Cost Ledger (:8098) requires heartbeat from Data Plane for usage metrics
- Budget alerts are sent via email (configure SMTP/SendGrid in K8s secrets)

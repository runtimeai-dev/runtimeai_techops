# AIops Workflows Guide

**Product**: Lifecycle Workflows | **Version**: 1.0.0

---

## Overview
Event-driven automation for agent lifecycle management: provisioning, decommissioning, access reviews.

## Key APIs

```bash
# List workflows
curl https://<YOUR_ENDPOINT>/api/workflows?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Create workflow
curl -X POST https://<YOUR_ENDPOINT>/api/workflows \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "agent-onboarding", "trigger": "agent.created", "actions": [{"type": "certify"}, {"type": "assign_policy", "policy_id": "default-prod"}]}'

# HRIS Webhook (lifecycle events from HR systems)
curl -X POST https://<YOUR_ENDPOINT>/api/lifecycle/hris/webhook \
  -H "Content-Type: application/json" \
  -d '{"event": "employee_offboarded", "employee_id": "emp-123"}'
```

## On-Prem Notes
- Lifecycle Worker runs as a background goroutine within the control-plane
- HRIS webhook requires configuring your HR system to POST to the webhook URL

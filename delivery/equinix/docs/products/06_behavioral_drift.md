# Behavioral Drift Detection Guide

**Product**: Drift Engine | **Version**: 1.0.0

---

## Overview
Monitors agent behavior in real-time, detects deviations from baseline patterns, and triggers alerts.

## Key APIs

```bash
# Get drift findings
curl https://<YOUR_ENDPOINT>/api/drift/findings?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Get agent behavioral profile
curl https://<YOUR_ENDPOINT>/api/agents/<AGENT_ID>/drift-profile \
  -H "Authorization: Bearer <TOKEN>"
```

## How It Works
1. **Baseline**: Drift Engine monitors agent API calls and establishes behavioral baseline
2. **Detection**: Any deviation (new endpoints, unusual data volumes, timing anomalies) is flagged
3. **Alert**: Drift findings surface in Dashboard → Drift Detection page
4. **Action**: Operator can quarantine agent or escalate to Kill Switch

## On-Prem Notes
- Drift Engine (:8099) requires access to Redis for event streaming
- Configure alert thresholds via `/api/config` endpoint

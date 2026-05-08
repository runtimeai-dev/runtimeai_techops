# Governance & Compliance Guide

**Product**: AI Governance Engine | **Version**: 1.0.2

---

## Overview
Centralized policy management, Separation of Duties (SoD), access reviews, and compliance framework automation.

## Key APIs

```bash
# List policies
curl https://<YOUR_ENDPOINT>/api/policies?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Create policy
curl -X POST https://<YOUR_ENDPOINT>/api/policies \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "no-production-access", "type": "rego", "content": "package authz\ndefault allow = false"}'

# List SoD rules
curl https://<YOUR_ENDPOINT>/api/sod-rules?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Compliance frameworks (SOC2, GDPR, EU AI Act)
curl https://<YOUR_ENDPOINT>/api/compliance/frameworks?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"

# Access reviews
curl https://<YOUR_ENDPOINT>/api/access-reviews?tenant_id=<TENANT_ID> \
  -H "Authorization: Bearer <TOKEN>"
```

## Policy Sync Status Dashboard (v1.0.2+)

Monitor policy distribution across Control Plane and Data Plane with the **Policy Sync Status** page:

### Three-Stage Version Tracking
Track OPA policy bundles through the entire pipeline:

1. **Control Plane Stage** — Active version in the Control Plane
   - Shows promoted policy version
   - Promotion timestamp
   - Release notes/changelog

2. **Bundle Cache Push** — Distribution via bundle-cache service
   - Shows when bundles are pushed to bundle-cache:8094
   - Monitors push success/failure

3. **Flow Enforcer Stage** — Loaded version in Data Plane
   - Shows version loaded into WASM enforcement plugin
   - Load timestamp
   - Bundle age (time since loaded)

### Sync Status Indicators
- **In Sync** — CP version matches Enforcer loaded version
- **Stale DP** — Enforcer running old version (bundle-cache push may have failed)
- **No DP Connected** — No heartbeat from any Data Plane nodes
- **No Active Policy** — No policy version promoted in CP
- **Pushing...** — Bundle push in progress

### Policy Drift Detection
- **Automatic Alerts** — Stale bundle detection triggers amber alerts
- **Suggested Actions** — "Force Sync Now" button for immediate re-push
- **Age Tracking** — Human-readable bundle age (e.g., "2h 15m old")
- **Failure Diagnostics** — Error messages indicate bundle-cache failures or enforcer connectivity issues

### Operational Monitoring
- **Real-time Refresh** — Auto-refreshes every 60 seconds
- **Manual Refresh** — Click refresh button for immediate status update
- **Policy Editor Link** — Quick navigation to policy editor for version changes
- **Historical Context** — View CP promotion timestamps for policy version auditing

## On-Prem Notes
- OPA bundles are served by the control-plane at `/opa/bundles/<tenant>/bundle.tar.gz`
- Policy changes take effect within 30 seconds (OPA polling interval)
- Bundle-cache service (:8094) must be reachable from Data Plane nodes
- Policy sync dashboard requires network access to control-plane for real-time status

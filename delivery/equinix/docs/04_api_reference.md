# RuntimeAI Platform — API Reference (Summary)

**Version**: 1.0.0  
**Date**: 2026-03-27  
**Classification**: Confidential — Equinix Trial Delivery

---

## Authentication

All API calls require one of:

| Method | Header | Use Case |
|--------|--------|----------|
| Session Cookie | `Cookie: session_id=<ID>` | Dashboard UI users |
| API Key | `X-API-Key: <KEY>` | External integrations |
| Bearer Token | `Authorization: Bearer <TOKEN>` | Service-to-service |
| Admin Secret | `X-RuntimeAI-Admin-Secret: <SECRET>` | Admin operations |

---

## Core APIs (273 Total Endpoints)

### Agent Management

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/agents` | auditor | List all agents for tenant |
| POST | `/api/agents` | operator | Register new agent |
| GET | `/api/agents/{id}` | auditor | Get agent details |
| PATCH | `/api/agents/{id}` | operator | Update agent metadata |
| DELETE | `/api/agents/{id}` | admin | Remove agent |
| POST | `/api/agents/{id}/certify` | operator | Certify agent (30-day validity) |
| POST | `/api/agents/{id}/verify-image` | operator | Verify container image signature |
| POST | `/api/agents/{id}/sbom` | operator | Ingest SBOM for agent |
| GET | `/api/agents/{id}/supply-chain` | auditor | Get supply chain status |

### Audit & Compliance

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/audit` | auditor | List audit evidence |
| GET | `/api/audit/verify` | auditor | Verify Merkle hash chain integrity |
| GET | `/api/audit/export` | auditor | Export audit evidence (JSON/CSV) |
| GET | `/api/compliance/frameworks` | auditor | List compliance frameworks |
| GET | `/api/compliance/evidence` | auditor | Get compliance evidence |
| POST | `/api/compliance/evidence` | operator | Submit compliance evidence |

### Kill Switch

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/kill-switch/activate` | admin | Activate emergency kill switch |
| POST | `/api/kill-switch/deactivate` | admin | Deactivate kill switch |
| GET | `/api/kill-switch/active` | auditor | List active kill switches |

### Governance

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/policies` | auditor | List policies |
| POST | `/api/policies` | operator | Create policy |
| GET | `/api/policies/egress` | auditor | List egress policies |
| POST | `/api/policies/egress` | operator | Create egress policy |
| POST | `/api/policies/egress/check` | auditor | Check egress policy decision |
| GET | `/api/sod-rules` | auditor | List Separation of Duties rules |

### MCP Gateway (44+ Endpoints)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/mcp/servers` | auditor | List MCP servers |
| POST | `/api/mcp/servers` | operator | Register MCP server |
| GET | `/api/mcp/tools` | auditor | List MCP tools |
| POST | `/api/mcp/tools` | operator | Register MCP tool |
| POST | `/api/mcp/invoke` | operator | Invoke MCP tool (with governance) |
| GET | `/api/mcp/audit` | auditor | MCP invocation audit log |
| POST | `/api/mcp/rate-limit` | admin | Configure MCP rate limits |

### MCP Governance (OPER-045 — 10-Layer Pipeline)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/mcp/policy/rules` | operator | List policy rules |
| POST | `/api/mcp/policy/rules` | operator | Create policy rule (deny/allow/review + glob pattern) |
| PATCH | `/api/mcp/policy/rules/{id}` | operator | Update rule |
| DELETE | `/api/mcp/policy/rules/{id}` | operator | Delete rule |
| GET | `/api/mcp/governance/profiles` | operator | List agent profiles (access packages) |
| POST | `/api/mcp/governance/profiles` | operator | Create/upsert agent profile |
| GET | `/api/mcp/guardrails/rules` | operator | List guardrail rules |
| POST | `/api/mcp/guardrails/rules` | operator | Create guardrail (rate_limit, time_based, cost_limit) |
| GET | `/api/mcp/governance/actions` | operator | Query audit log (filter: agent, tool, decision) |
| POST | `/api/mcp/governance/actions/record` | service | MCP Gateway writes audit entries |
| GET | `/api/mcp/credentials` | operator | List stored credentials (metadata only) |
| POST | `/api/mcp/credentials` | operator | Store credential (vault_ref or encrypted) |
| POST | `/api/mcp/credentials/{id}/rotate` | operator | Rotate credential |
| POST | `/api/mcp/credentials/{id}/revoke` | operator | Revoke credential |

### MCP Marketplace (Approval Workflow)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/mcp/marketplace/request` | operator | Request MCP server install |
| GET | `/api/mcp/marketplace/installs` | operator | List my installs with status |
| GET | `/api/admin/mcp/requests` | admin | List pending install requests (all tenants) |
| POST | `/api/admin/mcp/requests/{id}/approve` | admin | Approve request → lifecycle command |
| POST | `/api/admin/mcp/requests/{id}/reject` | admin | Reject with reason |
| POST | `/api/mcp/lifecycle/result` | service | DP reports install success/failure |

### DLP (Data Loss Prevention)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/mcp/dlp/scan` | operator | Scan text for PII. Body: `{"content":"text","agent_id":"id","direction":"outbound"}` |
| GET | `/api/mcp/dlp/stats` | operator | DLP scan statistics |

### Discovery (24 Endpoints)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/inventory/discovered` | auditor | List all discovered agents |
| GET | `/api/discovery/inbox` | operator | Shadow AI Inbox (pending triage) |
| POST | `/api/discovery/scan` | operator | Trigger discovery scan |
| GET | `/api/discovery/findings` | auditor | List discovery findings |
| POST | `/api/discovery/import` | operator | Import discovered agent to registry |

### Administration (23 Endpoints)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/tenants` | admin | List tenants |
| POST | `/api/tenants` | admin | Create tenant |
| GET | `/api/users` | admin | List users for tenant |
| POST | `/api/users` | admin | Create user |
| GET | `/api/quotas` | operator | Get quota usage |
| PUT | `/api/quotas` | admin | Update quotas |

### Risk & OAuth

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/risk-scores` | auditor | Get risk scores |
| GET | `/api/oauth/clients` | auditor | List OAuth clients |
| POST | `/api/oauth/clients` | operator | Create OAuth client |
| GET | `/api/access-reviews` | auditor | List access review cycles |

### SIEM Integration

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/siem/config` | auditor | Get SIEM configuration |
| PUT | `/api/siem/config` | operator | Update SIEM configuration |
| POST | `/api/siem/test` | operator | Test SIEM connection |

---

## Example Requests

### Register an Agent

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/agents \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "payment-processor-v2",
    "owner": "fintech-team",
    "environment": "production",
    "skills": ["payment-processing", "fraud-detection"],
    "risk_tier": "HIGH"
  }'
```

### Verify Audit Chain

```bash
curl -s https://<YOUR_ENDPOINT>/api/audit/verify?tenant_id=equinix-trial \
  -H "X-API-Key: <AUDITOR_KEY>" | jq .
# Expected: {"valid": true, "message": "Chain integrity verified. All hashes are valid."}
```

### Activate Kill Switch

```bash
curl -X POST https://<YOUR_ENDPOINT>/api/kill-switch/activate \
  -H "X-RuntimeAI-Admin-Secret: <SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "scope": "agent",
    "target": "az-agent-rogue-001",
    "reason": "Anomalous behavior detected",
    "duration": "1h"
  }'
```

### Export Compliance Evidence (CSV)

```bash
curl -s "https://<YOUR_ENDPOINT>/api/audit/export?tenant_id=equinix-trial&format=csv" \
  -H "X-API-Key: <AUDITOR_KEY>" \
  -o runtimeai_audit_log.csv
```

---

## Health Check Endpoints

| Service | URL | Expected Response |
|---------|-----|-------------------|
| Control Plane | `http://control-plane:8080/healthz` | `200 OK` |
| Auth Service | `http://auth-service:8090/health` | `200 OK` |
| Identity DNS | `http://identity-dns:8053/health` | `200 OK` |
| ML Intelligence | `http://ml-intelligence-service:8095/health` | `200 OK` |
| eSign Service | `http://esign-service:3001/api/v1/sign/health` | `200 OK` |

---

## Rate Limits

| Endpoint Category | Limit | Window |
|-------------------|-------|--------|
| Authentication | 10 req | 60s |
| API (standard) | 100 req | 60s |
| Kill Switch | 5 req | 60s |
| Audit Export | 10 req | 300s |
| Discovery Scan | 2 req | 300s |

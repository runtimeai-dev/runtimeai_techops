# RuntimeAI — Product Guides (Equinix Trial)

**Version**: 1.0.0  
**Date**: 2026-03-27  

---

## Product Portfolio (10 Products)

These guides are adapted from the RuntimeAI product documentation for on-premises deployment. All Azure-specific URLs have been replaced with `<YOUR_ENDPOINT>` placeholders.

---

### 1. AI Agent Registry

**Purpose**: Centralized catalog of all AI agents, their owners, environments, skills, and lifecycle status.

**Key Configuration**:
```bash
# Register an agent
curl -X POST https://<YOUR_ENDPOINT>/api/agents \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "trading-bot-v3",
    "owner": "quant-team",
    "environment": "production",
    "skills": ["order-execution", "risk-assessment"],
    "risk_tier": "HIGH"
  }'

# List agents
curl https://<YOUR_ENDPOINT>/api/agents \
  -H "Authorization: Bearer <TOKEN>"
```

**On-Prem Notes**: Agent discovery works with network scanners that probe for AI endpoints. Configure scanner targets in the Discovery settings.

---

### 2. AI Compliance Hub (AAIC)

**Purpose**: SOC 2 / ISO 27001 / GDPR / EU AI Act compliance automation.

**Key Configuration**:
```bash
# Get compliance frameworks
curl https://<YOUR_ENDPOINT>/api/compliance/frameworks \
  -H "Authorization: Bearer <TOKEN>"

# Submit evidence
curl -X POST https://<YOUR_ENDPOINT>/api/compliance/evidence \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "framework_id": "soc2",
    "control_id": "CC1.1",
    "evidence_type": "audit_log",
    "description": "Agent activity log for Q1 2026"
  }'
```

**Auditor Dashboard**: Available at `https://<YOUR_ENDPOINT>:7091/`

---

### 3. AI Firewall & DLP

**Purpose**: Real-time traffic inspection, egress policy enforcement, data loss prevention.

**Key Configuration**:
```bash
# Create egress policy (block external API calls)
curl -X POST https://<YOUR_ENDPOINT>/api/policies/egress \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "destination": "*.openai.com",
    "action": "block",
    "category": "ai-vendor"
  }'

# Check if destination is allowed
curl -X POST https://<YOUR_ENDPOINT>/api/policies/egress/check \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"destination": "api.openai.com"}'
```

**Data Plane**: Flow Enforcer (Envoy + Wasm) intercepts all agent traffic. WAF (OpenResty) provides L7 inspection.

---

### 4. eSign

**Purpose**: Digital document signing with audit trails and compliance evidence.

**Key Configuration**:
- eSign Service: `https://<YOUR_ENDPOINT>:3001`
- eSign Landing: `https://<YOUR_ENDPOINT>:3002`
- Requires SendGrid API key for email notifications
- Supports multi-signer workflows with sequential signing

---

### 5. Kill Switch

**Purpose**: Emergency shutdown of rogue AI agents (< 50ms latency via Redis).

**Key Configuration**:
```bash
# Activate (immediate effect)
curl -X POST https://<YOUR_ENDPOINT>/api/kill-switch/activate \
  -H "X-RuntimeAI-Admin-Secret: <SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"scope": "agent", "target": "<AGENT_ID>", "reason": "Anomalous behavior", "duration": "1h"}'

# Deactivate
curl -X POST https://<YOUR_ENDPOINT>/api/kill-switch/deactivate \
  -H "X-RuntimeAI-Admin-Secret: <SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"scope": "agent", "target": "<AGENT_ID>"}'
```

---

### 6. FineOps (AI Cost Management)

**Purpose**: Budget tracking, cost allocation, and spend alerts for AI workloads.

**Key Configuration**:
- Budget service: `https://<YOUR_ENDPOINT>:8101`
- Cost Ledger: handles real-time cost tracking
- Dashboard: Budget & Cost page shows allocation per agent/owner

---

### 7. MCP Gateway

**Purpose**: Governance layer for Model Context Protocol — policy enforcement on tool calls.

**Key Configuration**:
```bash
# Register MCP server
curl -X POST https://<YOUR_ENDPOINT>/api/mcp/servers \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "financial-tools", "url": "https://tools.internal:8080"}'

# Invoke tool with governance
curl -X POST https://<YOUR_ENDPOINT>/api/mcp/invoke \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"server": "financial-tools", "tool": "execute-trade", "params": {"symbol": "AAPL", "qty": 100}}'
```

---

### 8. Identity Fabric

**Purpose**: Agent identity lifecycle — certificates, SPIFFE IDs, OAuth, mTLS.

**Key Configuration**:
- Bot CA: Issues X.509 certificates for agent-to-agent mTLS
- Identity DNS: Resolves agent names to endpoints via DoH
- IdP Connectors: Federate with external identity providers

---

### 9. Discovery Scanner

**Purpose**: Automated detection of AI agents across the network.

**Key Configuration**:
```bash
# Trigger scan
curl -X POST https://<YOUR_ENDPOINT>/api/discovery/scan \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"scan_type": "network", "targets": ["10.0.0.0/24"]}'

# List discovered agents
curl https://<YOUR_ENDPOINT>/api/discovered-agents \
  -H "Authorization: Bearer <TOKEN>"
```

---

### 10. Marketplace

**Purpose**: Pre-built policy packs, compliance templates, and integration modules.

**Key Configuration**:
- Marketplace service: `https://<YOUR_ENDPOINT>:8096`
- Browse and install compliance packs (SOC 2, GDPR, EU AI Act)
- One-click policy deployment for common governance patterns

---

## On-Prem Deployment Notes

| Area | Cloud Default | On-Prem Equivalent |
|------|--------------|-------------------|
| Secrets | Azure Key Vault | HashiCorp Vault / K8s Secrets |
| DNS | Azure DNS | CoreDNS / Identity DNS service |
| Monitoring | Azure Monitor | Prometheus + Grafana |
| Storage | Azure Blob | MinIO / NFS |
| Email | SendGrid SaaS | SMTP relay / Mailhog for testing |
| TLS Certs | Let's Encrypt | Internal CA / cert-manager |

# RuntimeAI Platform — Training Walkthrough

**Version**: 1.0.0-trial
**Audience**: Equinix Security Operations Team

---

## Walkthrough 1: Platform Login & Navigation (5 min)

### Steps
1. **Open Dashboard**: Navigate to `https://app.<YOUR_DOMAIN>` in your browser
2. **Login**: Enter your credentials (email + password) or use SSO
3. **Dashboard Overview**: You'll see the main AI Ops Center with:
   - Agent count (registered/discovered)
   - Active kill switches
   - Compliance score
   - Recent audit events
4. **Navigation**: Use the left sidebar to access all platform modules:
   - **Agents** — Registered and discovered AI agents
   - **Policies** — Egress control, DLP rules
   - **Compliance** — SOC 2, GDPR, EU AI Act frameworks
   - **Discovery** — Shadow AI scanner results
   - **MCP Gateway** — Governed tool access
   - **Kill Switch** — Emergency stop
   - **Audit Trail** — Cryptographic event chain

### Key Features to Note
- Dark/Light mode toggle (top right)
- Tenant switcher (for multi-tenant operators)
- Real-time notifications bell icon

---

## Walkthrough 2: Agent Registration & Discovery (10 min)

### Manual Agent Registration
1. Navigate to **Agents** → **Registered Agents**
2. Click **+ Register Agent**
3. Fill in:
   - Name: `payment-processor-v1`
   - Owner: `finops-team`
   - Description: `Validates and routes payment transactions`
   - Risk Tier: `Critical`
4. Click **Save** — agent appears in the list with a unique ID and identity certificate

### Shadow AI Discovery
1. Navigate to **Discovery** → **Discovered Agents**
2. View agents found by automated scanners:
   - Network scanner (scans subnets for AI service ports)
   - VSCode scanner (finds Copilot/Cursor extensions)
   - MCP config scanner (detects MCP server configurations)
3. For each discovered agent, you can:
   - **Approve** — Move to registered agents
   - **Quarantine** — Block from network
   - **Investigate** — View source details, risk score

### API Method
```bash
curl -X POST https://api.<YOUR_DOMAIN>/api/agents \
  -H "Cookie: session=<YOUR_SESSION>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "data-analyzer-v2",
    "owner": "data-science",
    "risk_tier": "high"
  }'
```

---

## Walkthrough 3: Kill Switch (5 min)

### Activate Kill Switch
1. Navigate to **Kill Switch**
2. Click **Activate Kill Switch**
3. Select scope:
   - **Agent** — Kill specific agent
   - **Tenant** — Kill all agents for a tenant
   - **Global** — Kill all agents (emergency only)
4. Select severity: `Critical`, `High`, or `Medium`
5. Enter reason: "Anomalous behavior detected"
6. Click **Activate** — response time is **sub-200ms**

### Verify
- Dashboard updates immediately showing active kill switch
- Agent status changes to `KILLED` in agent list
- Audit event logged with cryptographic hash

### Deactivate
1. Navigate to **Kill Switch** → **Active**
2. Click **Deactivate** next to the active switch
3. Confirm — agent resumes normal operation

### API Method
```bash
# Activate
curl -X POST https://api.<YOUR_DOMAIN>/api/kill-switch/activate \
  -H "X-RuntimeAI-Admin-Secret: <SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"scope":"agent","target":"<AGENT_ID>","reason":"Test drill","duration":"5m"}'

# Check active
curl https://api.<YOUR_DOMAIN>/api/kill-switch/active \
  -H "Cookie: session=<YOUR_SESSION>"
```

---

## Walkthrough 4: Policy Engine & DLP (10 min)

### Create Egress Policy
1. Navigate to **Policies** → **Egress Policies**
2. Click **+ New Policy**
3. Configure:
   - Destination: `*.openai.com`
   - Action: `Block`
   - Category: `LLM Provider`
4. Save — all agent traffic to OpenAI is now blocked

### DLP Scanning
1. Navigate to **AI Firewall** → **DLP**
2. Test scan: enter text containing PII (e.g., "SSN: 123-45-6789")
3. View scan results — detections highlighted with severity

### API Method
```bash
# Scan content for PII
curl -X POST https://api.<YOUR_DOMAIN>/api/mcp/dlp/scan \
  -H "Cookie: session=<YOUR_SESSION>" \
  -H "Content-Type: application/json" \
  -d '{"content":"Customer SSN: 123-45-6789","agent_id":"test","direction":"outbound"}'
```

---

## Walkthrough 5: Compliance & Audit (10 min)

### View Compliance Frameworks
1. Navigate to **Compliance** → **Frameworks**
2. View active frameworks: SOC 2 Type II, GDPR, EU AI Act
3. Each framework shows:
   - Compliance score (%)
   - Control count (passed/failed/not assessed)
   - Evidence mapping

### Audit Trail Verification
1. Navigate to **Audit Trail**
2. View events with SHA-256 hashes forming a Merkle chain
3. Click **Verify Chain** — confirms cryptographic integrity
4. Each event shows: timestamp, action, actor, affected entity, hash

### API Method
```bash
# Verify audit chain
curl https://api.<YOUR_DOMAIN>/api/audit/verify?tenant_id=<TENANT_ID> \
  -H "Cookie: session=<YOUR_SESSION>"
# Expected: {"valid": true, "chain_length": N}
```

---

## Walkthrough 6: MCP Gateway (10 min)

### View MCP Servers
1. Navigate to **Discovery** → **MCP Servers**
2. View discovered MCP server configurations with:
   - Transport type (stdio, SSE, HTTP)
   - Tools inventory
   - Risk classification
   - Access controls

### Governed Tool Access
1. Navigate to **MCP Gateway** → **Tools**
2. View all available MCP tools across servers
3. Each tool shows: name, server, risk level, invocation count
4. Invoke a tool with governance applied:
   - DLP scanning on input/output
   - Egress policy enforcement
   - Rate limiting
   - Audit logging

---

## Walkthrough 7: eSign Service (10 min)

1. Navigate to `https://esign.<YOUR_DOMAIN>`
2. **Create Document**: Upload a PDF
3. **Add Signers**: Enter email addresses
4. **Send for Signing**: Recipients get email with signing link
5. **Track Status**: View document status (pending, signed, completed)
6. **Download**: Get signed PDF with audit trail embedded

---

## Walkthrough 8: Operational Tasks (5 min)

### Backup
```bash
./backup.sh --output /mnt/backups
```

### Health Check
```bash
kubectl get pods -n rt19
curl https://api.<YOUR_DOMAIN>/health
```

### View Logs
```bash
kubectl logs -n rt19 deploy/control-plane --tail=50 -f
```

### Secret Rotation
```bash
# Generate new JWT secret
NEW_SECRET=$(openssl rand -hex 32)
# Update K8s secret
kubectl create secret generic rt19-app-secrets -n rt19 \
  --from-literal=JWT_SECRET=$NEW_SECRET --dry-run=client -o yaml | kubectl apply -f -
# Restart services
kubectl rollout restart deploy -n rt19
```

---

## Quick Reference

| Task | Command/URL |
|------|-------------|
| Dashboard | `https://app.<DOMAIN>` |
| API docs | `https://api.<DOMAIN>/health` |
| Kill switch | **Dashboard** → Kill Switch → Activate |
| Compliance | **Dashboard** → Compliance → Frameworks |
| Audit verify | `GET /api/audit/verify?tenant_id=<ID>` |
| DLP scan | `POST /api/mcp/dlp/scan` |
| Backup | `./backup.sh` |
| Restore | `./docs/08_disaster_recovery.md` |
| SBOM | `./generate-sbom.sh` |

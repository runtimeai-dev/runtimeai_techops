# Real SoW Testing — What I Need From You

**Goal**: Test every SoW item with REAL data before Equinix delivery. No simulations.

---

## 🟢 What I Can Test Right Now (No Action Needed)

These I will test autonomously — real API calls against rt19:

| # | SoW Item | Test Method |
|---|----------|-------------|
| 1 | Agent Registry (CRUD) | Register real agents via API, verify in DB |
| 2 | Egress Policy Enforcement | Create block/allow rules, verify enforcement |
| 3 | Kill Switch (all 3 levels) | Activate/suspend/terminate, measure latency |
| 4 | Audit Chain (Merkle) | Verify SHA-256 chain integrity via `/audit/verify` |
| 5 | Compliance Frameworks | Verify SOC2/GDPR/EU AI Act auto-provisioned |
| 6 | Evidence Export | Generate and download evidence bundles |
| 7 | MCP Gateway Health | Verify 6-layer pipeline |
| 8 | Access Reviews | Create campaigns, verify lifecycle |
| 9 | Dashboard Stats | Verify all dashboard metrics populate |
| 10 | Monitoring Health | Verify service health matrix |
| 11 | Manual Agent Ingest | Ingest agents from external sources via API |
| 12 | Tool Inventory | Register/list tools |
| 13 | Agent Lifecycle (Register→Block→Ignore) | Status transitions via PATCH |
| 14 | Discovery Settings (active/passive mode) | Toggle and verify |
| 15 | Shadow AI Inbox | Ingest + triage unregistered agents |

---

## 🟡 What I Need From You

### 1. GitHub PAT (for real GitHub scanner)
The GitHub scanner scans actual repos for AI agent code patterns.
```
Provide: GitHub Personal Access Token with `repo` scope
I will:  Scan a real repo (yours or a test org), discover AI agents in code
```

### 2. Cloud Credentials (for real AWS/Azure/GCP scanners)
The cloud scanners discover AI/ML workloads in cloud environments.
```
Provide one or more of:
  - AWS:   AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY + AWS_REGION
  - Azure: AZURE_TENANT_ID + AZURE_CLIENT_ID + AZURE_CLIENT_SECRET (read-only SP)
  - GCP:   GOOGLE_CLOUD_PROJECT + service account JSON

I will:  Discover Bedrock models, Azure OpenAI deployments, Vertex AI endpoints
         Store all creds in vault (never in code/env)
```

### 3. Do You Have Ollama or Any Local LLM Running?
The process scanner detects real AI processes on machines.
```
If yes: I can run the process scanner against this Mac Mini for real
        detection of ollama, lm-studio, etc.
If no:  I'll install ollama briefly for a real test, then remove
```

### 4. IdP Connector Test (for real OAuth scanner)
The OAuth scanner discovers OAuth grants across IdPs.
```
Provide one of:
  - Okta:     OKTA_ORG_URL + OKTA_API_TOKEN (read-only)
  - Azure AD: MS Graph app with Application.Read.All permission
  - Google:   Admin SDK credentials

I will:  Discover real OAuth apps, service principals, shadow AI apps
```

### 5. VS Code Extensions Dir Access
```
Provide: Is VS Code installed on this Mac Mini? (likely yes)
I will:  Run the real VSCode scanner against ~/.vscode/extensions/
         Discover actual AI extensions (Copilot, Codeium, etc.)
```

### 6. Network Logs for Shadow AI Detection
```
Provide one of:
  - DNS query logs (from Pi-hole, pfSense, or CloudFlare)
  - Browser proxy logs
  - Or just confirm: can I capture 60s of real DNS traffic with `tcpdump`?

I will:  Feed real network data through the network scanner
         Detect actual shadow AI traffic patterns
```

### 7. eSign Real Document Test
```
Provide: A sample PDF document (non-sensitive) to send for signing
I will:  Create a real signing request, complete the full lifecycle
         (upload → send → sign → verify → audit trail)
```

### 8. SendGrid Email (already configured?)
```
Confirm: Is SendGrid configured and working on rt19?
I will:  Test real email notifications for eSign, magic links, etc.
```

---

## 🔴 Schema Fixes Needed First

Before real testing can proceed, these DB issues must be fixed (found during initial testing):

| Issue | Impact | Fix |
|-------|--------|-----|
| `discovery_findings.severity` CHECK (lowercase only) | Network + Advanced scanners fail | Update app.py to send lowercase OR relax constraint |
| `discovery_scans` missing columns | ✅ FIXED (scanner_id, items_found, metadata) | Already applied |
| `discovery_findings` missing columns | ✅ FIXED (scan_id, agent_id) | Already applied |
| Discovery service has NO `API_KEY_SECRET` env var | Security gap — using `dev-secret-key` default | Deploy proper secret from vault |

---

## Priority Order for Testing

Once you provide items above, I'll test in this order:

1. **Fix severity bug** → Network + Advanced scanners work → all 8 internal scanners pass
2. **VS Code scanner** (if VS Code installed) → immediate
3. **GitHub scanner** (if PAT provided) → real repo scan
4. **Process scanner** (if ollama available) → real process detection
5. **Cloud scanners** (if creds provided) → real AWS/Azure/GCP discovery
6. **OAuth scanner** (if IdP creds provided) → real OAuth app discovery
7. **eSign lifecycle** → real document signing
8. **AI Firewall DLP** → real PII detection (SSN, credit cards)
9. **Kill Switch latency** → sub-100ms measurement

All results saved to `testing_output/discovery_scanners/` with methodology, API calls, and DB validation.

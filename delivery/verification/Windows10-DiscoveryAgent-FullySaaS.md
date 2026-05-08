# Windows 10 Discovery Agent — Fully SaaS Deployment Guide

> **Version**: 2.0.0
> **Last Updated**: 2026-04-10
> **Target Environment**: RuntimeAI Fully SaaS (enforcer.rt19.runtimeai.io)
> **Minimum Requirements**: Windows 10 Home/Pro/Enterprise 21H2+ (including 24H2), PowerShell 5.1+

---

## Overview

The RuntimeAI Discovery Agent scans Windows 10 endpoints for AI tools, shadow AI, MCP servers, and unauthorized model usage. In a **Fully SaaS** deployment, no local infrastructure is required — the agent communicates directly with the RuntimeAI cloud control plane via `api.rt19.runtimeai.io`.

### What Gets Scanned (9 Categories)

| # | Category | Examples |
|---|---|---|
| 1 | **AI Processes** | Ollama, LM Studio, Cursor, Windsurf, Claude Code, vLLM, ComfyUI, **Perplexity Comet**, ChatGPT |
| 2 | **IDE Extensions** | Copilot, Codeium, Tabnine, Continue, Amazon Q, Cody, Gemini Code Assist |
| 3 | **Shadow AI DNS** | api.openai.com, api.anthropic.com, api.groq.com, api.deepseek.com, **comet.perplexity.ai**, chatgpt.com (24 domains) |
| 4 | **Docker Containers** | ollama, vllm, triton, jupyter, open-webui, langfuse, dify |
| 5 | **Python Packages** | openai, anthropic, langchain, transformers, crewai, litellm, mcp (35+ packages) |
| 6 | **MCP Configs** | Claude Desktop, Cursor, Windsurf, Cline, Continue config files |
| 7 | **MCP Packages** | @modelcontextprotocol/server-*, mcp-server-*, @anthropic/* |
| 8 | **Windows Services** | AI-related Windows services (ollama, triton, mlflow, runtimeai) |
| 9 | **npm AI Packages** | openai, anthropic, langchain, @ai-sdk globally installed packages |

---

## Prerequisites

1. **Windows 10** (version 21H2 or later, **including Home 24H2**) or Windows 11
   - ✅ Works on Windows 10 Home — no Pro/Enterprise-only features used
   - All cmdlets (Get-Process, Get-Service, Resolve-DnsName) available on all editions
2. **PowerShell 5.1+** (built into Windows 10)
3. **Internet access** to `api.rt19.runtimeai.io` (port 443)
4. **Tenant credentials** (obtained from RuntimeAI dashboard):
   - Tenant ID
   - API Key (from Settings → API Keys)

### Optional (for broader scanning)
- Docker Desktop installed (uses WSL2 backend on Home edition — for container scanning)
- Python 3.x installed (for Python package scanning)
- Node.js / npm installed (for MCP package scanning)

---

## Installation Methods

### Method 1: One-Liner (Recommended)

Open **PowerShell** (Run as Administrator for service scanning):

```powershell
# Step 1: Set credentials
$env:TENANT_ID = "your-tenant-id"
$env:API_URL = "https://api.rt19.runtimeai.io"
$env:API_KEY = "your-api-key"

# Step 2: Run discovery agent (downloads and executes automatically)
irm "$env:API_URL/api/discovery/client_agents/scanner_windows.ps1" | iex
```

### Method 2: Download and Run

```powershell
# Step 1: Set credentials
$env:TENANT_ID = "your-tenant-id"
$env:API_URL = "https://api.rt19.runtimeai.io"
$env:API_KEY = "your-api-key"

# Step 2: Download the agent
Invoke-WebRequest -Uri "$env:API_URL/api/discovery/client_agents/scanner_windows.ps1" `
    -OutFile "$env:TEMP\runtimeai_scanner.ps1"

# Step 3: Review the script (optional, recommended for compliance)
notepad "$env:TEMP\runtimeai_scanner.ps1"

# Step 4: Run
& "$env:TEMP\runtimeai_scanner.ps1"
```

### Method 3: Python Agent (Cross-Platform Alternative)

If PowerShell execution is restricted, use the Python agent:

```powershell
# Step 1: Set credentials
$env:TENANT_ID = "your-tenant-id"
$env:API_URL = "https://api.rt19.runtimeai.io"
$env:API_KEY = "your-api-key"

# Step 2: Download and run Python agent
python -c "import urllib.request; urllib.request.urlretrieve('$env:API_URL/api/discovery/client_agents/python_endpoint_agent.py', 'agent.py')"
python agent.py
```

---

## Execution Policy

If you encounter an execution policy error, you have two options:

### Option A: Bypass for single run
```powershell
powershell -ExecutionPolicy Bypass -File "$env:TEMP\runtimeai_scanner.ps1"
```

### Option B: Set policy (requires admin)
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Expected Output

```
🔍 RuntimeAI Discovery Agent v2.0.0
   Tenant:   feltsense
   Endpoint: DESKTOP-A1B2C3D
   Time:     2026-04-10T14:30:00Z

📡 [1/9] Scanning running processes...
   ⚠️  Found: ollama (PID 12345)
   ⚠️  Found: cursor (PID 23456)
📦 [2/9] Scanning IDE extensions...
   ⚠️  Found vscode ext: github.copilot
   ⚠️  Found cursor ext: continue.continue
🌐 [3/9] Checking Shadow AI DNS reachability...
   ℹ️  Reachable: api.openai.com
   ℹ️  Reachable: api.anthropic.com
   ℹ️  Reachable: api.groq.com
🐳 [4/9] Scanning Docker containers...
   ⚠️  Found container: ollama
🐍 [5/9] Scanning Python packages...
   ⚠️  Found: openai (1.52.0)
   ⚠️  Found: langchain (0.3.15)
🔌 [6/9] Scanning MCP configuration files...
   ⚠️  Found MCP config: claude_desktop (C:\Users\...\Claude\claude_desktop_config.json)
      → MCP server: filesystem (npx @modelcontextprotocol/server-filesystem)
      → MCP server: brave-search (npx @modelcontextprotocol/server-brave-search)
🔌 [7/9] Scanning for MCP server processes and npm packages...
   ⚠️  Found npm MCP pkg: @modelcontextprotocol/server-github (1.2.0)
🖥️  [8/9] Scanning Windows services...
📦 [9/9] Scanning npm global AI packages...
   ⚠️  Found npm AI pkg: openai

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Total findings: 12

📤 Submitting findings to RuntimeAI...
✅ Scan complete — 12 findings submitted to RuntimeAI platform
```

---

## Viewing Results in the Dashboard

1. Navigate to `https://app.rt19.runtimeai.io`
2. Log in with your tenant credentials
3. Go to **Discovery → Shadow AI Inbox**
4. Findings from the endpoint scan appear with:
   - Category tags (process, ide_extension, shadow_ai_dns, mcp_config, etc.)
   - Severity levels (info, low, medium)
   - Hostname identification
   - Triage actions (Register, Dismiss, Block)

---

## Scheduling Recurring Scans

### Windows Task Scheduler

```powershell
# Create a daily scan at 2:00 AM
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -Command `"& { `$env:TENANT_ID='your-tenant-id'; `$env:API_URL='https://api.rt19.runtimeai.io'; `$env:API_KEY='your-api-key'; irm `$env:API_URL/api/discovery/client_agents/scanner_windows.ps1 | iex }`""

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask `
    -TaskName "RuntimeAI-DiscoveryAgent" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -Description "RuntimeAI endpoint discovery agent - daily AI tool scan"
```

### Verify scheduled task
```powershell
Get-ScheduledTask -TaskName "RuntimeAI-DiscoveryAgent"
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| `Set TENANT_ID env var` error | Ensure `$env:TENANT_ID` is set before running |
| `Set API_URL env var` error | Ensure `$env:API_URL = "https://api.rt19.runtimeai.io"` |
| `Invoke-RestMethod` timeout | Verify internet access to `api.rt19.runtimeai.io:443` |
| `401 Unauthorized` | Verify API key is correct and active in dashboard |
| Execution policy error | Use `powershell -ExecutionPolicy Bypass` |
| No findings detected | Script runs correctly but no AI tools installed on this endpoint |
| Partial results (Docker skipped) | Docker Desktop not installed or not running |
| Partial results (Python skipped) | Python/pip not on PATH |

---

## Security Considerations

| Aspect | Detail |
|---|---|
| **Data transmitted** | Findings only (tool names, PIDs, versions). No file content or model data. |
| **Authentication** | API key sent via `X-API-Key` header over TLS |
| **Endpoint** | `POST /api/discovery/endpoint-scan` on `api.rt19.runtimeai.io` |
| **Privileges** | Runs without admin. Admin recommended for Windows service scanning. |
| **Local fallback** | If submission fails, findings saved to `%TEMP%\runtimeai_scan_*.json` |
| **No persistent agent** | Script runs once and exits. No background process installed. |
| **Network** | HTTPS only (port 443). No outbound connections besides the CP API. |

---

## Architecture

```
┌─────────────────────┐     HTTPS/443     ┌──────────────────────────┐
│  Windows 10 Laptop  │ ───────────────→  │  api.rt19.runtimeai.io   │
│                     │                    │  (Control Plane API)     │
│  scanner_windows.ps1│  POST /api/       │                          │
│  (PowerShell 5.1+)  │  discovery/       │  → discovery_findings    │
│                     │  endpoint-scan    │  → discovered_agents     │
│  Scans:             │                    │  → scan_runs             │
│  - Processes        │  ←────────────── │                          │
│  - IDE extensions   │  202 Accepted     │  Dashboard shows results │
│  - DNS reachability │                    │  in Shadow AI Inbox      │
│  - Docker           │                    └──────────────────────────┘
│  - Python packages  │
│  - MCP configs      │
│  - MCP npm packages │
│  - Windows services │
│  - npm AI packages  │
└─────────────────────┘
```

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 2.0.0 | 2026-04-10 | Added MCP scanning (configs, servers, npm), expanded to 9 categories, 80+ patterns |
| 1.0.0 | 2026-03-15 | Initial release with 5 categories |

---

## Full End-to-End Flow — What Works on a Windows 10 Laptop

After the discovery agent runs and submits findings, the full **Discover → Register → Configure → Enforce → Audit** chain can be tested entirely from a single Windows 10 laptop against the RuntimeAI SaaS platform.

### Flow Overview

```
Windows 10 Laptop (Comet + Perplexity + Copilot installed)
         │
    ┌────┴────┐
    │ Step 1  │  Run discovery agent
    │ PS1/Py  │  → Finds Comet, Perplexity, Copilot, MCP configs
    └────┬────┘
         │ POST /api/discovery/endpoint-scan
         ▼
    ┌─────────┐
    │ Step 2  │  Dashboard → Shadow AI Inbox → Triage
    │ Browser │  → Register "comet-desktop" as a known agent
    └────┬────┘
         │
    ┌────┴────┐
    │ Step 3  │  Dashboard → LLM Providers → Add vendor config
    │ Browser │  e.g., OpenAI with allowed_models: ["gpt-4o-mini"]
    │         │       blocked_models: ["gpt-4", "gpt-4-turbo"]
    └────┬────┘
         │
    ┌────┴────┐
    │ Step 4  │  Dashboard → LLM Providers → Issue proxy key
    │ Browser │  Returns: rtai-pk-abc123... (shown once, bcrypt-hashed)
    └────┬────┘
         │
    ┌────┴────┐
    │ Step 5  │  Test from PowerShell — allowed model
    │ PS/curl │  ✅ 200 OK — proxied through enforcer to OpenAI
    └────┬────┘
         │
    ┌────┴────┐
    │ Step 6  │  Test from PowerShell — blocked model
    │ PS/curl │  ❌ 403 Forbidden — model denied by policy
    └────┬────┘
         │
    ┌────┴────┐
    │ Step 7  │  Dashboard → Audit → view all proxy logs
    │ Browser │  → Every request logged with tenant, agent, model, decision
    └─────────┘
```

### Step-by-Step Test Guide

#### Step 1: Run Discovery Agent

```powershell
$env:TENANT_ID = "feltsense"
$env:API_URL = "https://api.rt19.runtimeai.io"
$env:API_KEY = "your-api-key"
irm "$env:API_URL/api/discovery/client_agents/scanner_windows.ps1" | iex
```

Expected: Finds Comet, Perplexity, Copilot, any MCP configs

#### Step 2: Triage in Shadow AI Inbox

1. Open `https://app.rt19.runtimeai.io`
2. Navigate to **Discovery → Shadow AI Inbox**
3. Find the endpoint scan results from Step 1
4. Click **Register** on the discovered AI agent (e.g., "comet-desktop")
5. Set status to **REGISTERED** with a sponsor

#### Step 3: Configure LLM Provider

1. Navigate to **LLM Providers** (`/llm-providers`)
2. Click **Add Provider**
3. Fill in:
   - **Vendor**: `openai`
   - **Alias**: `openai` (becomes the proxy path: `enforcer.rt19.runtimeai.io/openai/...`)
   - **API Key**: Your OpenAI API key (stored in Vault, never in plaintext)
   - **Allowed Models**: `gpt-4o-mini, gpt-4o`
   - **Blocked Models**: `gpt-4, gpt-4-turbo, o1-preview`

The API stores this in `tenant_vendor_configs` with the key securely in Vault at path `runtimeai/{tenant_id}/openai/default`.

#### Step 4: Issue Proxy Key

1. Still on **LLM Providers** page
2. Click **Issue Proxy Key**
3. Fill in:
   - **Agent ID**: `comet-desktop` (the agent registered in Step 2)
   - **Vendor Alias**: `openai`
   - **Allowed Models** (optional): Can further restrict, e.g., `gpt-4o-mini` only
4. Copy the returned key: `rtai-pk-a1b2c3d4e5f6g7h8...`

> ⚠️ The plaintext key is shown **once**. It is bcrypt-hashed in the database and cannot be retrieved again.

#### Step 5: Test Allowed Model (from PowerShell)

```powershell
# ✅ ALLOWED — gpt-4o-mini is in the allowed list
$headers = @{
    "Authorization" = "Bearer rtai-pk-a1b2c3d4e5f6g7h8..."
    "Content-Type"  = "application/json"
}
$body = @{
    model    = "gpt-4o-mini"
    messages = @(
        @{ role = "user"; content = "Hello, what is RuntimeAI?" }
    )
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "https://enforcer.rt19.runtimeai.io/openai/v1/chat/completions" `
    -Method POST -Headers $headers -Body $body
```

**Expected**: 200 OK — response proxied through to OpenAI, audit log recorded.

#### Step 6: Test Blocked Model (from PowerShell)

```powershell
# ❌ BLOCKED — gpt-4 is in the blocked list
$body = @{
    model    = "gpt-4"
    messages = @(
        @{ role = "user"; content = "Hello from a blocked model" }
    )
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "https://enforcer.rt19.runtimeai.io/openai/v1/chat/completions" `
    -Method POST -Headers $headers -Body $body
```

**Expected**: 403 Forbidden — `{"error": "guardrail_denied", "message": "model gpt-4 is blocked by policy", "rule": "model_blocklist"}`

#### Step 7: Verify Audit Trail

1. Navigate to **Audit & Activity** (`/audit-activity`) in the dashboard
2. Filter by agent ID `comet-desktop`
3. Verify both requests appear:
   - ✅ `ALLOWED` entry for `gpt-4o-mini`
   - ❌ `DENIED` entry for `gpt-4`

---

### Enforcement Layers

The proxy enforces model restrictions at **3 independent layers**:

| Layer | Where | What It Checks |
|---|---|---|
| **1. Vendor Config** | `tenant_vendor_configs` table → OPA bundle | `allowed_models[]` / `blocked_models[]` per vendor alias |
| **2. Proxy Key** | `proxy_keys` table → CP validate API | Per-key model restrictions (can further restrict vendor-level config) |
| **3. OPA Guardrails** | vendor-wrapper → OPA `/v1/data/guardrails/deny` | Model + prompt content rules (PII detection, prompt injection, etc.) |

Each layer is fail-closed in production: if OPA is unreachable, requests are denied (503).

---

### Additional Tests from the Windows Laptop

| Test | How | What It Proves |
|---|---|---|
| **Kill Switch** | Dashboard → Kill Switch → Block agent | Agent gets 403 on ALL requests regardless of model |
| **PII Guardrail** | Send `{"model":"gpt-4o-mini","messages":[{"role":"user","content":"My SSN is 123-45-6789"}]}` | Request denied by PII guardrail rule |
| **Egress Policy** | Dashboard → Egress → Block `api.openai.com` | Even with valid proxy key, traffic to OpenAI is blocked at the egress layer |
| **Revoke Proxy Key** | Dashboard → LLM Providers → Revoke key | Previously working key returns 401 |
| **Budget Enforcement** | Dashboard → Budget → Set $5 daily limit | Requests denied once daily cost threshold is exceeded |
| **Entitlement Check** | Dashboard → Entitlements → Remove `vendor:openai` | Agent loses access to OpenAI vendor, gets 403 `no_entitlement` |
| **MCP Discovery** | Run scan on laptop with Claude Desktop + MCP servers | Dashboard shows MCP config files, server names, and tools |

---

### Required Services (Deployed on rt19)

The end-to-end proxy flow requires these services running on the `rt19` cluster:

| Service | Role | Endpoint |
|---|---|---|
| **Control Plane** | API + vendor config CRUD + proxy key management | `api.rt19.runtimeai.io` |
| **Vendor Wrapper** | Reverse proxy with middleware chain | `enforcer.rt19.runtimeai.io` |
| **OPA** | Policy engine (guardrails, entitlements) | Internal: `opa:8181` |
| **Vault Broker** | API key storage/retrieval | Internal: `vault-broker:8082` |
| **Bundle Cache** | Pushes OPA bundles from CP config | Internal: `bundle-cache:8084` |
| **Dashboard** | Tenant admin UI | `app.rt19.runtimeai.io` |

All services are deployed and operational. No additional infrastructure needed on the client laptop.

---

### Middleware Chain (Request Path)

When a request hits `enforcer.rt19.runtimeai.io/openai/v1/chat/completions`:

```
1. Proxy Key Validation   → CP /api/proxy-keys/validate (bcrypt compare)
2. Agent Block Check       → CP /api/vendor-config/agent-check (BLOCKED status?)
3. Entitlement Check       → OPA /v1/data/runtimeai/agents/{tenant}/{agent}/permissions
4. Egress Policy           → CP /api/policies/egress/check (destination allowlist)
5. Guardrail Deny Rules    → OPA /v1/data/guardrails/deny (model + content check)
6. Key Injection           → Vault Broker retrieves real API key
7. Upstream Proxy          → Forward to api.openai.com with real key
8. Response PII Scan       → Async: check response for SSN/email/CC patterns
9. Audit Log               → CP /api/vendor-proxy-log (full request metadata logged)
```

Each step is fail-closed in production. The entire chain completes in <200ms for allowed requests.


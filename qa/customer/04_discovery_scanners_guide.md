# 04 — AI Discovery & Scanner Setup Guide

**Product**: AI Discovery
**Audience**: Customer Security / DevOps Engineer
**API Base**: `https://api.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is AI Discovery?

AI Discovery finds every AI agent in your environment — including shadow AI that nobody sanctioned. It runs 5 categories of scanners and feeds findings into the governance pipeline.

---

## The 5 Scanner Categories

| # | Scanner | What It Finds | Where It Runs |
|---|---------|---------------|---------------|
| 1 | **Cloud Scanner** | AWS Lambda/Bedrock, Azure AI Studio/Functions, GCP Vertex AI, K8s ML pods | API-based (cloud credentials) |
| 2 | **IDE Scanner** | VS Code Copilot, Cursor, JetBrains AI, Windsurf, CLI tools | Endpoint agent |
| 3 | **Endpoint Scanner** | Ollama, LangServe, local LLMs, network traffic | Endpoint agent |
| 4 | **Automation Scanner** | GitHub Actions bots, CI/CD AI steps, Lambda functions | API-based |
| 5 | **AI Assistant Scanner** | ChatGPT Desktop, Claude Desktop, local LLM apps | Endpoint agent |

---

## Setting Up Each Scanner on rt19

### Scanner 1: Cloud Scanner (AWS)

Scans your AWS account for AI/ML services.

#### Via Dashboard
1. Navigate to **Discovery** → **Scanner Config**
2. Click **Add Scanner** → **Cloud Scanner**
3. Select provider: **AWS**
4. Enter:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Regions to scan: `us-east-1, us-west-2`
   - Services to scan: `lambda, bedrock, sagemaker`
5. Set schedule: Every 6 hours
6. Click **Save & Run**

#### Via API

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Configure AWS cloud scanner
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-aws-scanner",
    "type": "cloud",
    "provider": "aws",
    "config": {
      "access_key_id": "AKIA...",
      "secret_access_key": "...",
      "regions": ["us-east-1", "us-west-2"],
      "services": ["lambda", "bedrock", "sagemaker"],
      "scan_interval_hours": 6
    },
    "enabled": true
  }'
```

### Scanner 2: Cloud Scanner (Azure)

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-azure-scanner",
    "type": "cloud",
    "provider": "azure",
    "config": {
      "tenant_id": "<azure_ad_tenant_id>",
      "client_id": "<service_principal_id>",
      "client_secret": "<service_principal_secret>",
      "subscription_ids": ["sub-1", "sub-2"],
      "services": ["cognitive-services", "openai", "ml-workspace", "functions"],
      "scan_interval_hours": 6
    },
    "enabled": true
  }'
```

### Scanner 3: Cloud Scanner (GCP)

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-gcp-scanner",
    "type": "cloud",
    "provider": "gcp",
    "config": {
      "project_ids": ["acme-prod", "acme-ml"],
      "service_account_key": "<base64_encoded_key>",
      "services": ["vertex-ai", "cloud-functions", "cloud-run"],
      "scan_interval_hours": 6
    },
    "enabled": true
  }'
```

### Scanner 4: IDE Scanner

Detects AI coding assistants on developer workstations.

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-ide-scanner",
    "type": "ide",
    "config": {
      "targets": ["vscode-copilot", "cursor", "jetbrains-ai", "windsurf", "cline", "claude-code"],
      "scan_method": "process_detection",
      "detect_mcp_connections": true,
      "scan_interval_hours": 12
    },
    "enabled": true
  }'
```

### Scanner 5: Endpoint Scanner

Finds AI services running on servers, laptops, Docker hosts.

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-endpoint-scanner",
    "type": "endpoint",
    "config": {
      "targets": ["ollama", "langserve", "llama-cpp", "text-generation-webui", "localai"],
      "network_scan": true,
      "port_ranges": ["8000-8100", "11434"],
      "subnets": ["10.0.0.0/16"],
      "scan_interval_hours": 24
    },
    "enabled": true
  }'
```

### Scanner 6: Automation Scanner

Detects AI in CI/CD pipelines and automation.

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-automation-scanner",
    "type": "automation",
    "config": {
      "github_token": "ghp_...",
      "github_org": "acme-corp",
      "scan_actions": true,
      "scan_workflows": true,
      "detect_ai_steps": true,
      "scan_interval_hours": 24
    },
    "enabled": true
  }'
```

### Scanner 7: AI Assistant Scanner

Detects desktop AI apps (ChatGPT, Claude, etc.).

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acme-assistant-scanner",
    "type": "assistant",
    "config": {
      "targets": ["chatgpt-desktop", "claude-desktop", "perplexity", "copilot-app"],
      "detect_browser_extensions": true,
      "scan_interval_hours": 24
    },
    "enabled": true
  }'
```

---

## Running a Scan

### Trigger Immediate Scan

```bash
# Trigger a scan for a specific scanner
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scanners/<scanner_id>/run"

# Trigger all scanners
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/scan-all"
```

### View Scan Results

```bash
# List all findings
curl -sf -b "$COOKIE" "$API/api/discovery/findings" | jq '.findings[] | {name, type, risk_score, status}'

# Filter by scanner type
curl -sf -b "$COOKIE" "$API/api/discovery/findings?type=cloud" | jq .

# Shadow AI findings only
curl -sf -b "$COOKIE" "$API/api/discovery/findings?status=shadow" | jq .
```

### Triage Shadow AI

When a scanner finds an unsanctioned AI agent, it appears in the Shadow AI Inbox.

#### Via Dashboard
1. Navigate to **Discovery** → **Shadow AI Inbox**
2. For each finding, choose:
   - **Register** — Convert to a governed agent (creates agent in registry)
   - **Approve** — Mark as sanctioned (no action needed)
   - **Block** — Add to firewall block list
   - **Investigate** — Assign to a team member for review

#### Via API

```bash
# Register a shadow AI finding as a governed agent
curl -sf -b "$COOKIE" -X POST "$API/api/discovery/findings/<finding_id>/register" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_name": "prod-summarizer-bot",
    "blueprint_id": "<blueprint_id>",
    "sponsor_email": "alice@acme-corp.com",
    "risk_tier": "limited"
  }'
```

---

## Scanner Dashboard

The Scanner Dashboard shows:

| Metric | Description |
|--------|-------------|
| **Total Findings** | All discovered AI agents/tools |
| **Shadow AI Count** | Unsanctioned agents needing triage |
| **Coverage** | % of environment scanned |
| **Scanner Health** | Last run time, success/failure per scanner |
| **Risk Distribution** | Findings by risk score (0-100) |

---

## Cross-Platform Shadow AI Detection Script

For endpoint scanning on macOS (common in dev environments):

```bash
#!/bin/bash
# Quick local shadow AI detection (macOS)

echo "=== Shadow AI Detection ==="

# Check for AI coding assistants
for app in "Cursor" "Copilot" "Claude" "ChatGPT" "Windsurf"; do
  if pgrep -fi "$app" > /dev/null 2>&1; then
    echo "  ⚠️  FOUND: $app is running"
  fi
done

# Check for local LLM servers
for port in 11434 8000 8080 5000; do
  if curl -s "http://localhost:$port" > /dev/null 2>&1; then
    echo "  ⚠️  FOUND: Service on port $port"
  fi
done

# Check for Ollama
if command -v ollama &> /dev/null; then
  echo "  ⚠️  FOUND: Ollama installed"
  ollama list 2>/dev/null | while read line; do
    echo "    → Model: $line"
  done
fi

# Check for MCP servers
if [ -f "$HOME/.config/claude/claude_desktop_config.json" ]; then
  echo "  ⚠️  FOUND: Claude Desktop MCP config"
fi
if [ -f "$HOME/.cursor/mcp.json" ]; then
  echo "  ⚠️  FOUND: Cursor MCP config"
fi
```

---

## FAQ

**Q: Do scanners need to run inside my network?**
A: Cloud scanners are API-based and run from the control plane. IDE, endpoint, and assistant scanners need an agent deployed inside your network (or run the script above on individual machines).

**Q: How do I avoid false positives?**
A: Configure exclusion lists per scanner. For example, exclude your sanctioned AI tools from the assistant scanner so they don't appear as shadow AI.

**Q: What credentials do cloud scanners need?**
A: Read-only API access. For AWS: `ReadOnlyAccess` policy. For Azure: `Reader` role on subscriptions. For GCP: `roles/viewer`.

**Q: How often should scanners run?**
A: Cloud scanners: every 6 hours. IDE/endpoint: every 12-24 hours. Automation: every 24 hours. Balance thoroughness with API rate limits.

**Q: Can I scan Kubernetes clusters?**
A: Yes. The cloud scanner detects K8s pods with ML-related labels, images from AI registries (e.g., `huggingface/`, `ollama/`), and GPU resource requests.

**Q: What happens to discovered agents after triage?**
A: Registered agents appear in the Agent Registry with a trust score of 50. Blocked agents are added to the firewall. Approved agents are marked as sanctioned.

### Advanced Setup Questions

**Q: Can I integrate Discovery findings with my SIEM?**
A: Yes. Configure SIEM integration under **Settings** → **Integrations** → **SIEM**. Findings are exported as structured events to Splunk, Sentinel, or QRadar.

**Q: How does fingerprinting prevent duplicate findings?**
A: Each finding is fingerprinted using a hash of (scanner_type + source_id + agent_identifier). Duplicate scans update the existing finding instead of creating new ones.

**Q: Can I write custom scanner plugins?**
A: Not yet. Custom scanners are on the roadmap. Currently, you can use the Endpoint Scanner with custom port ranges and process names to approximate custom scanning. See [gaps_issues.md](gaps_issues.md).

**Q: How do I scan air-gapped environments?**
A: Deploy the discovery service locally and configure it to report back to the control plane via outbound HTTPS. For fully air-gapped: export findings as JSON and import via API.

**Q: Can Discovery detect AI agents that communicate only via internal APIs?**
A: The endpoint scanner detects processes and open ports. For internal API-only agents, use the automation scanner to scan your service mesh/registry, or manually register known agents.

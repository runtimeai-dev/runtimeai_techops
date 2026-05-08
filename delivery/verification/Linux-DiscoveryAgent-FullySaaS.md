# Linux Discovery Agent — Fully SaaS Deployment Guide

> **Version**: 1.0.0
> **Last Updated**: 2026-04-16
> **Target Environment**: RuntimeAI Fully SaaS (api.rt19.runtimeai.io)
> **Minimum Requirements**: Ubuntu 20.04+ / RHEL 8+ / Debian 11+, Python 3.8+, curl

---

## Overview

The RuntimeAI Discovery Agent scans Linux endpoints for AI tools, shadow AI, MCP servers, Docker-hosted models, and unauthorized LLM API usage. Results are reported to the RuntimeAI cloud control plane.

### What Gets Scanned

| # | Category | Examples |
|---|---|---|
| 1 | AI Processes | ollama, vllm, triton, lm-studio, comfyui, jupyter |
| 2 | Python Packages | openai, anthropic, langchain, transformers, crewai, litellm, mcp |
| 3 | Shadow AI DNS | api.openai.com, api.anthropic.com + 22 more domains |
| 4 | Docker Containers | ollama, vllm, triton, open-webui, langfuse, dify |
| 5 | MCP Configs | Claude Desktop, Cursor, Windsurf config paths |
| 6 | Systemd Services | ollama, triton, mlflow, runtimeai services |
| 7 | npm AI Packages | openai, anthropic, langchain globally installed |

---

## Prerequisites

1. **Linux**: Ubuntu 20.04+, Debian 11+, RHEL 8+, Amazon Linux 2023, or Alpine 3.16+
2. **Python 3.8+** with pip
3. **Internet access** to `api.rt19.runtimeai.io` (port 443)
4. **Tenant credentials**: Tenant ID + API Key (from Dashboard → Settings → API Keys)

---

## Installation

### Method 1: One-Line Install (Recommended)

```bash
curl -sSL https://api.rt19.runtimeai.io/api/discovery/client_agents/linux_installer.sh | \
  TENANT_ID=<your-tenant-id> API_KEY=<your-api-key> bash
```

### Method 2: Manual Install

```bash
# 1. Download scanner
mkdir -p /opt/runtimeai/scanner
curl -sSL https://api.rt19.runtimeai.io/api/discovery/client_agents/linux_scanner.py \
  -o /opt/runtimeai/scanner/scan.py

# 2. Install Python dependencies
pip3 install requests psutil

# 3. Set environment
export RUNTIMEAI_TENANT_ID=<your-tenant-id>
export RUNTIMEAI_API_KEY=<your-api-key>
export RUNTIMEAI_API_URL=https://api.rt19.runtimeai.io

# 4. Run scan
python3 /opt/runtimeai/scanner/scan.py
```

---

## Expected Output

```
[RuntimeAI Scanner] Starting Linux endpoint scan...
[RuntimeAI Scanner] Scanning processes... found 3 AI processes
[RuntimeAI Scanner] Scanning Python packages... found 8 AI packages
[RuntimeAI Scanner] Checking DNS (shadow AI)... found 2 active domains
[RuntimeAI Scanner] Scanning Docker containers... found 1 AI container
[RuntimeAI Scanner] Reporting 14 findings to api.rt19.runtimeai.io...
[RuntimeAI Scanner] ✅ Scan complete. Results visible in Dashboard → Discovery → Shadow AI Inbox
```

---

## Dashboard Verification

1. Log into `https://app.rt19.runtimeai.io`
2. Navigate to **Discovery → Shadow AI Inbox**
3. Verify findings from this endpoint appear with `source: endpoint_scanner`
4. Check **Discovery → Scan History** for the scan run entry

---

## Scheduling Recurring Scans

### Using cron (recommended)

```bash
# Run daily at 2 AM
echo "0 2 * * * root RUNTIMEAI_TENANT_ID=<id> RUNTIMEAI_API_KEY=<key> RUNTIMEAI_API_URL=https://api.rt19.runtimeai.io python3 /opt/runtimeai/scanner/scan.py >> /var/log/runtimeai-scan.log 2>&1" \
  | sudo tee /etc/cron.d/runtimeai-scanner
```

### Using systemd timer

```bash
# Create service
sudo tee /etc/systemd/system/runtimeai-scan.service <<EOF
[Unit]
Description=RuntimeAI Discovery Scan
[Service]
Type=oneshot
Environment=RUNTIMEAI_TENANT_ID=<id>
Environment=RUNTIMEAI_API_KEY=<key>
Environment=RUNTIMEAI_API_URL=https://api.rt19.runtimeai.io
ExecStart=/usr/bin/python3 /opt/runtimeai/scanner/scan.py
EOF

# Create timer (daily at 2 AM)
sudo tee /etc/systemd/system/runtimeai-scan.timer <<EOF
[Unit]
Description=RuntimeAI Daily Discovery Scan
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now runtimeai-scan.timer
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Connection refused` to API | Verify firewall allows outbound HTTPS to `api.rt19.runtimeai.io` |
| `401 Unauthorized` | Check TENANT_ID and API_KEY are correct |
| No findings reported | Run `python3 scan.py --verbose` to see what was scanned |
| Docker containers not detected | Ensure user has Docker socket access (`sudo usermod -aG docker $USER`) |
| pip packages not found | Scanner checks `/usr/lib/python*/site-packages` and `~/.local/lib/python*` |

---

## Security Considerations

- The scanner runs as the current user — does NOT require root (but root sees more processes)
- API Key is transmitted over TLS only (port 443)
- No data is stored locally — all findings are sent to the control plane
- The scanner binary can be audited: it's a Python script, not compiled

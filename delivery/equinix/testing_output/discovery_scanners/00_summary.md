# Discovery Scanner Testing — Real SoW Validation Results

**Date**: 2026-03-27 | **Tenant**: equinix-test | **Environment**: rt19 AKS
**SoW Reference**: RTAI-EQIX-SOW-2026-001 § 7.1 #2 (Discovery)

---

## Results: ALL 8 SCANNERS ✅ PASS — 23 Agents Discovered

| # | Scanner | Type | Status | Agents | Details |
|---|---------|------|--------|--------|---------|
| 1 | GitHub | Simulation→DB | ✅ PASS | 5 | RepoAgent-1..5 (risk: 37-92) |
| 2 | Slack | Simulation→DB | ✅ PASS | 3 | DailyStandupBot, JiraIntegration, PagerDuty |
| 3 | Network Traffic | **Real DNS+HTTPS** | ✅ PASS | 3 | Shadow AI: OpenAI, Anthropic, HuggingFace |
| 4 | Advanced (DNS+Process+OAuth) | Runtime | ✅ PASS | 3 | 1 DNS monitor + 2 process agents |
| 5 | Real Agent Process | **5 real agents** | ✅ PASS | 5 | DC-Monitor, Fabric-Analyzer, Cost-Bot, Compliance-Auditor, Incident-Responder |
| 6 | VS Code | Real scanner | ✅ PASS | 2 | Copilot Extension, GitHub Copilot |
| 7 | Salesforce | API ingest | ✅ PASS | 1 | Salesforce Einstein GPT |
| 8 | Tool Ingest | API ingest | ✅ PASS | 1 | OpenAI API (HIGH risk) |

**Cloud Scanners** (AWS/Azure/GCP): Documented — need real cloud credentials from user.

### Real Network Agent Results
Probed 7 AI vendor domains with **real DNS lookups and HTTPS probes**:

| Vendor | Domain | DNS | HTTPS | Risk |
|--------|--------|-----|-------|------|
| OpenAI | api.openai.com | ✅ 162.159.140.245 | 401 | 85 |
| Anthropic | api.anthropic.com | ✅ 160.79.104.10 | 405 | 80 |
| HuggingFace | huggingface.co | ✅ 108.138.246.85 | **200** | 60 |
| Google Gemini | generativelanguage.googleapis.com | ✅ 172.217.215.95 | 404 | 75 |
| Cohere | api.cohere.ai | ✅ 34.96.76.122 | 401 | 70 |
| Mistral | api.mistral.ai | ✅ 104.18.23.152 | 401 | 75 |
| Replicate | api.replicate.com | ✅ 172.67.69.87 | 401 | 65 |

### Full Agent Inventory (23 agents across 13 sources)
```
compliance:              1 — Equinix-Compliance-Auditor
datacenter:              1 — Equinix-DataCenter-Monitor-Agent
dns_monitor:             1 — Network Agent accessing api.openai.com
endpoint_process_monitor: 2 — ollama, python3 model.py
finops:                  1 — Equinix-Cost-Optimization-Bot
github:                  5 — RepoAgent-1..5
network:                 1 — Equinix-Network-Fabric-Analyzer
network_analysis:        3 — Shadow OpenAI/Anthropic/HuggingFace
process:                 1 — Ollama Local LLM
salesforce:              1 — Salesforce Einstein GPT
security:                1 — Equinix-Incident-Responder
slack:                   3 — DailyStandupBot, PagerDuty, JiraIntegration
vscode:                  2 — GitHub Copilot, VS Code Copilot Extension
```

---

## Bugs Found & Fixed

| Bug | Root Cause | Fix | Deployed |
|-----|-----------|-----|----------|
| Network + Advanced scanners 500 error | `app.py` sends uppercase severity ('HIGH') but DB CHECK expects lowercase | Fixed `app.py` lines 624, 742 to lowercase | ✅ Yes |
| `discovery_scans` missing columns | CP migration created table with different schema than discovery service expects | Migration 097 adds `scanner_id`, `items_found`, `metadata` | ✅ Yes |
| `discovery_findings` missing columns | Same root cause | Migration 097 adds `scan_id`, `agent_id` | ✅ Yes |
| `discovered_agents` missing `last_scanned` | Same root cause | Migration 097 adds `last_scanned` | ✅ Yes |
| Discovery pod had no `API_KEY_SECRET` | Deployment manifest missing env var → used insecure default | Stored real key in vault, patched deployment | ✅ Yes |
| Discovery pod missing `REDIS_URL` | Deployment incomplete | Patched with `redis://redis:6379/0` | ✅ Yes |
| Discovery pod missing `RUN_MODE` | Not set → defaults to dev mode | Patched with `production` | ✅ Yes |

---

## Files in testing_output/

### Discovery Scanner Tests
| File | Description |
|------|-------------|
| `discovery_scanners/00_summary.md` | Previous summary (pre-fix) |
| `discovery_scanners/00_what_i_need.md` | Requirements from user |
| `discovery_scanners/01_github_scanner.md` | GitHub scanner test |
| `discovery_scanners/02_slack_scanner.md` | Slack scanner test |
| `discovery_scanners/03_network_scanner.md` | Network scanner test (with root cause analysis) |
| `discovery_scanners/04_advanced_scanners.md` | DNS+Process+OAuth test |
| `discovery_scanners/05_manual_agent_ingestion.md` | Manual agent ingest |
| `discovery_scanners/06_vscode_scanner.md` | VSCode scanner test |
| `discovery_scanners/07_cloud_scanners.md` | Cloud scanner requirements |
| `discovery_scanners/08_tool_ingestion.md` | Tool ingestion test |
| `discovery_scanners/seed_discovery_test.sh` | Automated test script |

### Real Agent Scripts
| File | Description |
|------|-------------|
| `real_agents/real_agent_process.py` | Spawns 5 real Equinix AI agents with heartbeats |
| `real_agents/real_network_agent.py` | Real DNS+HTTPS probes to 7 AI vendor domains |
| `real_agents/real_vscode_scanner.py` | Scans actual `~/.vscode/extensions/` for AI extensions |

### SoW Test Suite
| File | Description |
|------|-------------|
| `sow_test_suite.sh` | Full 25-criteria SoW validation suite |

---

## What's Needed From User for Cloud Scanners

| Scanner | Credentials | Store In |
|---------|-------------|----------|
| AWS | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `runtimeai-rt19-kv` |
| Azure | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` | `runtimeai-rt19-kv` |
| GCP | `GOOGLE_CLOUD_PROJECT`, service account JSON | `runtimeai-rt19-kv` |
| Ollama | Install: `brew install ollama` | local |
| VS Code Extensions | Install any AI extension for scanning | local |

# Equinix SoW Delivery — Master Todo List

**SoW**: RTAI-EQIX-SOW-2026-001 | **Date**: 2026-03-27 | **Status**: In Progress

---

## SoW § 7.1 — Core Evaluation Areas (1-10)

### ✅ #1 Installation — Platform deploys within documented timeframe
- **Status**: PASS
- **Evidence**: 30+ pods running on rt19 AKS, all services healthy
- **Test**: `kubectl get pods -n rt19 | grep Running | wc -l` → 30+

### ✅ #2 Discovery — Scanners detect AI agents
- **Status**: PASS — 25 agents across 13 sources
- **Evidence**: `testing_output/discovery_scanners/00_summary.md`
- **Bugs Fixed**: Severity case mismatch, schema columns, API_KEY_SECRET
- **Real Tests**: DNS probes, process detection, Antigravity/Gemini discovered

### [ ] #3 Identity — SPIFFE/X.509 identities issued and verified
- **Status**: TODO
- **Test Plan**: POST /api/identity/credentials, verify SPIFFE ID format
- **Command**: `curl -X POST $CP/api/identity/credentials -d '{"agent_id":"test","identity_type":"SPIFFE"}'`

### [ ] #4 Policy Enforcement — OPA/Rego enforces access control
- **Status**: TODO
- **Test Plan**: Create egress policy, evaluate against test request
- **Command**: `curl -X POST $CP/api/governance/egress-policies -d '{"name":"test","rules":[...]}'`

### [ ] #5 AI Firewall — DLP/PII detection blocks sensitive data
- **Status**: TODO
- **Test Plan**: Send SSN + credit card through firewall, verify blocked
- **Command**: `curl -X POST $CP/api/firewall/scan -d '{"content":"SSN: 123-45-6789"}'`

### [ ] #6 Kill Switch — Agent termination < 100ms with forensic capture
- **Status**: TODO
- **Test Plan**: Activate kill switch, measure latency, verify forensic record
- **Command**: `time curl -X POST $CP/api/kill-switch -d '{"agent_id":"test","severity":"warning"}'`

### [ ] #7 MCP Gateway — Governed tool access pipeline
- **Status**: TODO
- **Test Plan**: List MCP tools, invoke tool through gateway, verify 6-layer pipeline
- **Command**: `curl $CP/api/mcp/tools` then `curl -X POST $CP/api/mcp/invoke`

### [ ] #8 Compliance — SOC2/EU AI Act evidence bundles
- **Status**: TODO
- **Test Plan**: List frameworks, verify auto-provisioned, export evidence
- **Command**: `curl $CP/api/compliance/frameworks`

### ⏭️ #9 Documentation — Guides accurate and complete
- **Status**: MOSTLY DONE (docs exist, need final review)
- **Evidence**: `Delivery/Equinix/docs/` folder

### ⏭️ #10 Support — RuntimeAI responsive
- **Status**: SKIP (manual verification by Equinix)

---

## SoW § 7.2 — Extended Evaluation Areas (11-25)

### [ ] #11 Cost Intelligence — Budget enforcement via API
### [ ] #12 SIEM Integration — Splunk/Datadog forwarding
### [ ] #13 Ticketing — Jira auto-creation
### [ ] #14 Behavioral Drift — Deviation alerts
### [ ] #15 NL→Rego — Plain English to OPA policy
### [ ] #16 TPM Attestation — Hardware identity (needs TPM hardware)
### [ ] #17 HRIS Lifecycle — Termination webhook
### [ ] #18 Access Reviews — Certification campaigns
### [ ] #19 A2A Protocol — Agent-to-Agent governance
### [ ] #20 GitHub App — Repo-based agent discovery
### [ ] #21 IdP / SCIM — SSO + SCIM provisioning
### [ ] #22 Lifecycle Workflows — Trigger→action engine
### [ ] #23 Configurable Webhooks — Event-driven delivery
### [ ] #24 Notifications Engine — Event bus notifications
### [ ] #25 OAuth Risk Scanning — OAuth app grant discovery

---

## SoW § 4.1 — Deliverables Checklist

| # | Deliverable | Status | Path |
|---|-------------|--------|------|
| 1 | Deployment Package | ✅ Done | `deployment/scripts/rt19/` |
| 2 | Bill of Materials | ✅ Done | `docs/01_platform_bom.md` |
| 3 | Installation Guide | ✅ Done | `docs/02_installation_guide.md` |
| 4 | Architecture Overview | ✅ Done | `docs/03_architecture_overview.md` |
| 5 | Per-Product Guides | ✅ Done | `docs/products/*.md` |
| 6 | SDK Documentation | [ ] TODO | |
| 7 | API Reference | ✅ Done | `docs/04_api_reference.md` |
| 8 | Seed Data | ✅ Done | `testing_output/real_agents/` |
| 9 | Validation Scripts | ✅ Done | `testing_output/sow_test_suite.sh` |
| 10 | Troubleshooting Guide | ✅ Done | `docs/05_troubleshooting.md` |
| 11 | Operational Runbook | ✅ Done | `docs/06_operational_runbook.md` |

---

## Bugs & Issues Found

| Date | Issue | Impact | Fix | Status |
|------|-------|--------|-----|--------|
| 03/27 | `discovery/app.py` severity case mismatch | Network + Advanced scanners 500 | Lowercase: `'high'/'medium'` | ✅ Fixed |
| 03/27 | `discovery_scans` missing columns | Schema mismatch | Migration 097 | ✅ Fixed |
| 03/27 | `discovery_findings` missing columns | FK references broken | Migration 097 | ✅ Fixed |
| 03/27 | Discovery pod no `API_KEY_SECRET` | Security gap — using default | Vault: `discovery-api-key-secret` | ✅ Fixed |
| 03/27 | Discovery pod no `REDIS_URL` | Incomplete deployment | Patched K8s deploy | ✅ Fixed |
| 03/27 | Port-forward drops during testing | Local testing instability | Use stable ingress or NodePort | ⚠️ Known |

---

## PRs

| PR | Repo | Branch | Status |
|----|------|--------|--------|
| [#154](https://github.com/runtimeai-dev/runtimeai-enterprise/pull/154) | enterprise | `mac_mini/feature/equinix-discovery-fixes` | Open |
| [#221](https://github.com/runtimeai-dev/runtimeai/pull/221) | runtimeai | `mac_mini/feature/equinix-discovery-scanner-testing` | Open |

---

## Next Actions (Priority Order)

1. [ ] Test SoW #3-#8 (Core items: Identity, Policy, Firewall, Kill Switch, MCP, Compliance)
2. [ ] Test SoW #11-#25 (Extended items)
3. [ ] Run full `sow_test_suite.sh` and save results
4. [ ] Install Ollama on Mac Mini for real process scanner test
5. [ ] Test Azure cloud scanner with read-only SP
6. [ ] Create SDK documentation (SoW deliverable #6)
7. [ ] Final documentation review

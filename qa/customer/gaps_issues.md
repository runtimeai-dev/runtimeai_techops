# Gaps & Issues — Brutally Honest Assessment

**Purpose**: This document identifies every gap, missing implementation, and issue that would prevent a real customer from deploying and using the full RuntimeAI platform on Azure rt19.

**Last Updated**: 2026-03-17
**Severity Scale**: 🔴 Critical (blocks customer) | 🟠 High (major friction) | 🟡 Medium (workaround exists) | 🟢 Low (nice-to-have)

---

## Executive Summary

**RuntimeAI has 12 products. In a real customer deployment, here's the honest state:**

| Product | Deployable? | Fully Functional? | Customer-Ready? |
|---------|:-----------:|:-----------------:|:---------------:|
| Agent Identity Fabric | ✅ | 🟡 Partial | 🟡 |
| AI Discovery | ✅ | 🟡 Partial | 🟡 |
| AI Control Plane | ✅ | 🟡 Partial | 🟡 |
| AI Firewall | 🟡 CP only | ❌ No data plane | ❌ |
| Agent Behavioral Intel | ✅ | 🟡 Partial | 🟡 |
| AI Ops Center | ✅ | 🟡 Partial | 🟡 |
| MCP Gateway | ✅ | 🟡 Partial | 🟡 |
| AI Compliance Hub | ✅ | 🟡 Partial | 🟡 |
| Agent Marketplace | ✅ | 🟡 Partial | 🟡 |
| AI Cost Intelligence | ✅ | 🟡 Partial | 🟡 |
| RuntimeAI Sign | ✅ | 🟡 Partial | 🟡 |
| ML Intelligence | ❌ | ❌ | ❌ |

**Bottom line**: The control plane (API + Dashboard) is deployed and functional for most products. But the **data plane is completely absent** on rt19, which means runtime enforcement (DLP inline, egress blocking, flow enforcement, cost metering) doesn't actually happen. A customer can configure policies, but those policies are not enforced on real AI agent traffic.

---

## 🔴 Critical Gaps (Blocks Customer Deployment)

### GAP-001: No Data Plane on rt19
**Severity**: 🔴 Critical
**Impact**: Customers can configure policies but cannot enforce them on actual agent traffic.

**What's missing**:
- Flow Enforcer (Envoy + Wasm sidecar) — NOT deployed on rt19
- WAF (OpenResty) — NOT deployed on rt19
- Data Proxy (DLP inline scanning) — NOT deployed on rt19
- Cost Ledger (token metering) — NOT deployed on rt19
- Identity DNS (agent identity resolution) — NOT deployed on rt19
- Drift Engine (behavioral analysis) — NOT deployed on rt19

**Why it matters**: Without the data plane, the AI Firewall is a paper firewall. DLP rules exist but aren't enforced inline. Egress rules exist but aren't blocked at the network level. Cost metering requires manual API calls instead of automatic interception.

**What needs to happen**:
1. Build ARM64 images for all data plane services
2. Create K8s manifests for data plane namespace
3. Configure DP → CP communication (outbound HTTPS)
4. Test Flow Enforcer Wasm plugin on ARM64
5. Verify Envoy compatibility with AKS node sizing

**Estimated effort**: 2-3 weeks

---

### GAP-002: SDK & CLI Not Published
**Severity**: 🔴 Critical
**Impact**: Customers cannot install the SDK via npm/pip/go modules. They would need source access.

**What's missing**:
- TypeScript SDK not published to npm (`@runtimeai/sdk`)
- Go SDK not published as a Go module
- Python SDK does not exist
- CLI binary not published (no `brew install`, no binary downloads)
- MCP Server SDK not published to npm (`@runtimeai/mcp-sdk`)

**Why it matters**: A customer cannot integrate their AI agents with RuntimeAI without the SDK. Telling them to clone the repo and build from source is not viable.

**What needs to happen**:
1. Set up npm publishing pipeline for TypeScript SDK
2. Publish Go module to `github.com/runtimeai-dev/runtimeai-sdk`
3. Create Python SDK (wrapper around REST API)
4. Create CI/CD for CLI binary releases (macOS/Linux/Windows)
5. Set up MCP Server SDK npm package

**Estimated effort**: 1-2 weeks

---

### GAP-003: Container Images Not Published to Public Registry
**Severity**: 🔴 Critical
**Impact**: Customers cannot pull RuntimeAI images without access to the private ACR.

**What's missing**:
- GHCR images not published for most services
- No public image registry for customers
- No image versioning/tagging strategy for customer consumption
- No offline/airgap bundle generation automated

**Why it matters**: DSGDemoEnterpriseSaas references GHCR images, but most services are only built and pushed to the private ACR (`runtimeaicr.azurecr.io`). Customers deploying their own data plane need access to images.

**What needs to happen**:
1. Set up GitHub Actions to auto-publish to GHCR on tag
2. Define image naming convention for customers
3. Create PAT-based access for customer GHCR pulls
4. Automate offline bundle creation (`docker save` + `gzip`)

**Estimated effort**: 1 week

---

### GAP-004: No Automated Database Migrations for Customer Deployment
**Severity**: 🔴 Critical
**Impact**: Customers would need to manually run SQL migrations.

**What's missing**:
- No migration runner for customer deployments
- Migrations are embedded in service startup code — but not all services auto-migrate
- No rollback mechanism
- No migration status tracking

**Why it matters**: When a customer upgrades to a new version, they need confidence that database schema changes are applied correctly. Currently, this is a manual process.

**What needs to happen**:
1. Ensure all services auto-migrate on startup (most already do)
2. Add migration version tracking table
3. Document migration rollback procedures
4. Test upgrade path from v1.0 → v1.1

**Estimated effort**: 1 week

---

### GAP-005: No Customer Onboarding Automation
**Severity**: 🔴 Critical
**Impact**: Setting up a new customer requires manual API calls.

**What's missing**:
- No self-service tenant provisioning
- No automated onboarding workflow that creates tenant + admin user + seed data + email welcome
- No Terraform module for customer infrastructure
- The seed script exists but is internal — not customer-facing

**Why it matters**: Every new customer requires a RuntimeAI engineer to manually create their tenant. This doesn't scale.

**What needs to happen**:
1. Build self-service signup flow in the dashboard
2. Automate tenant provisioning with email verification
3. Create Terraform module for customer data plane deployment
4. Build customer-facing onboarding wizard

**Estimated effort**: 2-3 weeks

---

## 🟠 High Severity Gaps

### GAP-006: Discovery Scanners — No Actual Scanning Implementation
**Severity**: 🟠 High
**Impact**: Scanner configs can be created but actual scanning is limited.

**Details**:
- Cloud scanners exist in the Discovery service (Python/FastAPI) but need cloud provider credentials that customers must configure
- IDE and Endpoint scanners require an agent installed on customer machines — **no downloadable agent binary exists**
- Automation scanner (GitHub) requires OAuth app setup — no guided flow
- Network scanning requires privileged access — no clear instructions

**What's missing**:
- Downloadable scanner agent for macOS/Linux/Windows
- Guided cloud provider credential setup wizard
- GitHub OAuth app creation flow
- Actual network scanning binary

**Estimated effort**: 3-4 weeks (this is a big one)

---

### GAP-007: MCP Server Images Not Available for Customer Deployment
**Severity**: 🟠 High
**Impact**: Customers see 490+ integrations in the catalog but can only deploy Okta and PostgreSQL MCP servers.

**Details**:
- The catalog has 490+ entries (seeded by `seed_mcp_integrations.sh`)
- Only 2 MCP servers are actually implemented: `mcp-server-okta` and `mcp-server-postgresql`
- The other 488 are catalog metadata only — no actual server implementation
- Customer clicks "install" and nothing works

**What's missing**:
- Actual MCP server implementations for top integrations (Slack, Jira, GitHub, AWS, Azure, etc.)
- OR: Clear documentation that most integrations are "coming soon"
- OR: Ability for customers to point to community MCP servers

**Estimated effort**: Ongoing — each MCP server is 1-3 days

---

### GAP-008: No Azure Key Vault Integration
**Severity**: 🟠 High
**Impact**: Secrets are stored as base64-encoded K8s Secrets — not enterprise-grade.

**Details**:
- K8s Secrets are base64-encoded, not encrypted at the application layer
- No integration with Azure Key Vault via CSI driver
- Credential rotation requires manual K8s Secret updates
- No HSM backing for cryptographic keys

**What needs to happen**:
1. Add Azure Key Vault CSI driver to AKS
2. Migrate secrets from K8s Secrets to Key Vault
3. Configure SecretProviderClass for each service
4. Document key rotation procedure

**Estimated effort**: 1 week

---

### GAP-009: No SIEM Integration Working End-to-End
**Severity**: 🟠 High
**Impact**: Audit events exist but cannot be forwarded to customer SIEM.

**Details**:
- Audit trail is stored in PostgreSQL
- No webhook push for real-time events
- No Splunk HEC integration
- No Azure Sentinel integration
- No syslog forwarding
- Export is via API polling only

**What needs to happen**:
1. Implement webhook push for audit events
2. Build Splunk HEC connector
3. Build Azure Sentinel connector
4. Add syslog forwarding option

**Estimated effort**: 2 weeks

---

### GAP-010: eSign Service — Azure Blob Storage Not Configured
**Severity**: 🟠 High
**Impact**: Document storage fails without Azure Blob credentials.

**Details**:
- The `rt19-storage-secrets` secret may not be properly configured
- No Azure Storage Account provisioned in Terraform
- Document upload/download will fail silently
- No S3-compatible storage fallback

**What needs to happen**:
1. Provision Azure Storage Account
2. Create container for eSign documents
3. Configure `rt19-storage-secrets` with account + key
4. Test document upload/download end-to-end

**Estimated effort**: 2-3 days

---

### GAP-011: No SSO/OIDC Configured for Customer Auth
**Severity**: 🟠 High
**Impact**: Customers must use magic link or password. No Okta/Azure AD SSO.

**Details**:
- Auth service supports OIDC but it's not configured
- No SAML support
- No SCIM provisioning active
- Enterprise customers expect SSO day one

**What needs to happen**:
1. Document OIDC configuration steps
2. Test with Okta and Azure AD
3. Enable SCIM provisioning endpoint
4. Add SSO configuration to SaaS Admin

**Estimated effort**: 1 week

---

### GAP-012: Dashboard Feature Completeness
**Severity**: 🟠 High
**Impact**: Some dashboard pages may show stubs or incomplete UI.

**Details**:
- Dashboard was built iteratively — some product pages may be incomplete
- Some pages may still have hardcoded data (previous gap from DSGDemo)
- ML Intelligence page likely doesn't exist or is a stub
- Some advanced features (Identity Graph, TPM Attestation) may not have full UI coverage

**What needs to happen**:
1. Audit every dashboard page against the product guide
2. Remove any remaining hardcoded/mock data
3. Build missing ML Intelligence page
4. Verify all CRUD operations work through the UI

**Estimated effort**: 2-3 weeks (dashboard is a lot of pages)

---

## 🟡 Medium Severity Gaps

### GAP-013: No Multi-Region / HA Setup
**Severity**: 🟡 Medium
**Details**: rt19 is a single-region, single-cluster deployment. No failover, no replication, no multi-region. Acceptable for dev/staging but not for enterprise production.

### GAP-014: No Backup/Restore Automation
**Severity**: 🟡 Medium
**Details**: No CronJob for PostgreSQL backups. No PVC snapshots. No point-in-time recovery. Manual `pg_dump` is the only option.

### GAP-015: No Rate Limiting Configured on Ingress
**Severity**: 🟡 Medium
**Details**: NGINX ingress has no rate limiting annotations. A malicious client could DoS the API.

### GAP-016: No Observability Stack Active
**Severity**: 🟡 Medium
**Details**: `05-monitoring.yaml` exists but may not be applied. No Prometheus, Grafana, or alerting active on rt19. Operators are blind to service health trends.

### GAP-017: Billing Service Not Deployed on rt19
**Severity**: 🟡 Medium
**Details**: Stripe integration exists in code but the billing service may not be deployed as a separate pod. Billing configuration may be incomplete.

### GAP-018: No Customer Documentation Portal
**Severity**: 🟡 Medium
**Details**: All documentation is in this folder (markdown files). Customers would need a hosted documentation site (e.g., ReadTheDocs, Docusaurus). No API reference docs (OpenAPI/Swagger).

### GAP-019: No Webhook System for Event Notifications
**Severity**: 🟡 Medium
**Details**: Customers can't receive real-time notifications. No webhook registration, no event filtering, no delivery guarantees.

### GAP-020: No Load Testing Results
**Severity**: 🟡 Medium
**Details**: Unknown capacity limits. No benchmarks for: API throughput, concurrent users, agent registration rate, audit write rate. The 2-node B2pls_v2 cluster is likely memory-constrained.

### GAP-021: TPM Attestation — No Real Implementation
**Severity**: 🟡 Medium
**Details**: TPM 2.0 attestation APIs exist but there's no actual TPM validation. The API accepts any PCR measurements without cryptographic verification.

### GAP-022: Policy Engine — OPA Not Deployed
**Severity**: 🟡 Medium
**Details**: OPA policy evaluation is referenced in docs and code but no OPA sidecar or service is deployed on rt19. Policy evaluation is done in-process by the control plane.

### GAP-023: No Agent-to-Agent (A2A) Protocol
**Severity**: 🟡 Medium
**Details**: Marketplace references A2A but no implementation exists. Agents can't communicate with each other through the platform.

---

## 🟢 Low Severity Gaps

### GAP-024: No White-Label/Custom Branding
All tenants see RuntimeAI branding. No custom logo, color scheme, or domain masking.

### GAP-025: No Mobile App
No iOS/Android app for monitoring or approvals.

### GAP-026: No Grafana Dashboards Pre-Built
The monitoring YAML deploys Grafana but no pre-built dashboards for RuntimeAI metrics.

### GAP-027: No Terraform Provider for RuntimeAI
Customers can't manage RuntimeAI resources via Terraform (agent registration, policy creation, etc.).

### GAP-028: No Helm Chart Values Documentation
Helm charts exist but values are not documented. Customers can't customize deployment without reading chart source.

### GAP-029: No Changelog/Release Notes Automation
No automated changelog generation. Release notes are manually written.

### GAP-030: No API Rate Limit Documentation
No documentation on API rate limits, quotas, or throttling behavior.

---

## Gaps by Customer Journey

### Day 1: "I just signed — how do I get started?"
| Step | Gap | Impact |
|------|-----|--------|
| Install CLI | GAP-002 | Can't install |
| Pull images | GAP-003 | Can't pull |
| Deploy data plane | GAP-001 | Can't deploy |
| Configure SSO | GAP-011 | Must use magic link |
| Read docs | GAP-018 | Markdown files only |

### Day 7: "I want to secure my AI agents"
| Step | Gap | Impact |
|------|-----|--------|
| Install scanner agent | GAP-006 | No downloadable binary |
| Enforce DLP inline | GAP-001 | No data plane |
| Forward to SIEM | GAP-009 | No SIEM connector |
| Block egress inline | GAP-001 | No data plane |

### Day 30: "I need to pass a SOC 2 audit"
| Step | Gap | Impact |
|------|-----|--------|
| Auto-generate evidence | Works ✅ | |
| Connect auditor | Works ✅ | |
| Verify audit chain | Works ✅ | |
| Integrate with GRC tool | GAP-009 | No direct integration |

### Day 90: "I want to integrate 20 tools"
| Step | Gap | Impact |
|------|-----|--------|
| Browse MCP catalog | Works ✅ | |
| Install Okta integration | Works ✅ | |
| Install Slack integration | GAP-007 | Not implemented |
| Build custom MCP server | GAP-002 | SDK not published |

---

## Priority Ranking (Recommended Fix Order)

| Priority | Gap | Effort | Impact |
|----------|-----|--------|--------|
| **P0** | GAP-001: Data Plane | 2-3 weeks | Unlocks real enforcement |
| **P0** | GAP-002: SDK/CLI Publishing | 1-2 weeks | Unlocks developer adoption |
| **P0** | GAP-003: Image Publishing | 1 week | Unlocks customer deployment |
| **P1** | GAP-005: Onboarding Automation | 2-3 weeks | Reduces manual work per customer |
| **P1** | GAP-006: Scanner Agent | 3-4 weeks | Unlocks discovery product |
| **P1** | GAP-011: SSO/OIDC | 1 week | Enterprise expectation |
| **P1** | GAP-007: MCP Server Implementations | Ongoing | Unlocks integration value |
| **P2** | GAP-008: Key Vault | 1 week | Security hygiene |
| **P2** | GAP-009: SIEM Integration | 2 weeks | Enterprise requirement |
| **P2** | GAP-010: eSign Storage | 2-3 days | Unlocks eSign product |
| **P2** | GAP-012: Dashboard Completeness | 2-3 weeks | UX quality |
| **P3** | GAP-013 through GAP-030 | Varies | Polish |

---

## Self-Criticism: What This Document Gets Wrong

1. **API endpoints may not match reality**. The guides in this folder use endpoint paths based on codebase analysis. Some paths may differ in the deployed version. Every curl command should be tested against the live rt19 pod.

2. **Feature descriptions may overstate maturity**. Some features described in the product guides are architecturally present in the code but may not be wired up end-to-end. For example, "budget hard limits auto-activate kill switch" — the code paths exist but may not be integration-tested.

3. **The test scripts assume a happy path**. They check HTTP 200 responses but don't deeply validate response payloads. A 200 with empty data or mock data would pass.

4. **ARM64 compatibility is assumed but not tested for all services**. rt19 runs on ARM64 nodes. While Go services cross-compile easily, Python services (Discovery, AAIC) and Nginx configurations may have ARM64-specific issues.

5. **This folder was created by analyzing code, not by running every command on live rt19**. Some commands may fail in ways not anticipated here.

---

## Action Items for Next Sprint

- [ ] Deploy data plane services on rt19 (GAP-001)
- [ ] Publish SDK to npm (GAP-002)
- [ ] Set up GHCR publishing pipeline (GAP-003)
- [ ] Test every script in this folder against live rt19
- [ ] Fix every failing endpoint discovered during testing
- [ ] Update this document with actual results

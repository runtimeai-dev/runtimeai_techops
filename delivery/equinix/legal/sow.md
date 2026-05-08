![RuntimeAI](runtimeai_logo.png)

# STATEMENT OF WORK

## RuntimeAI Autonomous AI Security Platform — Trial Evaluation

---

**SOW Reference**: RTAI-EQIX-SOW-2026-001
**Effective Date**: [Upon execution by both parties]
**Version**: 1.1 — Draft

---

## 1. Parties

| Party | Entity | Contact |
|-------|--------|---------|
| **Provider** | RuntimeAI, Inc., 2261 Market Street, STE 30493, San Francisco, CA 94114 | Roshan Shaik, Founder & CEO |
| **Evaluator** | Equinix, Inc., One Lagoon Drive, Redwood City, CA 94065 | Kaladhar Voruganti, Brandon Gore, Equinix |

---

## 2. Purpose

This Statement of Work ("SOW") defines the scope, deliverables, responsibilities, and success criteria for a **4-week trial evaluation** of the RuntimeAI Autonomous AI Security Platform (the "Platform"). The trial is intended to validate the Platform's capabilities across two primary use cases:

1. **Network Product Integration** — Evaluation of RuntimeAI as a security and governance layer for Equinix Distributed AI Hub, Equinix Fabric, and Network Edge VNFs, under the direction of SVP, Network.
2. **Equinix Internal IT** — Evaluation of RuntimeAI for securing Equinix's internal AI agents, workloads, and tooling, under the direction of SVP, Equinix IT.

A third engagement model — RuntimeAI as an Equinix Fabric colo customer and Service Provider — is documented in Section 8 for future activation when a mutual customer requests private interconnection.

---

## 3. Scope of Evaluation

### 3.1 Platform Components

RuntimeAI will deliver the following platform components:

**Control Plane (CP):**
| Component | Description |
|-----------|-------------|
| Policy Engine | OPA/Rego-based policy enforcement with Natural Language → Rego translation |
| Identity Fabric | SPIFFE/X.509 agent identity issuance and management |
| Compliance Hub | Automated evidence generation for SOC 2 Type II, EU AI Act, FedRAMP |
| Risk Scoring Engine | Continuous risk assessment across all registered agents |
| Audit Chain | Immutable audit trail with cryptographic hash chaining |
| Dashboard & Ops Center | Real-time visibility, alerting, and operational management |
| SaaS Admin Console | Multi-tenant administration, onboarding, user management, platform health |
| Cost Intelligence | AI cost tracking, budget caps, and per-agent attribution via API (real-time agent metering requires SDK integration) |
| RuntimeAI Sign | Digital signature and document execution for governance workflows |
| Agent Marketplace | Agent catalog, registration, capability discovery, and sharing |
| Auditor Dashboard | Compliance auditor-facing view with evidence bundles and audit trails |
| SIEM Export | Event forwarding to Splunk (HEC), Datadog (Logs API), or file — per-tenant config, background worker with enrichment |
| Ticketing Integration | Jira REST API v3 bi-directional sync — auto-create tickets by severity, webhook receiver, encrypted token storage (ServiceNow planned) |
| HRIS Lifecycle | Employee termination webhook → auto-deprovision agent access with reprieve/lease management |
| Access Reviews | Periodic access certification campaigns — auto-populate from agent inventory, decide/apply workflow |
| Lifecycle Workflows | Automated trigger→action engine — create, enable, execute, and track workflow runs |
| A2A Protocol | Google Agent-to-Agent governed communication — policies, invoke, messages, capability discovery |
| Configurable Webhooks | Event-driven webhook delivery — per-tenant HMAC-signed notifications for governance events |
| IdP Connectors | SSO identity provider management (Okta, Azure AD, etc.) — CRUD, scan results, admin operations |
| SCIM 2.0 Provisioning | Automated user/group sync from identity providers via SCIM 2.0 proxy |
| GitHub App Integration | GitHub App webhook (HMAC-signed) + installation management for repo-based agent discovery |
| SSO / MFA | SSO proxy (Okta, Azure AD), MFA enforcement, JWKS validation, device trust |
| OAuth Risk Scanner | OAuth application grant enumeration, risk scoring, AI service app discovery |
| Notifications Engine | Event bus-driven notification service — registered handlers for governance events |
| DP↔CP Bridge | Data-plane to control-plane sync — drift findings, discovery results, WAF events, cost events, token validation |


**Data Plane (DP):**
| Component | Description |
|-----------|-------------|
| AI Firewall | DLP/PII scanning, egress control, WAF rate limiting |
| Kill Switch | Sub-100ms agent termination (3 severity levels) with forensic capture |
| MCP Gateway | 6-layer governed tool access pipeline for Model Context Protocol (ships with Okta + PostgreSQL servers; extensible — guide included for adding custom MCP tools) |
| Behavioral Intelligence | Drift detection, anomaly scoring, behavioral baselines |
| AI Respond (Autonomous AI Respond) | Automated incident response workflows — risk-triggered kill switch, alerting, and remediation |
| Discovery Scanners | 12 scanner types (GitHub, AWS, Azure, GCP, Network, DNS, Process, OAuth, VS Code, Multi-Cloud, AI Assistant, MCP) |
| Shadow AI Inbox | Unregistered agent detection and triage |
| LLM Router | OPA-enforced LLM vendor proxy — routes agent requests to AI providers with policy enforcement |
| Identity DNS | DNS-based agent identity resolution — resolves agent IDs to endpoints via DNS and DNS-over-HTTPS (DoH) with JWT auth |
| ML Intelligence Engine | Model registry, hybrid risk scoring, behavioral drift detection, data pipeline analytics, and edge foundation models |
| TPM Attestation (Verifier) | Hardware-bound agent identity via TPM 2.0 — PCR verification, golden measurements, attestation status dashboard |

> **Note**: LLM Router target is configurable via environment variable. It can route to cloud providers via Internet (OpenAI, Anthropic) or to Equinix's own self-hosted LLM (vLLM, Ollama, etc.) for fully offline operation.

**Supporting Services:**
| Component | Description |
|-----------|-------------|
| PostgreSQL | Multi-tenant database with Row-Level Security (RLS) |
| Redis | Session management, caching, and real-time event messaging (Pub/Sub) |
| Auth Service | User authentication, session management, magic link login |
| Vault Broker | Secrets management — supports HashiCorp Vault (on-prem), Azure Key Vault (cloud), or AWS Secrets Manager |
| Dex (OIDC Provider) | SSO and identity federation |
| Nginx | Reverse proxy, TLS termination, API gateway |
| Prometheus + Grafana | Monitoring, metrics, and observability dashboards |

### 3.2 Autonomous Capabilities

The Platform operates autonomously — background workers, event-driven workflows, and pre-built response templates run continuously without human intervention.

#### Background Workers (Always Running)

| Worker | Description |
|--------|-------------|
| Lifecycle Reaper | 10-second ticker scans for terminated employees (auto-revoke agents), inactive agents (auto-warn after 30 days), and expired leases (auto-suspend) |
| SIEM Forwarder | Async event forwarding with retry (3 attempts) and Dead Letter Queue — background enrichment before send |
| Audit Pipeline | Concurrent workers + poller — every audit event is asynchronously hashed, chained, and stored |
| Access Review Scheduler | Background goroutine checks for scheduled campaigns and auto-launches when due |
| Entitlement Expiration Checker | Auto-revokes expired entitlement assignments |
| Health Heartbeat | Periodic heartbeat from Data Plane → Control Plane — detects dead agents automatically |

#### Pre-Built Autonomous Workflow Templates

The platform ships with 5 pre-built trigger→action chains. Each chains multiple autonomous actions:

| Template | Trigger | Autonomous Actions (Chained) |
|----------|---------|------------------------------|
| High Risk Auto-Response | Risk level → Critical | Disable agent → Revoke access → Trigger kill switch → Send notification → Log audit event |
| New Agent Onboarding | Agent created | Log audit event → Send notification |
| Drift Violation Response | Drift detected (high severity) | Send notification → Log audit event |
| Inactive Agent Cleanup | 90 days of inactivity | Disable agent → Send notification → Log audit event |
| Sponsor Departure | Sponsor removed | Send notification → Create Jira ticket → Log audit event |

> Custom workflows can be created via the Lifecycle Workflows API — any trigger type can chain any combination of actions.

#### Event-Driven Autonomous Behaviors

| Behavior | Trigger | Auto-Action |
|----------|---------|-------------|
| Auto-Quarantine | Shadow AI found with high risk score | Agent auto-quarantined in Shadow AI Inbox |
| Kill Switch Cascade | AI Respond risk threshold exceeded | Kill switch fires autonomously (< 100ms) |
| Webhook Delivery | Any governance event | HMAC-signed webhook auto-fires to configured endpoints |
| Jira Auto-Create | Finding above configured severity threshold | Jira ticket auto-created with encrypted API token |

#### Autonomous Pillar Summary

| Pillar | Description | Capabilities |
|--------|-------------|--------------|
| **Self-Observing** | Continuous monitoring without human action | Lifecycle Reaper, Health Heartbeat, Audit Pipeline, Discovery Scanners |
| **Self-Healing** | Auto-remediation on detection | High Risk Auto-Response, Kill Switch Cascade, Auto-Quarantine, Sponsor Departure |
| **Self-Governing** | Autonomous policy enforcement and compliance | Drift Violation Response, Jira Auto-Create, Entitlement Expiration, Access Review Scheduler |
| **Self-Learning** | Adaptive behavioral baselines over time | Inactive Agent Cleanup, Behavioral Intelligence baselines, Risk Scoring Engine |

### 3.3 Deployment Model

RuntimeAI delivers the Platform as **pre-built container images** hosted on RuntimeAI's private container registry. No source code is delivered.

**Image Delivery:**
- RuntimeAI provides Equinix a **read-only, time-scoped registry access token** to pull container images.
- Token auto-expires at trial end (60 days). Renewal at RuntimeAI's discretion.
- All images are multi-architecture (linux/amd64, linux/arm64).

**Deployment Options:**
The Platform has **zero runtime Internet dependency** — all services (CP, DP, database, cache, secrets) run entirely within the deployment environment. Internet access is required only to pull container images from the registry.

| Option | Description |
|--------|-------------|
| **Azure AKS (Recommended)** | Equinix deploys to their own Azure Kubernetes cluster. Fastest path — full deployment guide and Terraform templates provided. |
| **On-Prem Kubernetes** | Equinix deploys to on-prem K8s. Pull images once from registry, then run fully on-prem. |
| **Air-Gapped** | Equinix pulls images from registry on an Internet-connected machine, then transfers to the air-gapped environment via standard container image export/import. |

**RuntimeAI Provides:**

| Deliverable | Description |
|-------------|-------------|
| Container images | Pre-built, signed, pulled via registry token |
| Kubernetes manifests | 8 YAML files covering all CP + DP services |
| Secrets generation script | Generates all required environment variables and credentials |
| Seed script | Populates demo tenants, sample data, and MCP catalog |
| Azure Deployment Guide | Step-by-step AKS deployment (Terraform + K8s) |
| Smoke test script | Validates all services are running and healthy |

**Updates During Trial:**
- RuntimeAI pushes updated images to the registry as needed (bug fixes, enhancements).
- Equinix applies updates by restarting the affected service: `kubectl rollout restart deployment/<service>`.

---

## 4. Deliverables

### 4.1 RuntimeAI Deliverables

| # | Deliverable | Description |
|---|-------------|-------------|
| 1 | **Deployment Package** | Pre-built container images (via registry token), Kubernetes manifests, environment configuration |
| 2 | **Bill of Materials (BOM)** | All services, versions, dependencies, resource requirements (CPU/RAM/disk) |
| 3 | **Installation Guide** | Step-by-step Kubernetes deployment (Azure AKS and on-prem K8s) |
| 4 | **Architecture Overview** | Control Plane + Data Plane topology, networking, security model |
| 5 | **Per-Product Guides** | Individual guide for each product: setup, configuration, testing, FAQ, troubleshooting |
| 6 | **SDK Documentation** | Python and Node.js SDK reference with code examples |
| 7 | **API Reference** | All REST endpoints, request/response schemas, Postman collection |
| 8 | **Seed Data** | Customer-neutral demonstration data for trial environment |
| 9 | **Validation Scripts** | Automated test suite Equinix can run independently |
| 10 | **Troubleshooting Guide** | Common issues, error codes, log locations, diagnostic commands |
| 11 | **Operational Runbook** | Backup, upgrade, restart, and rollback procedures |

### 4.2 Equinix Deliverables

| # | Deliverable | Description |
|---|-------------|-------------|
| 1 | **Compute Environment** | Kubernetes cluster, Docker host, or cloud account meeting minimum resource requirements |
| 2 | **Network Access** | Outbound HTTPS for container image pulls from RuntimeAI registry |
| 3 | **Evaluation Report** | Written assessment of installation, support, features, functionality, and claim validation |
| 4 | **SVP Presentations** | Report presented to SVP Network and SVP Equinix IT |

---

## 5. Support Model

| Aspect | Detail |
|--------|--------|
| **Model** | Self-service evaluation |
| **Approach** | Equinix installs, configures, and tests independently using provided documentation |
| **RuntimeAI Support** | Available for installation issues, configuration questions, and bug reports |
| **Response Time** | Best-effort during business hours (9 AM – 6 PM PT, Mon–Fri) |
| **Channel** | Email: support@runtimeai.io; or mutually agreed Slack channel |
| **Escalation** | Critical issues escalated to RuntimeAI engineering within 4 hours |

---

## 6. Timeline

| Phase | Duration | Activity |
|-------|----------|----------|
| **Pre-Trial** | 1 week | SOW + NDA execution, environment provisioning |
| **Delivery** | Upon signing | RuntimeAI delivers deployment package + documentation |
| **Installation** | Week 1 | Equinix deploys platform, RuntimeAI available for support |
| **Evaluation** | Weeks 2–3 | Equinix runs tests independently, validates claims |
| **Report** | Week 4 | Equinix writes evaluation report |
| **Presentations** | Week 4 | Report presented to SVP Network + SVP Equinix IT |

**Trial Start Date**: Mutually agreed upon SOW execution and environment readiness.
**Trial Duration**: 4 weeks (28 calendar days) from deployment date.
**License Duration**: 2 months (60 calendar days) from deployment date — provides buffer if deployment or evaluation is delayed.
**Trial Limits**: Up to **250 registered agents**, **10 admin users**, **2 tenants** (Network + IT).
**Extension**: A 2-week extension of the evaluation period is available upon mutual written agreement if critical evaluation areas require additional data. Total license duration remains 60 days.

---

## 7. Success Criteria

The following areas are available for evaluation during the trial, organized into **Core** (recommended for all evaluators) and **Extended** (available for deeper validation). Equinix may prioritize evaluation areas based on their use case.

### 7.1 Core Evaluation Areas

| # | Area | Criteria |
|---|------|----------|
| 1 | **Installation** | Platform deploys successfully within documented timeframe |
| 2 | **Discovery** | Scanners detect AI agents across evaluated environment |
| 3 | **Identity** | SPIFFE/X.509 identities issued and verified for registered agents |
| 4 | **Policy Enforcement** | OPA/Rego policies enforce access control and data governance |
| 5 | **AI Firewall** | DLP/PII detection blocks sensitive data in prompts/responses |
| 6 | **Kill Switch** | Agent termination completes in under 100ms with forensic capture |
| 7 | **MCP Gateway** | Governed tool access pipeline enforces policies on MCP calls |
| 8 | **Compliance** | SOC 2 / EU AI Act evidence bundles generated from trial data |
| 9 | **Documentation** | Guides are accurate, complete, and sufficient for self-service evaluation |
| 10 | **Support** | RuntimeAI responsive and helpful when contacted |

### 7.2 Extended Evaluation Areas

The following capabilities are included in the trial platform and available for evaluation. Equinix may test any or all of these based on time and interest.

| # | Area | Criteria |
|---|------|----------|
| 11 | **Cost Intelligence** | Cost tracking and budget enforcement functional via API |
| 12 | **SIEM Integration** | Event forwarding to Splunk or Datadog verified end-to-end |
| 13 | **Ticketing** | Jira ticket auto-creation from findings, webhook sync operational |
| 14 | **Behavioral Drift** | Drift detection triggers alerts when agent behavior deviates from baseline |
| 15 | **NL→Rego** | Plain English policy rule compiles to OPA/Rego and enforces correctly |
| 16 | **TPM Attestation** | Hardware-bound agent identity verified via TPM 2.0 with PCR golden measurement checks |
| 17 | **HRIS Lifecycle** | Employee termination webhook triggers automatic agent deprovisioning |
| 18 | **Access Reviews** | Access certification campaign runs end-to-end with decide/apply workflow |
| 19 | **A2A Protocol** | Agent-to-Agent governed invocation with policy enforcement |
| 20 | **GitHub App** | Repo-based agent discovery via GitHub App webhook integration |
| 21 | **IdP / SCIM** | SSO connector and SCIM 2.0 user provisioning operational |
| 22 | **Lifecycle Workflows** | Automated trigger→action workflow executes and tracks run history |
| 23 | **Configurable Webhooks** | Event-driven webhook delivery fires for governance events |
| 24 | **Notifications** | Event bus-driven notifications trigger on key platform events |
| 25 | **OAuth Risk Scanning** | OAuth app grants discovered and risk-scored |

### 7.3 Evaluation Scope Acknowledgment

> The Platform includes a comprehensive set of capabilities. Equinix acknowledges that:
>
> (a) The trial duration may not permit evaluation of all Extended Areas.
>
> (b) Features not evaluated during the trial period carry **no negative inference** regarding functionality or fitness.
>
> (c) The evaluation report should reflect only areas **actually tested** — features not tested should be noted as "Not Evaluated" rather than "Not Functional."
>
> (d) RuntimeAI will provide documentation and test scripts for all listed capabilities. Equinix determines which areas to prioritize based on their evaluation objectives.

---

## 8. Three Engagement Models

### Model 1: Equinix Network Product
RuntimeAI evaluated as a security and governance layer integrated with Equinix Distributed AI Hub, Equinix Fabric, and Network Edge VNFs. Evaluation results presented to **SVP, Network**.

### Model 2: Equinix Internal IT
RuntimeAI evaluated for securing Equinix's own internal AI agents — shadow AI discovery, DLP, policy enforcement, compliance automation, and cost tracking. Evaluation results presented to **SVP, Equinix IT**.

### Model 3: RuntimeAI as Fabric Colo / Service Provider (Future)
RuntimeAI establishes colocation presence on Equinix Fabric, enabling enterprise customers to access RuntimeAI via private/direct Fabric interconnection. Cost shared between customer, Equinix, and RuntimeAI. **This model will be activated when a mutual customer requests private interconnection** and is not in scope for the current trial.

---

## 9. Intellectual Property

- RuntimeAI retains all intellectual property rights to the Platform, including source code, algorithms, models, documentation, and trade secrets.
- Equinix receives a **non-exclusive, non-transferable, revocable evaluation license** for the duration of the trial period.
- No source code is delivered. Platform is delivered as **pre-built container images** via a read-only, time-scoped registry access token.
- Registry access token expires automatically at trial end. RuntimeAI may revoke access at any time.
- Upon trial completion or termination, Equinix shall destroy all copies of the Platform (including locally cached container images) and confirm destruction in writing.
- **Exception**: If Equinix executes a Letter of Intent (LOI) or obtains a license (production or non-production) from RuntimeAI prior to or within 30 days of trial completion, Equinix may retain the trial instance for the purpose of migrating configurations, policies, settings, and operational data to subsequent deployments.

---

## 10. Confidentiality

This SOW is subject to the Mutual Non-Disclosure Agreement (RTAI-EQIX-NDA-2026-001) executed concurrently herewith. Key provisions:
- **Mutual Confidentiality**: Neither party shall disclose the other party's Confidential Information.
- **Non-Replication**: Neither party shall replicate, reverse-engineer, or create derivative works based on the other party's proprietary technology or trade secrets disclosed during the engagement.

---

## 11. Fees

This trial is provided at **no cost** to Equinix for the RuntimeAI Platform software and documentation. Equinix shall provide and bear the cost of all infrastructure (compute, storage, networking) required to install and test the Platform in their own environment. There is no commercial commitment or obligation to purchase arising from this SOW. Commercial terms, if any, will be negotiated separately following the trial.

---

## 12. Limitation of Liability

THE PLATFORM IS PROVIDED "AS IS" FOR EVALUATION PURPOSES. RUNTIMEAI MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE. RUNTIMEAI'S TOTAL LIABILITY UNDER THIS SOW SHALL NOT EXCEED THE TOTAL FEES PAID BY EQUINIX UNDER THIS SOW. EQUINIX ASSUMES ALL RISK ASSOCIATED WITH THE EVALUATION.

---

## 13. Termination

Either party may terminate this SOW at any time with **30 days' written notice**. Upon termination:
- Equinix shall destroy all copies of the Platform and documentation, subject to the exception in Section 9 (LOI/license retention).
- RuntimeAI shall destroy all Equinix Confidential Information received.
- Sections 9, 10, and 12 survive termination.

---

## 14. Governing Law

This SOW shall be governed by the laws of the State of California, without regard to conflict of law provisions.

---

## 15. Signatures

| | RuntimeAI, Inc. | Equinix, Inc. |
|--|----------------|---------------|
| **Name** | Roshan Shaik | |
| **Title** | Founder & CEO | |
| **Date** | | |
| **Signature** | _________________ | _________________ |

---

*RTAI-EQIX-SOW-2026-001 — Draft v1.1 — April 15, 2026*

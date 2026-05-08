# Prompt: Technical Architect + Testing Architect — Equinix Delivery Package Review

> **Copy the entire contents below this line and paste as a prompt to your AI coding agent.**

---

## Role

You are a **Senior Technical Architect** and **Testing Architect** performing a rigorous, independent review of a delivery package for **Equinix** — a Tier-1 data center customer receiving an **on-premises installation** of the **RuntimeAI Platform** (The Autonomous Economy Control Plane). Your review carries the weight of a pre-ship audit. Nothing ships to Equinix until your review passes.

## Context

- **Product**: RuntimeAI — a 10-product SaaS/On-Prem platform for AI agent governance, compliance, identity, security, and lifecycle management.
- **Customer**: Equinix (Fortune 500 data center operator)
- **Delivery Model**: On-premises Kubernetes deployment (AKS, EKS, or bare-metal K8s)
- **Live Environment**: Currently running on `rt19` AKS cluster in Azure (`westus2`)
- **API Base**: `https://api.rt19.runtimeai.io`
- **SoW**: 25 success criteria covering installation through advanced features

## What to Review

Review the ENTIRE Equinix delivery folder and all related documents:

### Primary: Delivery Package
```
/Users/roshanshaik/work/runtimeai/Delivery/Equinix/
├── README.md                           # Delivery overview
├── legal/
│   ├── sow.md                          # ⚠️ THE ACTUAL SOW — 25 success criteria (SOURCE OF TRUTH)
│   └── nda.md                          # NDA template
├── docs/
│   ├── 01_platform_bom.md              # Bill of Materials (all services, versions, ports)
│   ├── 02_installation_guide.md        # K8s installation steps
│   ├── 03_architecture_overview.md     # System architecture
│   ├── 04_api_reference.md             # API documentation
│   ├── 05_troubleshooting.md           # Troubleshooting guide
│   ├── 06_operational_runbook.md       # Ops runbook
│   ├── runtimeai_postman_collection.json # Postman collection
│   └── products/                       # Per-product guides (15 products)
│       ├── 00_platform_overview.md
│       ├── 00_product_guides.md
│       ├── 01_admin_onboarding.md
│       ├── 02_identity_fabric.md
│       ├── 03_discovery_scanners.md
│       ├── 04_governance_compliance.md
│       ├── 05_ai_firewall_killswitch.md
│       ├── 06_behavioral_drift.md
│       ├── 07_aiops_workflows.md
│       ├── 08_mcp_gateway.md
│       ├── 09_cost_intelligence.md
│       ├── 10_esign.md
│       ├── 11_marketplace.md
│       ├── 12_saas_admin.md
│       ├── 13_auto_compliance.md
│       ├── 14_sdk_integration.md
│       └── 15_ml_intelligence.md
├── testing_output/                     # API test logs
│   ├── 00_test_summary.md
│   ├── 01–09 test results
│   ├── discovery_scanners/             # Scanner test results
│   └── real_agents/                    # Real agent scripts used for testing
├── todo-list/                          # Tracker, verification logs
│   ├── 00_master_tracker.md
│   ├── user_action_items.md
│   ├── sow_fix_verification_log.md
│   └── sow_deep_verification_log.md
└── 032727_equinix_readiness_gaps.md    # Prior gap assessment
```

### Secondary: Supporting Context
```
# Actual SoW (legal source of truth)
/Users/roshanshaik/work/runtimeai/Delivery/Equinix/legal/sow.md

# Enterprise platform code & deployment
/Users/roshanshaik/work/runtimeai-enterprise/deployment/scripts/rt19/  # Deployment scripts
/Users/roshanshaik/work/runtimeai-enterprise/deployment/scripts/rt19/k8s/  # K8s manifests

# Seed scripts
/Users/roshanshaik/work/runtimeai/Engagements/Feltsense/seed_feltsense_demo.sh  # Demo seed

# QA suites
/Users/roshanshaik/work/runtimeai-enterprise/qa_testing_local/run_suite.sh
/Users/roshanshaik/work/runtimeai/End2EndTest/run_e2e.sh
```

## Your Deliverable

Create a single, exhaustive document at:
```
/Users/roshanshaik/work/runtimeai/Delivery/Equinix/032827_architect_review.md
```

The document MUST contain the following sections:

---

### Section 1: Executive Summary
- Overall delivery readiness score (Ready / Conditionally Ready / Not Ready)
- Top 5 risks for Equinix on-prem deployment
- Blocker count by severity (P0 Critical, P1 High, P2 Medium, P3 Low)

### Section 2: SoW Compliance Matrix
For EACH of the 25 SoW success criteria:
| # | SoW Criterion (verbatim from sow.md) | Status (PASS/FAIL/PARTIAL/UNTESTED) | Evidence Found | Gaps | Test Command to Verify |
Map EVERY criterion. Do not skip any. If evidence is missing, mark it UNTESTED. If partial, explain what's missing.

### Section 3: Documentation Completeness Audit
For each document in `docs/`:
- Does it exist? Is it complete?
- Does it reference the correct API endpoints?
- Does it match the actual deployed behavior?
- Are there screenshots or examples?
- Would an Equinix DevOps engineer be able to follow it from scratch?
- Score each doc: Complete / Partial / Stub / Missing

### Section 4: Installation & Deployment Audit
- Review `02_installation_guide.md` — does it cover:
  - [ ] Prerequisites (K8s version, node specs, storage classes, namespaces)
  - [ ] Secrets provisioning (Vault/KMS integration or manual K8s secrets)
  - [ ] Image pull from registry (ACR, private registry, air-gapped)
  - [ ] Database setup (PostgreSQL with RLS, migrations)
  - [ ] Redis setup
  - [ ] TLS/cert-manager setup
  - [ ] DNS/Ingress configuration
  - [ ] Service dependencies and startup order
  - [ ] Health check validation after install
  - [ ] Rollback procedure
- Review K8s manifests in `deployment/scripts/rt19/k8s/` — are they parameterized or hardcoded?
- Can Equinix run this in an air-gapped environment?

### Section 5: Security & Compliance Audit
- RLS coverage: are ALL tenant-scoped tables covered?
- Secrets management: are any secrets hardcoded in code, manifests, or docs?
- Auth: JWT validation, session management, OIDC integration
- Network isolation: Network policies in K8s?
- SOC 2 / FedRAMP alignment
- Data encryption at rest and in transit

### Section 6: Test Coverage Gap Analysis
For each SoW item, does a **real, executable test** exist?
| SoW # | Test Script Exists? | Test Is Automated? | Test Uses Real API? | Test Validates Response? | Gap |
Identify any SoW items that have:
- No test at all
- A test that only checks HTTP 200 (not response content)
- A test that uses hardcoded/stubbed data
- A test that is manual-only (no script)

### Section 7: On-Prem Readiness Gaps
Things that work on our hosted `rt19` but may break on Equinix's on-prem:
- External dependencies (SendGrid, Azure Key Vault, ACR)
- DNS assumptions
- TLS certificate provisioning
- Cloud-specific storage (Azure Blob → what on-prem?)
- OIDC provider configuration
- Outbound connectivity requirements (for discovery scanners, Ollama, etc.)

### Section 8: Coding Agent Test Instructions
This is the most critical section. Write **detailed, step-by-step instructions** that a coding agent (AI assistant) can follow to validate every deliverable. The agent has access to:
- `kubectl` (connected to the target cluster)
- `curl` (for API testing)
- `az` CLI (for Azure)
- `gh` CLI (for GitHub)
- `python3`, `bash`, `jq`
- The full codebase at the paths listed above

Structure as:

#### 8.1: Pre-Flight Checks
```bash
# Commands to verify cluster connectivity, namespace, pod health, DB connectivity
```

#### 8.2: Authentication
```bash
# How to obtain session cookies for API testing
# How to test both admin and operator roles
# How to test cross-tenant isolation
```

#### 8.3: For Each SoW Item (#1–#25)
```
## SoW #N: [Title]
### What to Test
- [specific acceptance criteria from sow.md]
### Test Commands
```bash
# Exact curl/kubectl commands with expected responses
```
### Expected Results
- [what PASS looks like]
- [what FAIL looks like]
### Edge Cases to Test
- [negative tests, boundary conditions, tenant isolation]
```

#### 8.4: Regression Suite
```bash
# Full regression script that runs ALL tests sequentially
# Outputs PASS/FAIL summary table
# Saves results to a timestamped log file
```

#### 8.5: Tenant Isolation Proof
```bash
# Commands to prove RLS works
# Cross-tenant data access attempts (should return 0 rows)
# API-level tenant isolation verification
```

#### 8.6: Performance Benchmarks
```bash
# Kill switch latency (target: <200ms)
# API response times for critical endpoints
# Discovery scanner throughput
```

### Section 9: Missing Deliverables
List anything that should be in the delivery package but isn't:
- [ ] Release notes / changelog
- [ ] Upgrade/migration guide (v1 → v2)
- [ ] Capacity planning guide
- [ ] Backup & restore procedures
- [ ] Disaster recovery runbook
- [ ] SLA definitions
- [ ] Support escalation contacts
- [ ] Training materials / video walkthroughs
- [ ] License files
- [ ] Third-party dependency licenses (SBOM)

### Section 10: Prioritized Remediation Plan
A table of ALL gaps found, prioritized:
| # | Gap | Severity | SoW # | Owner | Estimated Effort | Remediation Steps |

---

## Rules for Your Review

1. **Read every file** in the delivery folder. Do not skip any.
2. **Read the actual SoW** (`legal/sow.md`) word-for-word. Every criterion matters.
3. **Cross-reference** docs against actual API behavior (use the test logs in `testing_output/`).
4. **Be brutally honest**. This is going to a Fortune 500 customer. Flag everything.
5. **No assumptions**. If something isn't documented, it's a gap.
6. **Think like Equinix's CTO**. Would you be confident deploying this in your data centers?
7. **Think like their Security team**. Would this pass a SOC 2 audit?
8. **Think like their DevOps team**. Can they install this without calling RuntimeAI?
9. **All test commands must be real** — no stubs, no `echo`, no simulated outputs.
10. **Save your deliverable** to: `/Users/roshanshaik/work/runtimeai/Delivery/Equinix/032827_architect_review.md`

---

## After Creating the Document

1. Commit to a new feature branch following the `mac_mini/feature/<name>` convention
2. Create a PR to `dev` with a descriptive title
3. Output the PR URL

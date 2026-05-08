# Equinix Trial Evaluation Report — RuntimeAI

> **Document Template** — Provide this template to Equinix evaluators. They fill in their findings during Weeks 2–4 of the trial.

---

## Report Metadata

| Field | Value |
|-------|-------|
| **Evaluator Name** | _[Name, Title]_ |
| **Evaluation Track** | _[ ] Model 1 — Network Products  [ ] Model 2 — Internal IT_ |
| **Trial Period** | _[Start Date] – [End Date]_ |
| **Environment** | _[AKS / EKS / Equinix Metal / On-prem K8s]_ |
| **Kubernetes Version** | _[e.g., v1.28.x]_ |
| **Node Count / Specs** | _[e.g., 3 nodes × 4 vCPU / 16 GB]_ |
| **RuntimeAI Version** | _[Chart version / image tag]_ |

---

## 1. Deployment Assessment

| Metric | Value | Notes |
|--------|-------|-------|
| Time to deploy (from package receipt to all pods Running) | _[hours]_ | |
| Deployment method used | _[ ] Helm  [ ] kubectl  [ ] Air-gap_ | |
| Total pods deployed | _[count]_ / 36 expected | |
| Issues encountered during deployment | _[count]_ | See §1.1 |
| Issues resolved without RuntimeAI support | _[count]_ | |
| Documentation sufficiency (1–5) | _[score]_ | 5 = no external help needed |
| Self-serve capability (1–5) | _[score]_ | 5 = fully autonomous deployment |

### 1.1 Deployment Issues

| # | Issue | Severity | Resolution | Time to Resolve |
|---|-------|----------|------------|-----------------|
| 1 | _[describe]_ | _[Critical/High/Medium/Low]_ | _[describe]_ | _[hours]_ |
| 2 | | | | |
| 3 | | | | |

---

## 2. Core Evaluation Criteria (SoW §7.1) — Must Pass All 10

| # | Criterion | Pass/Fail | Evidence | Notes |
|---|-----------|-----------|----------|-------|
| 1 | **Installation** — All services deployed and healthy | _[ ] Pass  [ ] Fail_ | `kubectl get pods` output | |
| 2 | **Discovery** — Shadow AI agents detected by scanner | _[ ] Pass  [ ] Fail_ | `sow_test_suite.sh --item 2` output | |
| 3 | **Identity** — SPIFFE X.509 certificate issued to agent | _[ ] Pass  [ ] Fail_ | Certificate chain screenshot | |
| 4 | **Policy Enforcement** — OPA blocks deny policy within <50ms | _[ ] Pass  [ ] Fail_ | Response time measurement | |
| 5 | **AI Firewall** — PII detected and redacted in response | _[ ] Pass  [ ] Fail_ | DLP scan result screenshot | |
| 6 | **Kill Switch** — Agent terminated in <100ms with audit log | _[ ] Pass  [ ] Fail_ | Audit log entry | |
| 7 | **MCP Gateway** — Tool call blocked by governance policy | _[ ] Pass  [ ] Fail_ | `sow_test_suite.sh --item 7` output | |
| 8 | **Compliance** — SOC 2 evidence bundle downloadable | _[ ] Pass  [ ] Fail_ | Downloaded bundle screenshot | |
| 9 | **Documentation** — Guides match actual platform behavior | _[ ] Pass  [ ] Fail_ | Manual review notes | |
| 10 | **Support** — Support request responded within 4 hours | _[ ] Pass  [ ] Fail_ | Slack timestamp evidence | |

**Core Score**: _[X]_ / 10 Pass

---

## 3. Extended Evaluation Criteria (SoW §7.2) — Optional

| # | Criterion | Tested? | Pass/Fail | Notes |
|---|-----------|---------|-----------|-------|
| 11 | Cost Intelligence — budget cap enforced | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 12 | SIEM Integration — events reach Splunk/Datadog | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 13 | Ticketing — Jira ticket auto-created | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 14 | Behavioral Drift — drift alert fires | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 15 | NL→Rego — English policy compiles and enforces | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 16 | eSign — Document signed with PDF audit trail | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 17 | Vendor Proxy — LLM call routed through proxy | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 18 | Multi-Tenant Isolation — cross-tenant access blocked | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 19 | API Key Management — create/rotate/revoke lifecycle | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |
| 20 | Audit Chain — cryptographic integrity verified | _[ ] Yes  [ ] No_ | _[ ] Pass  [ ] Fail_ | |

**Extended Score**: _[X]_ / _[Y tested]_ Pass

---

## 4. Equinix-Specific Scenarios

### Model 1 — Network Products (Brandon Gore / SVP Network)

| Scenario | Tested? | Result | Notes |
|----------|---------|--------|-------|
| A: AI agent on Network Edge VNF governed by policy | _[ ] Yes  [ ] No_ | _[Pass/Fail/Partial]_ | |
| B: Shadow AI discovered on Fabric-connected tenant | _[ ] Yes  [ ] No_ | _[Pass/Fail/Partial]_ | |
| C: Cost overrun on Distributed AI Hub workload | _[ ] Yes  [ ] No_ | _[Pass/Fail/Partial]_ | |

### Model 2 — Internal IT (SVP Equinix IT)

| Scenario | Tested? | Result | Notes |
|----------|---------|--------|-------|
| A: Employee uses unsanctioned AI tool (Shadow AI) | _[ ] Yes  [ ] No_ | _[Pass/Fail/Partial]_ | |
| B: AI agent leaks PII in prompt to external API | _[ ] Yes  [ ] No_ | _[Pass/Fail/Partial]_ | |
| C: AI agent cost spike during off-hours | _[ ] Yes  [ ] No_ | _[Pass/Fail/Partial]_ | |

---

## 5. Platform Stability

| Metric | Value |
|--------|-------|
| Total evaluation period | _[days]_ |
| Unplanned pod restarts | _[count]_ |
| Platform downtime | _[hours]_ |
| Longest continuous uptime | _[hours]_ |
| Performance degradation observed? | _[ ] Yes  [ ] No_ |

---

## 6. Strengths

_List the top 3–5 strengths observed during the evaluation:_

1. _[e.g., "Comprehensive agent governance with real-time kill switch"]_
2.
3.
4.
5.

---

## 7. Areas for Improvement

_List areas where the platform could be improved:_

1. _[e.g., "Discovery scanner took >30 minutes to detect new agents"]_
2.
3.
4.
5.

---

## 8. Recommendation

| Decision | Selected |
|----------|----------|
| **Proceed to production contract** | _[ ]_ |
| **Extend trial for additional evaluation** | _[ ]_ |
| **Decline** | _[ ]_ |

### Justification

_[Provide 2–3 paragraphs explaining the recommendation, referencing specific test results and business value observed.]_

---

## 9. Appendix

### A. Test Suite Output

_Attach the full output of `sow_test_suite.sh` here._

```
[paste output]
```

### B. Pod Status at End of Trial

```
[paste kubectl get pods -n eqix-rt19 output]
```

### C. Screenshots

_Attach relevant dashboard screenshots, policy enforcement examples, and compliance evidence exports._

---

**Document prepared by**: _[Evaluator Name]_
**Date**: _[Date]_
**Submitted to**: _[SVP Network / SVP Equinix IT / RuntimeAI]_

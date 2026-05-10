# TOPS Index — TechOps Specifications (91 gaps, 160 hours)

Last updated: 2026-05-08  
Status: All in scope for production readiness  
Timeline: 2-3 weeks to Gate 5 (production ready)

---

## PHASE 1: Core Deployment + Secrets (Week 1 — 36 hours)

### Helm Charts (TOPS-001 to TOPS-008)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-001 | helm/control-plane/ — Copy + audit | 2h | Pending | Platform |
| TOPS-002 | helm/runtimeai-data-plane/ — Copy + audit | 2h | Pending | Platform |
| TOPS-003 | helm/runtimeai-control-plane/ — Copy variant | 2h | Pending | Platform |
| TOPS-004 | helm/authzion/ — Copy from runtimeai | 2h | Pending | Platform |
| TOPS-005 | helm/mcp-gateway/ — Copy + test | 2h | Pending | Platform |
| TOPS-006 | helm/whitelabel/ — Copy + customize | 2h | Pending | Platform |
| TOPS-007 | helm/agents/runtimeai-collector/ — DaemonSet chart | 3h | Pending | Platform |
| TOPS-008 | helm/agents/runtimeai-ebpf-tap/ — eBPF TAP chart | 3h | Pending | Platform |

**Subtotal**: 20 hours | **Gate**: All 8 pass `helm lint` + templates render error-free

---

### Terraform Configuration (TOPS-009 to TOPS-014)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-009 | terraform/azure/variables.tf | 2h | Pending | Platform |
| TOPS-010 | terraform/aws/variables.tf | 2h | Pending | Platform |
| TOPS-011 | terraform/gcp/variables.tf | 2h | Pending | Platform |
| TOPS-012 | terraform/oracle/variables.tf | 2h | Pending | Platform |
| TOPS-013 | terraform/*/backend.tf (all 4 clouds) | 8h | Pending | Platform |
| TOPS-014 | terraform/*/outputs.tf (all 4 clouds) | 4h | Pending | Platform |

**Subtotal**: 20 hours | **Gate**: `terraform plan` succeeds on all 4 clouds, state locks work

---

### QA Test Orchestration (TOPS-015 to TOPS-016)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-015 | qa/runtimeai/run_suite.sh — Create test runner | 2h | Pending | QA |
| TOPS-016 | qa/customer/run_suite.sh — Customer-facing suite | 2h | Pending | QA |

**Subtotal**: 4 hours | **Gate**: Both scripts execute 100+ tests with < 5% failure

---

### QuantumVault Integration (TOPS-017 to TOPS-022)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-017 | quantumvault-init.sh — Master key setup | 3h | Pending | Security |
| TOPS-018 | quantumvault-rotate-keys.sh — Key rotation | 2h | Pending | Security |
| TOPS-019 | Remove hardcoded secrets from Terraform | 3h | Pending | Security |
| TOPS-020 | create-secrets-from-qv.sh — K8s injection | 3h | Pending | Security |
| TOPS-021 | qv-audit-log-exporter.sh — Audit trail → Prometheus | 2h | Pending | Security |
| TOPS-022 | RLS for secrets access | 2h | Pending | Security |

**Subtotal**: 15 hours | **Gate**: Deploy rt19 with all secrets from QV, zero .env files in git

**PHASE 1 TOTAL**: 59 hours → compress to **36 hours** (parallel teams)  
**Phase 1 Owner**: Platform Lead + Security Lead  
**Phase 1 Deadline**: 2026-05-10 (EOD Friday)  

---

## PHASE 2: Monitoring & Alerting (Week 1-2 — 27 hours)

### Observability Stack (TOPS-023 to TOPS-033)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-023 | monitoring/prometheus/prometheus.yml — Full config | 4h | Pending | SRE |
| TOPS-024 | monitoring/prometheus/rules.yaml — Alert rules | 3h | Pending | SRE |
| TOPS-025 | monitoring/grafana/ — Dashboard suite | 4h | Pending | SRE |
| TOPS-026 | monitoring/alertmanager/alertmanager.yml — Routing | 2h | Pending | SRE |
| TOPS-027 | monitoring/alertmanager/silence-rules.yaml — Maintenance windows | 1h | Pending | SRE |
| TOPS-028 | docs/runbooks/alert-runbooks.md — Incident playbooks | 3h | Pending | SRE |
| TOPS-029 | scripts/monitoring/synthetic-tests.sh — Health checks | 2h | Pending | SRE |
| TOPS-030 | scripts/monitoring/log-aggregation.sh — Centralized logs | 2h | Pending | SRE |
| TOPS-031 | docs/incident-response-sla.md — SLA definition | 1h | Pending | SRE |
| TOPS-032 | scripts/incidents/postmortem-template.sh — Auto-create tickets | 1h | Pending | SRE |
| TOPS-033 | Post-incident review procedure | 1h | Pending | SRE |

**Subtotal**: 27 hours | **Gate**: Alerts fire to alerts@runtimeai.io, on-call responds within SLA

**PHASE 2 TOTAL**: 27 hours  
**Phase 2 Owner**: SRE Lead  
**Phase 2 Deadline**: 2026-05-13 (EOD Monday)  

---

## PHASE 3: Security Operations (Week 2 — 18 hours)

### Network, RBAC, Compliance (TOPS-034 to TOPS-044)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-034 | k8s/shared/network-policy.yaml — Pod traffic isolation | 2h | Pending | Security |
| TOPS-035 | k8s/shared/pod-security-policy.yaml — Hardening | 2h | Pending | Security |
| TOPS-036 | scripts/security/rbac-audit.sh — Weekly audit | 2h | Pending | Security |
| TOPS-037 | scripts/security/secrets-rotation-schedule.sh — Rotation ceremony | 2h | Pending | Security |
| TOPS-038 | scripts/security/container-image-scan.sh — Trivy integration | 2h | Pending | Security |
| TOPS-039 | scripts/security/audit-log-collector.sh — Centralized audit | 2h | Pending | Security |
| TOPS-040 | scripts/compliance/encryption-audit.sh — Coverage check | 1h | Pending | Security |
| TOPS-041 | docs/mfa-enforcement.md — Access control policy | 1h | Pending | Security |
| TOPS-042 | scripts/compliance/privacy-audit.sh — PII protection | 1h | Pending | Security |
| TOPS-043 | docs/penetration-testing-plan.md — Q1/Q3 schedule | 1h | Pending | Security |
| TOPS-044 | scripts/compliance/cis-benchmark-scan.sh — CIS controls | 1h | Pending | Security |

**Subtotal**: 18 hours | **Gate**: CIS Kubernetes benchmark 90%+ passing, RLS enforced everywhere

**PHASE 3 TOTAL**: 18 hours  
**Phase 3 Owner**: Security Lead  
**Phase 3 Deadline**: 2026-05-15 (EOD Thursday)  

---

## PHASE 4: Disaster Recovery (Week 2-3 — 12 hours)

### Backup, Failover, RTO/RPO (TOPS-045 to TOPS-051)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-045 | scripts/maintenance/database-backup.sh — Hourly snapshots | 3h | Pending | SRE |
| TOPS-046 | scripts/maintenance/kubernetes-etcd-backup.sh — Daily snapshots | 2h | Pending | SRE |
| TOPS-047 | docs/disaster-recovery.md — RTO/RPO runbook | 2h | Pending | SRE |
| TOPS-048 | Quarterly failover test (rt01 ↔ rt02) | 2h | Pending | SRE |
| TOPS-049 | docs/incident-escalation.md — Communication plan | 1h | Pending | SRE |
| TOPS-050 | Configuration backup & versioning (git + Azure) | 1h | Pending | SRE |
| TOPS-051 | docs/disaster-recovery-sla.md — RTO/RPO validation | 1h | Pending | SRE |

**Subtotal**: 12 hours | **Gate**: Monthly restore test < 5 min, actual RTO < 2 hours

**PHASE 4 TOTAL**: 12 hours  
**Phase 4 Owner**: SRE Lead  
**Phase 4 Deadline**: 2026-05-17 (EOD Saturday)  

---

## PHASE 5: Compliance, Cost, Documentation (Week 3 — 44 hours)

### Cost Management (TOPS-052 to TOPS-056)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-052 | scripts/maintenance/cost-analysis.sh — Monthly breakdown | 2h | Pending | Finance/SRE |
| TOPS-053 | k8s/shared/resource-quotas.yaml — Namespace caps | 1h | Pending | SRE |
| TOPS-054 | terraform/*/spot-instances.tf — 60% cost savings | 2h | Pending | Platform |
| TOPS-055 | terraform/*/reserved-instances.tf — 1-year commitment | 1h | Pending | Platform |
| TOPS-056 | monitoring/grafana/cost-tracking-dashboard.json | 2h | Pending | SRE |

**Subtotal**: 8 hours

---

### Compliance & Audit (TOPS-057 to TOPS-063)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-057 | scripts/compliance/soc2-evidence-generator.sh | 2h | Pending | Compliance |
| TOPS-058 | scripts/compliance/change-control-workflow.sh | 2h | Pending | Compliance |
| TOPS-059 | docs/data-retention-policy.md | 1h | Pending | Compliance |
| TOPS-060 | scripts/compliance/encryption-coverage-audit.sh | 1h | Pending | Compliance |
| TOPS-061 | docs/privacy-by-design.md | 1h | Pending | Compliance |
| TOPS-062 | Monthly attestation sign-off | 1h | Pending | Compliance |
| TOPS-063 | docs/compliance-control-mapping.md | 1h | Pending | Compliance |

**Subtotal**: 10 hours

---

### Documentation & Runbooks (TOPS-064 to TOPS-075)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-064 | docs/runbooks/add-new-service.md | 1h | Pending | Platform |
| TOPS-065 | docs/runbooks/scale-service.md | 1h | Pending | SRE |
| TOPS-066 | docs/runbooks/promote-code-to-production.md | 1h | Pending | Platform |
| TOPS-067 | docs/runbooks/emergency-rollback.md | 1h | Pending | SRE |
| TOPS-068 | docs/runbooks/pod-crashloop-troubleshooting.md | 1h | Pending | SRE |
| TOPS-069 | docs/runbooks/database-troubleshooting.md | 1h | Pending | SRE |
| TOPS-070 | docs/runbooks/tls-certificate-rotation.md | 1h | Pending | SRE |
| TOPS-071 | docs/runbooks/quantumvault-emergency.md | 1h | Pending | Security |
| TOPS-072 | docs/runbooks/incident-response-template.md | 1h | Pending | SRE |
| TOPS-073 | docs/architecture-decision-records/adr-001-quantumvault.md | 1h | Pending | Architecture |
| TOPS-074 | docs/architecture-decision-records/adr-002-kubernetes.md | 1h | Pending | Architecture |
| TOPS-075 | docs/troubleshooting-flowchart.md | 1h | Pending | SRE |

**Subtotal**: 12 hours

---

### Cloud Deployment Guides (TOPS-076 to TOPS-078)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-076 | docs/deployment-guides/azure.md (10 sections) | 3h | Pending | Platform |
| TOPS-077 | docs/deployment-guides/aws.md (10 sections) | 2h | Pending | Platform |
| TOPS-078 | docs/deployment-guides/gcp.md (10 sections) | 2h | Pending | Platform |

**Subtotal**: 7 hours

---

### Multi-Environment Documentation (TOPS-079 to TOPS-083)
| ID | Title | Effort | Status | Owner |
|----|-------|--------|--------|-------|
| TOPS-079 | environments/rt19/README.md (expand to 9 sections) | 2h | Pending | Platform |
| TOPS-080 | environments/rt01/README.md + rt02/README.md | 2h | Pending | Platform |
| TOPS-081 | environments/pqdata/README.md (expand) | 1h | Pending | Platform |
| TOPS-082 | environments/runtimecrm/README.md | 1h | Pending | Platform |
| TOPS-083 | environments/aep/README.md | 1h | Pending | Platform |

**Subtotal**: 7 hours

**PHASE 5 TOTAL**: 44 hours  
**Phase 5 Owner**: Platform Lead + Compliance Officer  
**Phase 5 Deadline**: 2026-05-22 (EOD)  

---

## MASTER SUMMARY

| Phase | Category | TOPS Count | Hours | Deadline | Owner |
|-------|----------|-----------|-------|----------|-------|
| 1 | Core + Secrets | 001–022 | 59h (36h) | 2026-05-10 | Platform + Security |
| 2 | Monitoring | 023–033 | 27h | 2026-05-13 | SRE |
| 3 | Security Ops | 034–044 | 18h | 2026-05-15 | Security |
| 4 | DR | 045–051 | 12h | 2026-05-17 | SRE |
| 5 | Compliance + Docs | 052–083 | 44h | 2026-05-22 | Platform + Compliance |
| **TOTAL** | **All Categories** | **001–083** | **160h (estimated)** | **2026-05-22** | **Cross-functional** |

---

## PRODUCTION READINESS GATES

| Gate | Date | Criteria | Owner |
|------|------|----------|-------|
| **Gate 1** | 2026-05-10 | TOPS-001 to TOPS-022 complete + deployed to rt19 | Platform Lead |
| **Gate 2** | 2026-05-13 | Monitoring + alerting working, first incident response validated | SRE Lead |
| **Gate 3** | 2026-05-15 | Security hardened, CIS benchmark 90%+ | Security Lead |
| **Gate 4** | 2026-05-17 | Disaster recovery tested, RTO/RPO validated | SRE Lead |
| **Gate 5** | 2026-05-22 | All 91 gaps resolved, production ready | VP Eng |

---

## TRACKING & STATUS

**Last Updated**: 2026-05-08 (initial creation)  
**Approval**: Pending VP Eng sign-off on scope + timeline  

**Next Actions**:
1. Assign Phase 1 owners (Platform Lead + Security Lead)
2. Start Phase 1 work Friday 2026-05-08
3. Daily standup Monday 2026-05-11 (9am UTC)
4. Gate 1 review Friday 2026-05-10 (EOD)

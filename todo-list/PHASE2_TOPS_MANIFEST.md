# Phase 2: Monitoring, Alerting & Security (TOPS-023 through TOPS-045)

## Overview
Phase 2 establishes observability and security controls for production operations.

| TOPS | Title | Effort | Status |
|------|-------|--------|--------|
| TOPS-023 | Prometheus Config & Scrape Targets | 3h | SPEC ✓ |
| TOPS-024 | Grafana Dashboards (15 total) | 4h | TO-SPEC |
| TOPS-025 | Alertmanager Routing & Escalation | 2h | TO-SPEC |
| TOPS-026 | Alert Rules & Thresholds (Critical, Warning) | 2h | TO-SPEC |
| TOPS-027 | K8s RBAC (cluster-admin, admin, edit, view) | 2.5h | TO-SPEC |
| TOPS-028 | K8s Network Policies (ingress/egress) | 3h | TO-SPEC |
| TOPS-029 | Pod Security Standards (restricted, baseline) | 2h | TO-SPEC |
| TOPS-030 | Image Registry Security (image signing, scanning) | 3h | TO-SPEC |
| TOPS-031 | Container Runtime Security (AppArmor, seccomp) | 2.5h | TO-SPEC |
| TOPS-032 | Secrets Encryption at Rest (etcd KMS) | 2h | TO-SPEC |
| TOPS-033 | TLS/HTTPS Everywhere (cert-manager, auto-renewal) | 2h | TO-SPEC |
| TOPS-034 | API Rate Limiting (per-tenant, per-service) | 2.5h | TO-SPEC |
| TOPS-035 | WAF Rules (OWASP Top 10) | 3h | TO-SPEC |
| TOPS-036 | DDoS Protection (cloud-native: Azure DDoS, AWS Shield) | 2h | TO-SPEC |
| TOPS-037 | Audit Logging (all API calls, K8s API audit) | 3h | TO-SPEC |
| TOPS-038 | Log Aggregation (ELK/Loki setup) | 3h | TO-SPEC |
| TOPS-039 | Incident Response Playbooks (5: outage, security breach, data loss, performance degradation, customer issue) | 2.5h | TO-SPEC |
| TOPS-040 | On-Call Rotation & Escalation Matrix | 1.5h | TO-SPEC |
| TOPS-041 | SLO/SLI Definitions & Error Budgets | 2h | TO-SPEC |
| TOPS-042 | Cost Monitoring & Chargeback (per-tenant usage) | 2.5h | TO-SPEC |
| TOPS-043 | Performance Profiling (CPU, memory, I/O bottlenecks) | 2h | TO-SPEC |
| TOPS-044 | Distributed Tracing (Jaeger/Zipkin setup) | 2.5h | TO-SPEC |
| TOPS-045 | MCP Gateway Registry & Marketplace (OPER_RT19-045 integration) | 3h | TO-SPEC |

**Total Phase 2 Effort: 62.5 hours**

## Gate: Phase 2 Completion Criteria
- [ ] All Prometheus scrapers healthy (100% services reporting metrics)
- [ ] All Grafana dashboards rendering without errors
- [ ] All alert rules passing dry-run validation
- [ ] All RBAC policies validated (no permission denials in logs)
- [ ] Network policies validated (no unexpected blocked traffic)
- [ ] Image scanning shows 0 critical vulnerabilities
- [ ] TLS certificates auto-renewing (test with 1-day test cert)
- [ ] Audit logs flowing to ELK (searchable)
- [ ] Incident playbooks reviewed and signed off by on-call team

## Notes
- Phase 2 is gated; cannot proceed to Phase 3 until all checks pass
- Security controls are non-negotiable for production (FedRAMP, SOC 2 requirements)
- Monitoring required for SLA compliance (99.9% uptime SLA)

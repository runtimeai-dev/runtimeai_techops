# Sub-Spec: Production Hardening Gaps — TechOps Platform

**Date**: May 8, 2026  
**Phase**: 2 of 7 (Production Hardening Workflow)  
**Gap Count**: 12 (6 P0, 4 P1, 2 P2)  
**Total Implementation Effort**: 28 hours

---

## P0 Gaps (Critical)

### P0-1: Kubernetes Manifest Validation Framework

**Problem**: K8s manifests can be syntactically valid but architecturally invalid (missing limits, no liveness probes, bad security contexts). No validation before deployment.

**Solution**:
- Create `scripts/validation/validate-manifests.sh` using kube-score + kubeval
- Validate all YAML in `k8s/` directory
- Check: resource limits, security context, probes, networkpolicies, RBAC
- Block deployment if validation fails
- Output human-readable report with violations

**Acceptance Criteria**:
- [ ] Script validates all 60+ K8s manifests
- [ ] Detects missing resource limits
- [ ] Detects missing security context
- [ ] Detects missing liveness/readiness probes
- [ ] Generates validation report before apply
- [ ] Executable from CI/CD pipeline

**Effort**: 2 hours

---

### P0-2: Helm Chart Integration Testing

**Problem**: Helm charts are linted but not tested for actual deployment. Template rendering can fail at deploy time.

**Solution**:
- Create `scripts/validation/test-helm-charts.sh`
- For each chart: `helm template` → `kubectl apply --dry-run` → `kubeval`
- Test with multiple values files (staging vs prod)
- Verify all resources render correctly
- Check for undefined template variables

**Acceptance Criteria**:
- [ ] Script tests all 7 Helm charts
- [ ] Validates with staging values
- [ ] Validates with production values
- [ ] Detects template errors early
- [ ] Generates validation report
- [ ] Part of CI/CD pipeline

**Effort**: 3 hours

---

### P0-3: Post-Deployment Health Verification

**Problem**: `kubectl rollout status` succeeds but pods may not actually be healthy (liveness probe failing, services not responding, metrics missing).

**Solution**:
- Create `scripts/validation/post-deploy-health-check.sh`
- Waits for pod ready (30s timeout)
- Validates endpoints responding (curl /health)
- Checks Prometheus metrics collection
- Verifies logs flowing to Loki
- Checks alerts configured

**Acceptance Criteria**:
- [ ] Validates all 31 core services ready
- [ ] Tests /health endpoints respond
- [ ] Verifies Prometheus scraping
- [ ] Verifies Loki log collection
- [ ] Checks alert rules loaded
- [ ] Part of deployment scripts

**Effort**: 2 hours

---

### P0-4: Load Testing Baseline

**Problem**: No baseline performance metrics. System behavior under load unknown.

**Solution**:
- Create `qa/load-tests/load-test-suite.sh`
- Run against rt19 (staging)
- Test scenarios: API requests, database queries, concurrent users
- Measure: p50, p95, p99 latency; error rates; throughput
- Store baselines in version control
- Generate comparison reports

**Acceptance Criteria**:
- [ ] 1000 concurrent users supported
- [ ] p99 latency < 500ms
- [ ] Error rate < 0.1%
- [ ] Baseline metrics documented
- [ ] Runnable from CI/CD
- [ ] Repeatable test suite

**Effort**: 4 hours

---

### P0-5: Chaos Engineering Procedures

**Problem**: Unknown system resilience. No procedures for testing failure scenarios.

**Solution**:
- Create `qa/chaos-tests/chaos-test-suite.sh`
- Scenarios: pod kill, node drain, disk fill, network latency
- Verify: automatic recovery, no data loss, alerts fire
- Document expected vs actual behavior
- Runbooks for investigation

**Acceptance Criteria**:
- [ ] 5+ chaos scenarios documented
- [ ] Pod restart within 30s of kill
- [ ] Service recovers automatically
- [ ] Alerts trigger during chaos
- [ ] No data loss
- [ ] Runbook per scenario

**Effort**: 3 hours

---

### P0-6: Emergency Rollback Procedures

**Problem**: Failed deployment or discovered bug → no automated rollback → extended downtime.

**Solution**:
- Create `scripts/deployment/rollback.sh`
- Rollback to previous Helm release
- Restore database from backup (if needed)
- Verify health after rollback
- Notify PagerDuty/Slack of rollback
- Generate rollback report

**Acceptance Criteria**:
- [ ] Script reverts last Helm release
- [ ] Validates health post-rollback
- [ ] Completes in < 5 minutes
- [ ] Sends notifications
- [ ] Works for all services
- [ ] Documented in runbooks

**Effort**: 2 hours

---

## P1 Gaps (High Priority)

### P1-1: Configuration Drift Detection

**Problem**: Manual changes to K8s resources not tracked. Infrastructure diverges from git.

**Solution**:
- Deploy Kubernetes audit logging (already configured)
- Create `scripts/compliance/detect-drift.sh`
- Compare live vs git-tracked configs
- Report unauthorized changes
- Alert on drift detection

**Acceptance Criteria**:
- [ ] Detects manual pod changes
- [ ] Reports unauthorized RBAC changes
- [ ] Identifies secret modifications
- [ ] Generates drift report daily
- [ ] Alerts on critical drift

**Effort**: 2 hours

---

### P1-2: Secret Rotation K8s Integration

**Problem**: Manual secret rotation error-prone. No K8s integration.

**Solution**:
- Enhance `scripts/secrets/rotate-*.sh` with K8s integration
- Update K8s secrets after rotation
- Restart pods to pick up new secrets
- Audit logging for rotations
- Verify applications still working

**Acceptance Criteria**:
- [ ] Automated secret rotation
- [ ] K8s secrets updated
- [ ] Pods restarted safely
- [ ] Zero downtime
- [ ] Audit trail logged
- [ ] Runbook for manual rotation

**Effort**: 3 hours

---

### P1-3: Terraform Dependencies Documentation

**Problem**: Module deployment order unclear. Risk of deployment failures.

**Solution**:
- Document dependency graph in `terraform/DEPENDENCIES.md`
- Create `scripts/validation/validate-tf-dependencies.sh`
- Check: PostgreSQL → Redis → K8s resources
- Validate variable outputs feed to dependents

**Acceptance Criteria**:
- [ ] Dependency graph documented
- [ ] Deployment order specified
- [ ] Validation script created
- [ ] No circular dependencies
- [ ] Safe to apply in order

**Effort**: 1 hour

---

### P1-4: Container Scanning Integration

**Problem**: Vulnerable container images deployed. No scanning before push.

**Solution**:
- Enhance `scripts/security/image-scanning.sh`
- Scan before push to registry
- Fail on critical vulnerabilities
- Block deployment if scan fails
- Generate SBOM (Software Bill of Materials)

**Acceptance Criteria**:
- [ ] Scans all images before push
- [ ] Fails on CRITICAL vulnerabilities
- [ ] Generates scan report
- [ ] SBOM created for each image
- [ ] Part of CI/CD pipeline
- [ ] Daily rescan of deployed images

**Effort**: 2 hours

---

## P2 Gaps (Medium Priority)

### P2-1: Operations Playbooks

**Problem**: Operators lack clear escalation procedures for incidents.

**Solution**:
- Create `docs/playbooks/incident-response.md`
- Define escalation paths by severity
- Link to runbooks
- Communication templates
- Post-incident review procedures

**Acceptance Criteria**:
- [ ] Escalation matrix defined
- [ ] Notification procedures documented
- [ ] Links to all runbooks
- [ ] Customer communication templates
- [ ] Post-incident checklist

**Effort**: 2 hours

---

### P2-2: Customer Demo Test Procedures

**Problem**: No TechOps operations demo. Customer validation unclear.

**Solution**:
- Create `qa/customer-demos/techops-operations-demo.md`
- Walkthrough: deploy service, monitor health, respond to alert, failover
- Document expected outputs at each step
- Success criteria for each scenario

**Acceptance Criteria**:
- [ ] 5+ demo scenarios documented
- [ ] Step-by-step procedures
- [ ] Expected outputs defined
- [ ] Success criteria clear
- [ ] 45-minute walkthrough total

**Effort**: 2 hours

---

## Implementation Summary

| Gap | P0/P1/P2 | Category | Hours | File(s) |
|-----|----------|----------|-------|---------|
| P0-1 | P0 | Validation | 2 | scripts/validation/validate-manifests.sh |
| P0-2 | P0 | Testing | 3 | scripts/validation/test-helm-charts.sh |
| P0-3 | P0 | Validation | 2 | scripts/validation/post-deploy-health-check.sh |
| P0-4 | P0 | Testing | 4 | qa/load-tests/load-test-suite.sh |
| P0-5 | P0 | Testing | 3 | qa/chaos-tests/chaos-test-suite.sh |
| P0-6 | P0 | Operations | 2 | scripts/deployment/rollback.sh |
| P1-1 | P1 | Operations | 2 | scripts/compliance/detect-drift.sh |
| P1-2 | P1 | Operations | 3 | scripts/secrets/rotate-integration.sh |
| P1-3 | P1 | Documentation | 1 | terraform/DEPENDENCIES.md |
| P1-4 | P1 | Security | 2 | scripts/security/image-scanning-enhanced.sh |
| P2-1 | P2 | Documentation | 2 | docs/playbooks/incident-response.md |
| P2-2 | P2 | Documentation | 2 | qa/customer-demos/techops-demo.md |
| | | **TOTAL** | **28** | |

---

**Phase**: 2 of 7 (Production Hardening Workflow)  
**Status**: ✅ COMPLETE — Ready for Phase 3 Implementation  
**Next Step**: Implement all 12 gaps in Phase 3

# SRE Agent Instructions: Phase Deployment & Validation

**For**: SRE engineers + automation agents  
**Purpose**: Validate TOPS completion, manage phase gates, operational readiness  
**Updated**: 2026-05-08

---

## YOUR ROLE

You own phase deployment, gate validation, and production readiness. Your checklist = production safety. Each gate = green light to proceed to next phase.

---

## PHASE WORKFLOW

### Pre-Phase Checklist (Before starting Phase N)

**1. Verify all blocking TOPS completed**

```bash
# Get list of TOPs that block Phase N
grep -h "Blocked By" /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-*.md | sort -u

# Check each is marked Complete
cat /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-NNN-*.md | grep "^Status:" | sort -u
# Expected: all prerequisite TOPS show "Status: Complete (pr-XXX)"
```

**2. Verify dependencies merged to dev**

```bash
git log dev --oneline | head -20
# Confirm all prerequisite TOPS PRs are merged
# Example: "Merge pull request #123 from techops/TOPS-017-quantumvault-init"
```

**3. Create phase tracking document**

```bash
cat > /Users/roshanshaik/work/runtimeai_techops/todo-list/PHASE-N-STATUS.md << 'EOF'
# PHASE-N Status Tracker

**Phase**: N  
**Owner**: [Name]  
**Start Date**: 2026-05-XX  
**Target End Date**: 2026-05-YY  
**Status**: IN_PROGRESS

## Daily Progress

| Date | TOPS Complete | Effort | Blockers |
|------|---------------|--------|----------|
| 2026-05-08 | 0/11 | 0h | None |

## Gate Criteria

- [ ] All TOPS marked Complete in spec
- [ ] All PRs merged to dev
- [ ] All acceptance tests passing
- [ ] 0 hardcoded secrets in code
- [ ] Documentation complete

## Sign-Off

- [ ] Platform Lead: code review passed
- [ ] Security Lead: secrets audit passed
- [ ] SRE Lead: deployment verified
EOF
```

---

### During-Phase Checklist (Daily)

**1. Daily standup (10 min)**

Ask each developer:
- Which TOPS completed today?
- Estimated hours vs actual hours spent?
- Any blockers?

**Example standup output**:
```
TOPS-001 (helm-control-plane): Complete (2h vs 2h estimated) ✅
TOPS-002 (helm-data-plane): In Progress (1.5h of 2h spent)
TOPS-003 (helm-control-plane-variant): Blocked by TOPS-017 ⏸️
TOPS-017 (quantumvault-init): In Progress (3.5h of 3h — edge case found)
```

**2. Monitor effort vs estimate**

```bash
# Sum estimated vs actual for Phase N TOPS
for tops in TOPS-{001..022}; do
  est=$(grep "Effort:" /Users/roshanshaik/work/runtimeai_techops/todo-list/${tops}-*.md | grep -oP '\d+h' | head -1)
  echo "$tops: estimated $est"
done | awk '{s+=$NF} END {print "Phase 1 Total Estimate: " s}'

# Current actual (from standup tracking):
# Phase 1 Estimate: 59h → compress to 36h (parallel teams)
# Current Actual: ? (sum from daily standups)

# If actual > estimate * 1.2: escalate to Platform Lead
```

**3. Validate tests passing**

```bash
# For each completed TOPS, run verification from spec
# Example TOPS-001 (Helm control-plane):

echo "=== TOPS-001 Verification ==="
helm lint /Users/roshanshaik/work/runtimeai_techops/helm/control-plane/
echo "Result: $? (expected 0)"

helm template /Users/roshanshaik/work/runtimeai_techops/helm/control-plane/ > /tmp/test.yaml
kubectl apply --dry-run=client -f /tmp/test.yaml
echo "Result: $? (expected 0)"

# Expected output:
# === TOPS-001 Verification ===
# 1 chart(s) linted, 0 chart(s) failed
# Result: 0 (expected 0)
# Result: 0 (expected 0)
```

---

### Post-Phase Checklist (Gate Review)

#### GATE 1 REVIEW (TOPS-001 to TOPS-022) — 2026-05-10

**Validation Checklist**:

```bash
# ✅ All 22 TOPS marked Status: Complete
for i in {001..022}; do
  status=$(grep "^Status:" /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-${i}-*.md 2>/dev/null)
  echo "TOPS-$i: $status"
done | grep -v "Complete" && echo "FAIL: Some TOPS not complete" || echo "PASS: All TOPS complete"

# ✅ All PRs merged to dev (0 open PRs for Phase 1 TOPS)
git log dev --oneline | grep -c "TOPS-00[1-9]\|TOPS-01[0-9]\|TOPS-02[0-2]"
# Expected: > 20 commits

# ✅ Zero hardcoded secrets in merged code
git log dev --oneline | head -25 | while read commit; do
  git show $commit | grep -i "password\|secret\|api.key" | grep -v "^#" | grep -v "template" && echo "FAIL: Found secret in $commit"
done
# Expected: 0 matches

# ✅ All Helm charts pass helm lint
for chart in helm/control-plane helm/runtimeai-data-plane helm/runtimeai-control-plane helm/authzion helm/mcp-gateway helm/whitelabel helm/agents/*; do
  [ -d "$chart" ] && helm lint $chart || echo "SKIP (not yet copied): $chart"
done
# Expected: "X chart(s) linted, 0 chart(s) failed" for all

# ✅ All Terraform passes terraform plan (all 4 clouds)
for cloud in azure aws gcp oracle; do
  echo "=== terraform/$cloud ==="
  cd /Users/roshanshaik/work/runtimeai_techops/terraform/$cloud
  terraform init -backend=false > /dev/null 2>&1
  terraform plan -out=tfplan 2>&1 | head -5
  [ $? -eq 0 ] && echo "PASS" || echo "FAIL"
done
# Expected: "PASS" for all 4

# ✅ QuantumVault init script tests pass
export QUANTUMVAULT_TEST_MODE=true
bash /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-init.sh --test
# Expected: "Master key initialization test PASSED" + exit 0

# ✅ rt19 deployment succeeds using Phase 1 artifacts
# (This is a full integration test, manual step)
export QUANTUMVAULT_INIT=true
bash scripts/build/rt19/build-push-deploy.sh control-plane
# Expected: deployment rolls out successfully, health checks pass
```

**Gate 1 Sign-Off**:

```markdown
- [ ] Platform Lead: "All code reviewed, patterns consistent, approved for production"
- [ ] Security Lead: "Secrets audit passed, no hardcoded values found"
- [ ] SRE Lead: "rt19 deployment verified, all services healthy"
- [ ] VP Eng: "36-hour estimate met (or escalation documented)"

Status: ✅ PASS → Proceed to Phase 2 | ❌ FAIL → Fix and re-validate
```

---

#### GATE 2 REVIEW (TOPS-023 to TOPS-033) — 2026-05-13

**Validation Checklist**:

```bash
# ✅ Prometheus scraping all 31 services
kubectl port-forward -n rt19 svc/prometheus 9090:9090 &
sleep 2
curl -s http://localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets | length'
# Expected: > 30
kill %1  # stop port-forward

# ✅ Alertmanager routing to alerts@runtimeai.io
kubectl get secret -n monitoring alertmanager-config -o jsonpath='{.data.alertmanager\.yml}' | base64 -d | grep "alerts@runtimeai.io"
# Expected: found

# ✅ Synthetic tests passing (health checks every 5 min)
bash /Users/roshanshaik/work/runtimeai_techops/scripts/monitoring/synthetic-tests.sh
# Expected: all checks green, latency < 500ms

# ✅ At least 3 alert rules configured
kubectl get prometheusrules -n monitoring 2>/dev/null | wc -l
# Expected: > 3 rules

# ✅ First incident scenario tested (simulate pod crash)
echo "Killing a pod to trigger alert..."
POD=$(kubectl get pods -n rt19 -l app=control-plane -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n rt19 $POD
sleep 120  # Wait for Prometheus to detect crash + alertmanager to fire
curl -s http://localhost:9093/api/v1/alerts | jq '.data | length'
# Expected: > 0 active alerts

# ✅ Post-mortem template accessible
[ -f /Users/roshanshaik/work/runtimeai_techops/docs/runbooks/alert-runbooks.md ] && echo "PASS: runbook exists" || echo "FAIL"
```

**Gate 2 Sign-Off**:

```markdown
- [ ] SRE Lead: "All monitoring operational, incident response tested"
- [ ] Platform Lead: "Documentation complete and validated"
- [ ] On-call Lead: "Confirmed readiness (test incident responded within SLA)"

Status: ✅ PASS → Proceed to Phase 3 | ❌ FAIL → Fix monitoring
```

---

#### GATE 3 REVIEW (TOPS-034 to TOPS-044) — 2026-05-15

**Validation Checklist**:

```bash
# ✅ Network policies applied
kubectl get networkpolicies -n rt19 -A | wc -l
# Expected: > 5 policies

# ✅ Pod security policies enforced
kubectl get pods -n rt19 -o jsonpath='{.items[*].spec.securityContext}' | grep -c "privileged.*true"
# Expected: 0 (no privileged containers)

# ✅ RBAC audit passing
bash /Users/roshanshaik/work/runtimeai_techops/scripts/security/rbac-audit.sh 2>&1 | tail -3
# Expected: "All service accounts have appropriate permissions"

# ✅ Container images scanned
bash /Users/roshanshaik/work/runtimeai_techops/scripts/security/container-image-scan.sh 2>&1 | grep -E "HIGH|CRITICAL" | wc -l
# Expected: 0 matches

# ✅ CIS Kubernetes benchmark > 90% passing
bash /Users/roshanshaik/work/runtimeai_techops/scripts/compliance/cis-benchmark-scan.sh 2>&1 | tail -1
# Expected: "passed_controls: ≥81/90"

# ✅ RLS enforced (query without RESET ROLE returns 0 rows)
kubectl exec -n rt19 -it deployment/control-plane -- \
  psql -U runtimeai_app -d runtimeai \
  -c "SELECT COUNT(*) FROM tenant_users WHERE tenant_id != 'my-tenant'" 2>/dev/null
# Expected: 0 (RLS policy prevents cross-tenant access)
```

**Gate 3 Sign-Off**:

```markdown
- [ ] Security Lead: "CIS benchmark verified, RLS audit complete"
- [ ] Compliance Officer: "Encryption coverage = 100%"
- [ ] Platform Lead: "No regressions in existing services"

Status: ✅ PASS → Proceed to Phase 4 | ❌ FAIL → Security fixes required
```

---

#### GATE 4 REVIEW (TOPS-045 to TOPS-051) — 2026-05-17

**Validation Checklist**:

```bash
# ✅ Database backups automated (hourly)
kubectl get cronjobs -n rt19 -l app=database-backup -o jsonpath='{.items[0].spec.schedule}'
# Expected: "0 * * * *" (every hour)

# ✅ Restore test completed (latency < 5 min)
# (Manual: restore a backup snapshot to staging DB + measure time)
cat /Users/roshanshaik/work/runtimeai_techops/docs/backup-restore-test-log.txt | tail -1
# Expected: "Database restored in 4m22s"

# ✅ K8s etcd backups automated (daily)
kubectl get cronjobs -n rt19 -l app=etcd-backup -o jsonpath='{.items[0].spec.schedule}'
# Expected: "0 2 * * *" (daily)

# ✅ Disaster recovery runbook validated
[ -f /Users/roshanshaik/work/runtimeai_techops/docs/disaster-recovery.md ] && echo "PASS" || echo "FAIL"
grep -q "RTO.*<.*2.*hour" /Users/roshanshaik/work/runtimeai_techops/docs/disaster-recovery.md && echo "PASS: RTO target met" || echo "FAIL"

# ✅ Failover test completed (rt01 ↔ rt02)
[ -f /Users/roshanshaik/work/runtimeai_techops/docs/failover-test-q2-2026.md ] && echo "PASS: test report exists"
grep -q "actual.*RTO.*minutes" /Users/roshanshaik/work/runtimeai_techops/docs/failover-test-q2-2026.md && echo "PASS: RTO measured"
```

**Gate 4 Sign-Off**:

```markdown
- [ ] SRE Lead: "RTO/RPO validated, backup integrity confirmed"
- [ ] VP Eng: "DR plan meets business SLA"

Status: ✅ PASS → Proceed to Phase 5 | ❌ FAIL → DR fixes required
```

---

#### GATE 5 REVIEW (TOPS-052 to TOPS-083) — 2026-05-22

**Validation Checklist**:

```bash
# ✅ All 91 TOPS marked Complete
grep -c "^Status: Complete" /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-*.md
# Expected: 91

# ✅ Cost tracking dashboard shows monthly spend
[ -f /Users/roshanshaik/work/runtimeai_techops/monitoring/grafana/cost-tracking-dashboard.json ] && echo "PASS"

# ✅ Compliance evidence auto-generated
bash /Users/roshanshaik/work/runtimeai_techops/scripts/compliance/soc2-evidence-generator.sh > /tmp/soc2-evidence.json
[ -s /tmp/soc2-evidence.json ] && echo "PASS: evidence generated" || echo "FAIL"

# ✅ All runbooks written + tested
find /Users/roshanshaik/work/runtimeai_techops/docs/runbooks -name "*.md" | wc -l
# Expected: > 10 runbooks

# ✅ Monthly attestation signed
[ -f /Users/roshanshaik/work/runtimeai_techops/docs/monthly-attestation-2026-05.txt ] && echo "PASS: attestation exists"
grep -q "Signed by:" /Users/roshanshaik/work/runtimeai_techops/docs/monthly-attestation-2026-05.txt && echo "PASS: signed"

# ✅ Production deployment checklist completed
cat /Users/roshanshaik/work/runtimeai_techops/docs/production-readiness-checklist.md | grep "^- \[x\]" | wc -l
# Expected: all items checked
```

**Gate 5 Sign-Off**:

```markdown
- [ ] Platform Lead: "All artifacts delivered, production ready"
- [ ] Security Lead: "Compliance evidence complete, SOC 2 audit-ready"
- [ ] SRE Lead: "Operations documentation complete, runbooks tested"
- [ ] VP Eng: "✅ PRODUCTION READY — All 5 gates passed"

Status: ✅ PASS → DEPLOY TO PRODUCTION | ❌ FAIL → Final fixes required
```

---

## ESCALATION MATRIX

**Blocker in Phase N TOPS**:
1. SRE Lead + Phase owner investigate (1 hour max)
2. If unresolved: Escalate to VP Eng + skip dependent TOPS (parallel track)
3. If blocker persists > 4 hours: Call all-hands standup

**Production incident during Phase N**:
- Pause Phase N (except critical fixes)
- All SRE respond (P0 SLA = 15 min response)
- Resume Phase N after incident closed + postmortem complete

**Effort variance > 20% (e.g., TOPS-017 estimated 3h but actual 5.5h)**:
- Escalate to Platform Lead immediately
- Capture what caused overage (edge case, unclear requirements, etc.)
- Adjust remaining TOPS estimates if pattern detected

---

## METRICS TO TRACK

**Daily**:
- [ ] Effort vs estimate (accumulate actual hours spent per TOPS)
- [ ] TOPS completion rate (N complete / 22 total for Phase 1)
- [ ] Quality gates passing (lint, tests, dry-run)

**Weekly**:
- [ ] Phase progress (target: 40% by day 2, 80% by day 4, 100% by EOW)
- [ ] Effort variance (flag if > 20%)
- [ ] Incident response time (SLA met?)
- [ ] Zero hardcoded secrets in commits

**Example tracking**:
```
Phase 1 Progress (Target: 40% by 2026-05-09)
- Day 1 (2026-05-08): TOPS-001, TOPS-017, TOPS-023 complete → 13% (3/22)
- Day 2 (2026-05-09): +4 TOPS → 27% (6/22)
- Day 3 (2026-05-10): +9 TOPS → 59% (13/22) ✅ EXCEEDED 40% target
- Day 4 (2026-05-11): +9 TOPS → 100% (22/22) ✅ GATE 1 PASSED
```

---

## SUCCESS CRITERIA FOR SRE

- [ ] All 5 gates passed (2026-05-22)
- [ ] 0 critical security findings in production
- [ ] 0 unplanned outages due to TechOps gaps
- [ ] 0 hardcoded secrets in any code
- [ ] 100% backup restore success rate (monthly test)
- [ ] New ops engineer productive in < 1 day (using runbooks)
- [ ] Incident MTTR (mean time to resolve) < 15 min for SEV1
- [ ] Incident MTBF (mean time between failures) > 30 days
- [ ] Cost tracking within ±10% of forecast
- [ ] All compliance evidence auto-generated + monthly attestation signed

---

## QUICK REFERENCE

**Daily standup** (10 min):
```
"TOPS-001: ✅ Complete (2h est, 2h actual)
 TOPS-002: 🔶 In Progress (1.5h of 2h spent)
 TOPS-003: ⏸️  Blocked by TOPS-017 (waiting for QV init)"
```

**Gate validation** (30 min):
```bash
# Run all checks in Gate N section above
# If any FAIL: file issue + fix + revalidate
```

**Escalation** (immediate):
```
Blocker > 1 hour? → Escalate to Platform Lead
Incident? → All hands on deck
Secret found? → Remove + rebase PR + retest
```

---

**Questions?** Post in #techops-ops Slack or daily standup.

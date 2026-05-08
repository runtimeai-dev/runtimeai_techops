# TOPS: TechOps Specifications System

**Purpose**: Break down 91 production-blocking gaps into 91 actionable specifications (TOPS-001 to TOPS-083)  
**Timeline**: 2-3 weeks (May 8-22, 2026)  
**Status**: All in scope, ready for Phase 1 start (2026-05-08)

---

## What Is TOPS?

TOPS (TechOps Specifications) organizes the runtimeai_techops repo creation into:

- **91 individual gaps** (TOPS-001 to TOPS-083)
- **5 sequential phases** (Core → Secrets → Monitoring → Security → DR+Compliance+Docs)
- **Clear acceptance criteria** for each gap (no ambiguity)
- **Daily progress tracking** (effort vs estimate, blockers, completion rate)
- **5 production gates** (validation checkpoints before proceeding)

**Result**: Production-ready TechOps platform by 2026-05-22.

---

## Files in This Directory

| File | Purpose | Audience |
|------|---------|----------|
| **index.md** | Master index of all 91 TOPS + phase timeline | Everyone |
| **TOPS-001 to TOPS-083** | Individual gap specifications (each 1-2h work) | Coding agents, SRE |
| **AGENT_INSTRUCTIONS.md** | How coding agents implement TOPS | Claude Code + developers |
| **SRE_INSTRUCTIONS.md** | How SRE validates phases + manages gates | SRE team, VP Eng |
| **PRODUCTION_READINESS_CHECKLIST.md** | Final gate (Gate 5) before going live | VP Eng |

---

## How to Use TOPS

### For Coding Agents (implementing a TOPS)

1. **Pick a TOPS**
   ```bash
   cat /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-NNN-<name>.md
   ```

2. **Read the spec** (10 min)
   - Problem statement
   - Acceptance criteria (ALL must be checked ✅)
   - Testing procedure (must pass locally)
   - Dependencies (what blocks me?)

3. **Check dependencies** (5 min)
   - If blocked: skip and pick independent TOPS
   - If no blockers: proceed

4. **Implement** (1-3 hours)
   - Follow existing patterns (don't invent new ones)
   - No hardcoded secrets anywhere
   - Test locally before committing

5. **Update TOPS spec** (2 min)
   - Mark acceptance criteria complete
   - Note actual effort (vs estimate)
   - Add completion date

6. **Daily standup** (2 min)
   - Report: "TOPS-001: ✅ Complete (2h est, 2h actual)"

**See**: [AGENT_INSTRUCTIONS.md](../AGENT_INSTRUCTIONS.md)

---

### For SRE (validating phase completion)

1. **Before Phase N**
   - Verify all blocking TOPS from Phase N-1 complete
   - Verify all PRs merged to dev

2. **During Phase N** (daily)
   - Standup: track which TOPS complete, effort vs estimate
   - Validate tests passing (helm lint, kubectl dry-run, etc.)
   - Flag blockers, escalate if > 1 hour

3. **End of Phase N** (Gate Review)
   - Run all validation checks from Gate N section
   - Collect sign-offs from Platform Lead, Security Lead, VP Eng
   - Green light to Phase N+1 or loop back for fixes

**See**: [SRE_INSTRUCTIONS.md](../SRE_INSTRUCTIONS.md)

---

### For VP Engineering (gate sign-off)

1. **Gate 1** (2026-05-10): Core Deployment + Secrets
   - ✅ All 22 TOPS complete, tests passing, deployed to rt19

2. **Gate 2** (2026-05-13): Monitoring + Alerting
   - ✅ Prometheus/Grafana operational, alerts firing to alerts@runtimeai.io

3. **Gate 3** (2026-05-15): Security Hardened
   - ✅ Network policies, RBAC, CIS benchmark 90%+, RLS enforced

4. **Gate 4** (2026-05-17): Disaster Recovery
   - ✅ Backups working, restore test < 5 min, RTO/RPO validated

5. **Gate 5** (2026-05-22): Production Ready
   - ✅ All 91 TOPS complete, monthly attestation signed

**See**: [PRODUCTION_READINESS_CHECKLIST.md](../docs/PRODUCTION_READINESS_CHECKLIST.md)

---

## PHASE BREAKDOWN

| Phase | TOPS | Owner | Deadline | Focus |
|-------|------|-------|----------|-------|
| **1** | 001-022 (22 TOPS) | Platform + Security | 2026-05-10 | Helm, Terraform, QuantumVault, QA runners |
| **2** | 023-033 (11 TOPS) | SRE | 2026-05-13 | Prometheus, Grafana, Alertmanager, runbooks |
| **3** | 034-044 (11 TOPS) | Security | 2026-05-15 | Network policies, RBAC, image scanning, CIS |
| **4** | 045-051 (7 TOPS) | SRE | 2026-05-17 | Backups, failover, RTO/RPO validation |
| **5** | 052-083 (31 TOPS) | Platform + Compliance | 2026-05-22 | Cost, compliance, docs, runbooks |

---

## Quick Start: Implement Your First TOPS

### Example: TOPS-001 (Helm control-plane)

```bash
# 1. Read the spec
cat /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-001-helm-control-plane.md

# 2. Check dependencies (none for TOPS-001)
grep "Blocked By" /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-001-*.md

# 3. Copy Helm chart from source repo
mkdir -p helm/control-plane
cp -r /Users/roshanshaik/work/runtimeai-enterprise/deployment/helm/control-plane/* helm/control-plane/

# 4. Test locally
helm lint helm/control-plane/
helm template helm/control-plane/ > /tmp/test.yaml
kubectl apply --dry-run=client -f /tmp/test.yaml

# 5. Create branch & commit
git checkout -b techops/TOPS-001-helm-control-plane
git add helm/control-plane/
git commit -m "TOPS-001: Copy helm/control-plane/ chart from runtimeai-enterprise"
git push origin techops/TOPS-001-helm-control-plane

# 6. Create PR (manually or via CLI)
# [Wait for approval]

# 7. Update TOPS spec
# Edit TOPS-001-helm-control-plane.md:
# - Mark: Status: Complete (pr-123)
# - Note: Effort: 2h (met estimate), Completed By: Your Name, 2026-05-08

# 8. Report in standup
# "TOPS-001: ✅ Complete (2h est, 2h actual)"
```

---

## How to Track Progress

### Daily Standup Format

```
PHASE 1 PROGRESS (May 8-10)
- TOPS-001: ✅ Complete (2h est, 2h actual) — helm-control-plane
- TOPS-002: 🔶 In Progress (1.5h of 2h spent) — helm-data-plane
- TOPS-003: ⏸️  Blocked by TOPS-017 — helm-control-plane-variant
- TOPS-017: 🔶 In Progress (3.5h of 3h spent, edge case found) — quantumvault-init

Summary: 1 complete, 2 in progress (40% done), 0 blockers
Effort: 7h spent vs 7h estimated → ON TRACK
```

### Effort Tracking Sheet

**Create**: `/Users/roshanshaik/work/runtimeai_techops/todo-list/PHASE-1-EFFORT-LOG.txt`

```
Date     | TOPS  | Status   | Hours Spent | Estimated | Notes
---------|-------|----------|-------------|-----------|-------------------
2026-05-08 | 001 | Complete | 2h          | 2h        | Met estimate
2026-05-08 | 017 | In Prog  | 3.5h        | 3h        | Found edge case
2026-05-08 | 020 | In Prog  | 1h          | 3h        | Started today
---------|-------|----------|-------------|-----------|-------------------
Daily Total:       6.5h        8h          → 19% under (good pace)
Phase 1 Target:   36h (59h ÷ parallel) for Gate 1 by 2026-05-10
```

---

## Gate Review Workflow

### At End of Each Phase (Friday 5pm UTC)

```bash
# 1. Collect all completed TOPS
grep "^Status: Complete" /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-*.md | wc -l

# 2. Run all validation checks from Gate N section
# (Platform Lead, Security Lead, SRE Lead each run their checks)

# 3. Compile sign-offs in PHASE-N-STATUS.md
cat > /Users/roshanshaik/work/runtimeai_techops/todo-list/PHASE-1-STATUS.md << 'EOF'
# PHASE 1 COMPLETION REPORT

**Completed**: 22/22 TOPS ✅
**Effort**: 38h actual vs 36h target (105% — acceptable)
**Blockers**: 0
**Security**: 0 hardcoded secrets found

## Sign-Offs

- [x] Platform Lead: All code reviewed, patterns consistent
- [x] Security Lead: Secrets audit passed
- [x] SRE Lead: Deployments verified on rt19
- [x] VP Eng: Gate 1 PASSED → Proceed to Phase 2

Signed: 2026-05-10 17:00 UTC
EOF

# 4. Publish results to #techops-ops Slack
# "PHASE 1 COMPLETE ✅ — All 22 TOPS done, Gate 1 PASSED, proceeding to Phase 2"

# 5. Merge PHASE-1-STATUS.md to dev
git add /Users/roshanshaik/work/runtimeai_techops/todo-list/PHASE-1-STATUS.md
git commit -m "PHASE-1: Completion report — 22/22 TOPS complete, Gate 1 PASSED"
git push origin dev
```

---

## When Something Goes Wrong

### TOPS Blocked by Another TOPS

**Example**: TOPS-003 blocked by TOPS-017 (waiting for QuantumVault init)

```bash
# 1. Update TOPS-003 spec
cat >> /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-003-helm-control-plane-variant.md << 'EOF'

## Dependencies
- **Blocked By**: TOPS-017 (waiting for QuantumVault master key initialization)
- **Status**: BLOCKED (unblock when TOPS-017 complete)

EOF

# 2. Move on to independent TOPS in same phase
# (e.g., TOPS-001, TOPS-002, TOPS-004 — which don't depend on TOPS-017)

# 3. When TOPS-017 complete: unblock TOPS-003 + start it
```

### Effort Estimate Way Off

**Example**: TOPS-017 estimated 3h but actual is 5h

```bash
# 1. Don't hide the overage
# 2. Update TOPS-017 spec: Effort: 3h → Effort: 5h
# 3. Add note in "Implementation Notes": "Discovered X edge case, required +2h"
# 4. Commit the updated TOPS file + code
# 5. Mention in next standup: "TOPS-017 took 5h vs 3h (edge case found, captured)"
# 6. VP Eng may adjust remaining TOPS estimates if pattern detected
```

### Hardcoded Secret Found in Code (BEFORE commit)

```bash
# 1. Fix immediately
grep -r "password" scripts/secrets/quantumvault-init.sh
# Found: password="my-prod-password"

# 2. Replace with env var
sed -i 's/password="my-prod-password"/password="${DB_PASSWORD}"/' scripts/secrets/quantumvault-init.sh

# 3. Retest
bash scripts/secrets/quantumvault-init.sh --test

# 4. Commit + push
git add scripts/secrets/quantumvault-init.sh
git commit -m "TOPS-017: Fix hardcoded password → env var reference"
```

### Hardcoded Secret Found AFTER commit

**Status**: That TOPS FAILS acceptance. Do NOT push to dev. Revert + fix + recommit.

---

## Metrics Dashboard

Track Phase progress in real time:

```
PHASE 1: Core Deployment + Secrets (22 TOPS, 59h → 36h compressed)

Completion: [████████░░░░░░░░░░░░░░░░░░] 36% (8/22 TOPS)

Effort:
  Estimated: 36h
  Actual: 16h (45% of phase duration complete)
  Pace: ON TRACK ✅

Blockers: 0

Quality:
  0 hardcoded secrets ✅
  Tests passing ✅
  Patterns consistent ✅
```

---

## Reference Links

- **Master Index**: [index.md](index.md) — All 91 TOPS + timeline
- **Coding Agent Guide**: [../AGENT_INSTRUCTIONS.md](../AGENT_INSTRUCTIONS.md)
- **SRE Agent Guide**: [../SRE_INSTRUCTIONS.md](../SRE_INSTRUCTIONS.md)
- **Production Readiness**: [../docs/PRODUCTION_READINESS_CHECKLIST.md](../docs/PRODUCTION_READINESS_CHECKLIST.md)

---

## FAQ

**Q: What if I can't start my TOPS because it's blocked?**  
A: Switch to an independent TOPS in the same phase (that has no blockers). Document the blocker in your TOPS spec.

**Q: My estimate is wrong halfway through—what do I do?**  
A: Update the TOPS spec (note the new estimate + why), then continue. Report variance in daily standup.

**Q: I found a hardcoded secret in my code—am I in trouble?**  
A: Not if you catch it BEFORE committing. Fix immediately, retest, recommit. If found AFTER: that TOPS fails, must revert + fix + recommit.

**Q: How long is this whole thing going to take?**  
A: 160 hours total, 36-44 hours per phase. With 5-7 people working in parallel, 2-3 weeks to Gate 5 (production ready).

**Q: Can I skip a TOPS if it seems low-priority?**  
A: No. All 91 are P0 (production blocking). Skip = missing production requirement.

---

**Questions?** Ask in daily standup (9am UTC) or #techops-implementation Slack.

**Let's ship this.** 🚀

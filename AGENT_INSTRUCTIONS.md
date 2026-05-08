# Agent Instructions: TechOps Specification Implementation

**For**: Claude Code + all coding agents  
**Purpose**: Implement TOPS specifications to build production-grade TechOps  
**Updated**: 2026-05-08

---

## YOUR ROLE

You are implementing individual TOPS specifications to unblock deployments across 5 product repos. Your work enables 50+ engineers to ship code safely. Treat each TOPS as a critical production system component.

---

## CRITICAL RULES (Non-Negotiable)

### 1. READ TOPS SPEC FIRST

Every TOPS file (in `/Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-NNN-*.md`) has:
- Acceptance criteria (all must be checked ✅)
- Testing instructions (must pass locally)
- Dependencies (other TOPS that block or are blocked by this one)
- Outputs (exact files to create)

**Rule**: Never start coding until you've read and understood the entire spec. If unclear, **ASK FOR CLARIFICATION** (never guess).

---

### 2. NO HARDCODED SECRETS ANYWHERE

**Forbidden patterns**:
```bash
# ❌ BAD
password="my-prod-password"
api_key="sk-12345"
db_connection_string="postgres://user:pass@host"

# ✅ GOOD
password="${DB_PASSWORD}"
api_key="${API_KEY}"
db_connection_string="${DATABASE_URL}"
```

**Before committing**: Run this check
```bash
grep -r "password\|secret\|api.key\|bearer\|token" <your-files> \
  | grep -v "^#" \
  | grep -v "export \|=\${" \
  | grep -v ".template"
# Expected output: ZERO matches
# If found: replace with environment variable reference, retest
```

**If you find hardcoded secrets in your code BEFORE commit**: Fix immediately, retest, then commit. If found AFTER commit: that TOPS FAILS acceptance.

---

### 3. FOLLOW EXISTING PATTERNS

**Never invent new patterns.** Copy structure from existing files:

| File Type | Copy Pattern From | Checklist |
|-----------|------------------|-----------|
| K8s YAML | `k8s/rt19/01-namespaces.yaml` | Indentation (2 spaces), labels, resource limits |
| Helm chart | `helm/control-plane/templates/deployment.yaml` | Template syntax, values refs, helpers |
| Bash script | `scripts/build/rt19/build-push-deploy.sh` | Error handling, logging, idempotency |
| Go code | `runtimeai-enterprise/control-plane/main.go` | gofmt, go vet, golangci-lint |

**Pattern verification**:
- K8s: Copy indentation exactly, use existing label scheme (`app.kubernetes.io/name`, `app.kubernetes.io/version`)
- Helm: Match template syntax from existing charts, use `.Release.Name` + `.Chart.Name` naming
- Bash: Use `set -e` for error exit, `log()` function for output, `mkdir -p` for safety
- Go: Run `gofmt -w`, `go vet ./...`, `golangci-lint run` before commit

---

### 4. TEST BEFORE COMMITTING

Every file type has a local test command. **You must run it and pass BEFORE pushing**.

```bash
# K8s manifest
kubectl apply --dry-run=client -f <file>.yaml
# Expected: no validation errors, exit 0

# Helm chart
helm lint helm/<chart>/
helm template helm/<chart>/ > /tmp/test.yaml
kubectl apply --dry-run=client -f /tmp/test.yaml
# Expected: exit 0 on all commands

# Bash script
bash -n <script>.sh
shellcheck <script>.sh
# Expected: 0 errors from both

# Terraform
terraform plan -out=tfplan
# Expected: exit 0, shows plan preview

# Python/Go
python -m py_compile <file>.py  # Python
go build ./...  # Go
# Expected: exit 0
```

**If test fails locally**: Debug + fix before committing. Never push failing code.

---

### 5. GIT WORKFLOW FOR TOPS

**Branch name**:
```bash
git checkout -b techops/TOPS-NNN-<short-name>
# Example: techops/TOPS-017-quantumvault-init
```

**Commit message**:
```bash
git commit -m "TOPS-NNN: <short title> — <what changed>

- Added scripts/secrets/quantumvault-init.sh
- Added docs/quantumvault-setup.md
- No hardcoded secrets
- Tested: helm lint, kubectl dry-run"
```

**Push + PR**:
```bash
git push origin techops/TOPS-NNN-<short-name>
# Then create PR with link to TOPS spec in description
```

**After approval**: 
```bash
# Platform Lead merges (never auto-merge on security TOPS)
# Then you're notified merge is complete
```

---

### 6. DOCUMENT EVERY FILE

- **K8s manifests**: Comment on resource limits ("Why CPU=500m?") + RLS policy (if applies)
- **Helm templates**: Match existing comment style on similar templates
- **Bash scripts**: Comment non-obvious logic (not every line, only "why" blocks)
- **Terraform**: Comment variable choices ("3 nodes: covers failover" vs "why 3?")
- **Output**: Update TOPS spec with actual effort (if diverged from estimate)

**Comment style**:
```yaml
# K8s: explain the constraint
resources:
  limits:
    cpu: 500m     # Matches CPU request from runtimeai-enterprise deployment
    memory: 512Mi # OOMKill observed at 256Mi with 100 concurrent requests
```

```bash
# Bash: explain the logic, not the syntax
# Idempotent: safe to run twice (create secret only if missing)
kubectl get secret -n rt19 qv-admin-token > /dev/null 2>&1 || \
  kubectl create secret generic qv-admin-token -n rt19 --from-literal=token=${TOKEN}
```

---

## WORKFLOW: Implement a TOPS

### Step 1: Read TOPS Spec (10 min)

```bash
cat /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-NNN-<name>.md
```

Understand:
- [ ] Problem statement (what's missing?)
- [ ] Acceptance criteria (what does "done" mean?)
- [ ] Outputs (which files to create?)
- [ ] Dependencies (what blocks me? what do I block?)
- [ ] Testing (how to verify locally?)

---

### Step 2: Check Dependencies (5 min)

```bash
grep -h "Blocked By\|Blocks" /Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-*.md | grep "TOPS-NNN"
```

- If **blocked by other TOPS**: Do NOT start (file blocker comment in TOPS)
- If **no blockers**: Proceed to implementation

---

### Step 3: Implement (varies: 1-3 hours)

```bash
# Example: TOPS-017 (QuantumVault init)
cd /Users/roshanshaik/work/runtimeai_techops
mkdir -p scripts/secrets
touch scripts/secrets/quantumvault-init.sh

# Write code following existing patterns (copy from reference file)
# Example reference: scripts/build/rt19/build-push-deploy.sh (structure, error handling, logging)

# Verify no hardcoded secrets
grep -E "password|secret|api.key|bearer" scripts/secrets/quantumvault-init.sh | grep -v "^#" | grep -v "\${"
# Expected: 0 matches

# Syntax check
bash -n scripts/secrets/quantumvault-init.sh
# Expected: exit 0
```

---

### Step 4: Test (10-30 min)

Run acceptance criteria tests from TOPS spec:

```bash
# For TOPS-017 (quantumvault-init):
bash -n scripts/secrets/quantumvault-init.sh                # Check syntax
shellcheck scripts/secrets/quantumvault-init.sh             # Check style
bash scripts/secrets/quantumvault-init.sh --test            # Run test mode
# Expected: "Master key initialization test PASSED" + exit 0
```

**If test fails**: 
1. Read error message carefully
2. Check existing pattern in repo
3. Fix the issue
4. Retest
5. Only commit when test passes

---

### Step 5: Commit & Push (5 min)

```bash
git add <files>
git commit -m "TOPS-017: quantumvault-init.sh — initialize master key + tenant hierarchy

- Added scripts/secrets/quantumvault-init.sh (3h effort)
- Added docs/quantumvault-setup.md
- Test mode: --test flag verified encryption roundtrip
- No hardcoded secrets (grep verified)"

git push origin techops/TOPS-017-quantumvault-init
```

---

### Step 6: Update TOPS Status (2 min)

Edit `/Users/roshanshaik/work/runtimeai_techops/todo-list/TOPS-017-quantumvault-init.md`:

```diff
- [ ] Code complete + all acceptance criteria met
+ [x] Code complete + all acceptance criteria met
- [ ] Tested locally
+ [x] Tested locally (bash -n + --test mode both passed)
- [ ] PR created + merged
+ [x] PR created + merged to dev (pr-123)

+ Completed By: Your Name, 2026-05-08
+ Verified By: Security Lead, 2026-05-09
```

---

## COMMON GOTCHAS & FIXES

### Gotcha 1: "I hardcoded a secret without realizing"

**Detection**: 
```bash
grep -r "password\|secret\|api_key\|bearer\|token" scripts/ k8s/ helm/ \
  | grep -v "^#" | grep -v "\${"
# Found: password="my-prod-db-password"
```

**Fix** (BEFORE commit):
```bash
# Replace hardcoded value with env var reference
sed -i 's/password="my-prod-db-password"/password="${DB_PASSWORD}"/' scripts/secrets/quantumvault-init.sh

# Retest
bash scripts/secrets/quantumvault-init.sh --test
# Expected: passes with env var

# Then commit
```

**If you discover hardcoded secret AFTER committing**: That TOPS fails acceptance. Do NOT push to dev.

---

### Gotcha 2: "K8s manifest indentation is wrong"

**Error**:
```
kubectl apply --dry-run=client -f k8s/rt19/NN-control-plane.yaml
# error validating data: spec.template.spec.containers[0].resources is not of type object
```

**Fix**:
```yaml
# ❌ WRONG (tabs or wrong spacing)
spec:
  template:
    spec:
      containers:
      - name: control-plane
        resources:
          limits:
            cpu: 500m   # BAD: improper indent

# ✅ RIGHT (2 spaces, consistent)
spec:
  template:
    spec:
      containers:
      - name: control-plane
        resources:
          limits:
            cpu: 500m
```

Copy indentation exactly from reference file: `k8s/rt19/01-namespaces.yaml`.

---

### Gotcha 3: "Helm template has undefined variable"

**Error**:
```bash
helm template helm/control-plane/ --debug
# Error: template: control-plane/templates/deployment.yaml:10:9 - 
# executing "control-plane" at <.Values.image.registry>: nil pointer evaluating interface {}.image.registry
```

**Fix**:
```yaml
# In helm/control-plane/values.yaml, add missing key:
image:
  registry: runtimeaicr.azurecr.io   # Was missing
  repository: control-plane
  tag: latest
```

Then retest:
```bash
helm template helm/control-plane/ > /tmp/test.yaml
# Expected: exit 0
```

---

### Gotcha 4: "Script works locally but fails in production"

**Common cause**: Hardcoded paths (e.g., `/Users/roshanshaik/work/runtimeai-enterprise`)

**Detection**:
```bash
grep -E "^/Users/|/home/|/opt/runtimeai" scripts/*.sh
# Found: /Users/roshanshaik/work/runtimeai-enterprise/control-plane
```

**Fix**:
```bash
# Replace hardcoded path with relative or env var
sed -i 's|/Users/roshanshaik/work/runtimeai-enterprise|$(pwd)/../runtimeai-enterprise|' scripts/secrets/quantumvault-init.sh

# Or use environment variable
# export CONTROL_PLANE_PATH=/Users/roshanshaik/work/runtimeai-enterprise
# ... then use $CONTROL_PLANE_PATH in script
```

---

### Gotcha 5: "Effort estimate was way off"

**What to do**:
1. Don't hide the overage
2. Update TOPS spec: change Effort from 3h to 5h
3. Add note in "Implementation Notes": "Discovered X edge case, required +2h investigation"
4. Commit the updated TOPS file alongside code
5. Mention in daily standup: "TOPS-017 took 5h vs 3h estimated (found edge case)"

---

## WHEN STUCK

| Problem | Solution |
|---------|----------|
| Can't understand spec | Ask in daily standup (10 min clarification) |
| Blocked by another TOPS | File blocker comment in TOPS-NNN spec, pause this TOPS |
| Test failing locally | Read error carefully, check existing patterns, ask SRE |
| Effort blowing up (2x estimate) | Escalate to phase owner, reduce scope or get help |
| Found a hardcoded secret | FIX IT before committing (never push hardcoded secrets) |

---

## ACCEPTANCE = ALL CRITERIA CHECKED

A TOPS is **NOT done** until:

```markdown
- [x] Criterion 1
- [x] Criterion 2
- [x] Criterion 3
- [x] All acceptance criteria MET
- [x] Tested locally (lint + test mode)
- [x] No hardcoded secrets (grep verified)
- [x] Code follows existing patterns
- [x] PR merged to dev
```

**If even 1 checkbox unchecked**: Status = **In Review** (NOT Complete).

---

## BLOCKED WAITING FOR OTHER WORK?

If TOPS-NNN is blocked by TOPS-MMM:

```bash
# In TOPS-NNN.md, update:
## Dependencies
- **Blocked By**: TOPS-MMM (description: e.g., "waiting for QuantumVault master key init")
- **Status**: BLOCKED

# Move on to independent TOPS in same phase
# Example: while waiting for TOPS-017, work on TOPS-001 (Helm chart copy)
```

---

## EFFORT TRACKING

**Daily check-in** (2 min):
- How many hours did you spend today?
- What's remaining?
- Any blockers?

Example:
```
TOPS-001: estimated 2h, spent 2h, complete ✅
TOPS-002: estimated 2h, spent 1h, 1h remaining
TOPS-003: estimated 2h, spent 0h, BLOCKED by TOPS-017 ⏸️
TOPS-017: estimated 3h, spent 4h, 1h remaining (edge case found)
```

---

## SUCCESS LOOKS LIKE

✅ TOPS-NNN spec completely understood  
✅ Code written following existing patterns  
✅ All hardcoded values replaced with ${VAR_NAME}  
✅ Tests passing locally (helm lint, kubectl dry-run, bash -n, etc.)  
✅ Git commit messages reference TOPS ID  
✅ PR approved + merged to dev  
✅ TOPS spec updated with actual effort + completion date  
✅ Daily standup: "TOPS-017 complete"

---

## QUICK REFERENCE: Common Test Commands

```bash
# K8s
kubectl apply --dry-run=client -f <file>.yaml

# Helm
helm lint helm/<chart>/
helm template helm/<chart>/

# Bash
bash -n <script>.sh
shellcheck <script>.sh

# Terraform
terraform plan -out=tfplan

# Python
python -m py_compile <file>.py

# Go
go build ./...
go vet ./...
golangci-lint run
```

---

**Questions?** Ask in daily standup (9am UTC, weekdays) or post in #techops-implementation Slack.

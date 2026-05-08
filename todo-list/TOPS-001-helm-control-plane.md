# TOPS-001: helm/control-plane/ — Helm Chart Copy & Audit

**Category**: Core Deployment | Helm Charts  
**Priority**: P0 (Production blocking)  
**Owner**: Platform Engineer  
**Effort**: 2h (confidence: high)  
**Timeline**: Phase 1, Week 1

---

## Problem Statement

The `helm/control-plane/` chart is missing from runtimeai_techops. Without it, the Control Plane service cannot be deployed declaratively via Helm; operators must manually edit K8s YAML manifests.

**Current State**: Directory does not exist  
**Desired State**: Full Helm chart in `helm/control-plane/` with Chart.yaml, values.yaml, templates/*, README.md  
**Blocking**: Cannot deploy Control Plane to rt19/rt01/rt02 without this chart

---

## Acceptance Criteria

- [ ] Directory `helm/control-plane/` exists with full chart structure
- [ ] `Chart.yaml` present with metadata (name, version, appVersion)
- [ ] `values.yaml` present with all configurable parameters
- [ ] Templates present: deployment.yaml, service.yaml, configmap.yaml, ingress.yaml (at minimum)
- [ ] `helm lint helm/control-plane/` passes with 0 errors, 0 warnings
- [ ] `helm template helm/control-plane/ > /tmp/manifest.yaml` succeeds
- [ ] `kubectl apply --dry-run=client -f /tmp/manifest.yaml` succeeds with no validation errors
- [ ] README.md documents: purpose, installation, configuration, troubleshooting
- [ ] No hardcoded secrets, passwords, or API keys in any template or values
- [ ] Chart supports both rt19 (staging) and rt01/rt02 (production) via values overrides
- [ ] PR created, reviewed, merged to dev
- [ ] Tested locally on developer machine (not in cluster)

---

## Detailed Requirements

### Inputs

**Source**: Copy from `runtimeai-enterprise/deployment/helm/control-plane/`

- Chart.yaml (name: control-plane, type: application)
- values.yaml (image repo, tag, replicas, resources, etc.)
- templates/NOTES.txt
- templates/deployment.yaml
- templates/service.yaml
- templates/configmap.yaml
- templates/ingress.yaml (if exists)
- templates/_helpers.tpl

### Outputs

**Files to create/modify**:
- [ ] `helm/control-plane/Chart.yaml`
- [ ] `helm/control-plane/values.yaml`
- [ ] `helm/control-plane/README.md` (new, explaining chart purpose + install steps)
- [ ] `helm/control-plane/templates/*.yaml` (copy all template files)

**Artifacts to commit**:
- All files above in single commit with message: `TOPS-001: Copy helm/control-plane/ chart from runtimeai-enterprise`

### Implementation Notes

- **Tainting strategy**: Keep source repo as reference, copy to techops as "deployable source of truth"
- **Values structure**: Separate `image.repository`, `image.tag`, `replicaCount`, `resources` into values.yaml (parameterizable)
- **Environment variants**: Use values-rt19.yaml, values-rt01.yaml (optional, can use base values.yaml + helm --set overrides)
- **Security**: Ensure all ConfigMap + Secret refs use K8s Secret objects, not inline values
- **Resource limits**: Match existing K8s manifests (e.g., 500m CPU, 512Mi memory for control-plane containers)

---

## Dependencies

- **Blocks**: TOPS-023 (Prometheus monitoring relies on this chart deployed)
- **Blocked By**: None
- **Related**: TOPS-002 (runtimeai-data-plane chart), TOPS-005 (mcp-gateway chart)

---

## Testing / Verification

```bash
# 1. Lint the chart
helm lint /Users/roshanshaik/work/runtimeai_techops/helm/control-plane/
# Expected: "1 chart(s) linted, 0 chart(s) failed"

# 2. Template render
helm template control-plane /Users/roshanshaik/work/runtimeai_techops/helm/control-plane/ > /tmp/test-manifest.yaml
# Expected: exit 0, /tmp/test-manifest.yaml contains valid YAML

# 3. Dry-run against K8s API
kubectl apply --dry-run=client -f /tmp/test-manifest.yaml
# Expected: no validation errors

# 4. Check for secrets in templates
grep -r "password\|secret\|api.key\|bearer" /Users/roshanshaik/work/runtimeai_techops/helm/control-plane/ --include="*.yaml"
# Expected: 0 matches (all sensitive values in K8s Secrets, not hard-coded)

# 5. Verify values.yaml structure
cat /Users/roshanshaik/work/runtimeai_techops/helm/control-plane/values.yaml | grep -E "image:|replicas:|resources:" | wc -l
# Expected: > 3 matches (parameterized correctly)
```

---

## Sign-Off

- [ ] Code complete + all acceptance criteria met
- [ ] Tested locally (`helm lint` + `helm template` + dry-run)
- [ ] PR created + merged to dev
- [ ] Chart renders templates error-free
- [ ] No hardcoded secrets in any file
- [ ] Related TOPS status updated (TOPS-023, etc.)

**Completed By**: [name + date]  
**Verified By**: [Platform Lead + date]

---

## Notes

- If source chart in runtimeai-enterprise has custom hooks, preserve them
- Check for CRDs (CustomResourceDefinitions) that might need separate installation
- Document any external dependencies (e.g., cert-manager, Prometheus Operator)

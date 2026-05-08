# TOPS-002: Helm Chart — RuntimeAI Data Plane

## Specification

Copy and validate Helm chart for RuntimeAI data-plane services from `runtimeai-enterprise/deployment/helm/runtimeai-data-plane/`.

## Acceptance Criteria

- [ ] Chart copied to `helm/runtimeai-data-plane/`
- [ ] `helm lint runtimeai-data-plane/` passes with 0 errors
- [ ] `helm template runtimeai-data-plane/` renders without errors
- [ ] `helm template --debug` shows valid YAML (no syntax errors)
- [ ] All required values documented in `values.yaml`
- [ ] Chart version bumped to 1.0.0
- [ ] README.md created with install instructions
- [ ] Committed to feature branch `TOPS-002-helm-data-plane`

## Effort Estimate

2 hours

## Dependencies

Blocked by: None
Blocks: TOPS-015, TOPS-016 (QA test runners)

## Implementation Notes

- Chart deploys data-plane services (e.g., cost-ledger, drift-engine, waf)
- Uses `namespace: rt19` default
- Supports environment variable overrides for image tags, replicas, resource requests
- Ensure all secrets referenced (db passwords, API keys) use K8s secretRef, not hardcoded values

## Verification

```bash
cd helm/runtimeai-data-plane
helm lint .
helm template . -f values.yaml | kubectl apply --dry-run=client -f -
```

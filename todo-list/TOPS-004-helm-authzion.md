# TOPS-004: Helm Chart — Authzion (Policy & Access Control)

## Specification

Copy Helm chart for Authzion (OPA + Envoy sidecar injector) from `runtimeai-enterprise/deployment/helm/authzion/`.

Authzion provides:
- Open Policy Agent (OPA) for fine-grained access control
- Envoy sidecar injector for traffic interception
- Rego policy compilation and caching
- JWT validation middleware

## Acceptance Criteria

- [ ] Chart copied to `helm/authzion/`
- [ ] `values.yaml` includes: opa_replicas, envoy_image, policy_update_interval
- [ ] `helm lint authzion/` passes
- [ ] `helm template authzion/ -f values.yaml` renders without errors
- [ ] All OPA policy files included in chart (embedded in ConfigMap)
- [ ] Sidecar injector webhook configured (namespace labels)
- [ ] Service account with cluster-role for policy enforcement
- [ ] Resource limits: OPA requests 512Mi, limits 1Gi
- [ ] Committed to feature branch `TOPS-004-helm-authzion`

## Effort Estimate

2 hours

## Dependencies

Blocked by: None
Blocks: TOPS-015, TOPS-016

## Implementation Notes

- Authzion runs 2-3 OPA replicas for HA
- Envoy injection is opt-in per namespace (add label `authzion.io/enable-injection=true`)
- OPA policies are compiled at startup; invalid syntax prevents pod from starting
- Sidecar adds ~100ms latency; only enabled for services requiring fine-grained access control

## Verification

```bash
helm lint helm/authzion/
helm template helm/authzion/ | kubectl apply --dry-run=client -f -
# Check OPA ConfigMap
helm template helm/authzion/ | grep -A 20 "kind: ConfigMap"
```

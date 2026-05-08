# TOPS-003: Helm Chart — Control Plane (Variant for Prod)

## Specification

Create production variant of Control Plane Helm chart from `runtimeai-enterprise/deployment/helm/control-plane/`. This variant includes:
- Multi-replica deployment with affinity rules (spread across nodes)
- Pod Disruption Budget (PDB) for high availability
- Resource limits/requests tuned for production load
- Horizontal Pod Autoscaler (HPA) configuration

## Acceptance Criteria

- [ ] Chart copied and variant created at `helm/control-plane/`
- [ ] `values-rt19.yaml` (staging, 2 replicas)
- [ ] `values-rt01-prod.yaml` (prod, 3+ replicas, PDB, HPA)
- [ ] `helm lint control-plane/` passes
- [ ] `helm template control-plane/ -f values-rt01-prod.yaml` renders valid YAML
- [ ] Pod affinity ensures replicas on different nodes
- [ ] PDB allows max 1 disruption
- [ ] HPA set to scale 3-10 replicas based on CPU 70%
- [ ] All image refs use imagePullSecrets (no plaintext registry creds)
- [ ] Committed to feature branch `TOPS-003-helm-control-plane-variant`

## Effort Estimate

2.5 hours

## Dependencies

Blocked by: None
Blocks: TOPS-015, TOPS-016

## Implementation Notes

- Control Plane is stateless; safe to scale horizontally
- Ensure RBAC service account has cluster-admin role (limited to control-plane namespace)
- Configure anti-affinity to prevent 2+ replicas on same node
- HPA requires metrics-server in kube-system namespace (add as prereq check)

## Verification

```bash
helm template helm/control-plane/ -f helm/control-plane/values-rt01-prod.yaml | \
  grep -A 5 "kind: PodDisruptionBudget"
kubectl apply -f <(helm template helm/control-plane/ -f helm/control-plane/values-rt01-prod.yaml) --dry-run=client
```

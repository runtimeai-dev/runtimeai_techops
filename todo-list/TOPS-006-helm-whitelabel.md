# TOPS-006: Helm Chart — White-Label (Customer On-Prem Install)

## Specification

Copy Helm chart for White-Label deployment from `runtimeai/deployment/helm/whitelabel/`. This chart supports customer on-premises installation with:
- All dependencies bundled (PostgreSQL, Redis, ingress)
- Minimal external service dependencies
- Simplified configuration for customer IT teams
- Support for offline/air-gapped deployments

## Acceptance Criteria

- [ ] Chart copied to `helm/whitelabel/`
- [ ] `values.yaml` includes: customer_name, domain, tls_cert_path, storage_class
- [ ] `helm lint whitelabel/` passes
- [ ] `helm template whitelabel/` renders without errors
- [ ] All components templated: services, jobs, migrations, webhooks
- [ ] Includes PostgreSQL subchart (or Helm repo reference)
- [ ] Includes Redis subchart (or Helm repo reference)
- [ ] TLS certificate configuration (customer provides cert/key)
- [ ] Committed to feature branch `TOPS-006-helm-whitelabel`

## Effort Estimate

2.5 hours

## Dependencies

Blocked by: None
Blocks: TOPS-015 (customer-facing QA), delivery/equinix (on-prem bundle)

## Implementation Notes

- White-label is self-contained; designed for airgapped deployment
- Requires customer to provide: TLS cert, domain, initial admin password
- Includes database initialization job (runs once at install)
- Supports multiple storage classes (local, nfs, managed storage)
- Documentation should include install, upgrade, backup procedures

## Verification

```bash
helm lint helm/whitelabel/
helm template helm/whitelabel/ --values helm/whitelabel/values-customer-template.yaml | kubectl apply --dry-run=client -f -
# Check for all required resources
helm template helm/whitelabel/ | grep "kind:" | sort | uniq -c
```

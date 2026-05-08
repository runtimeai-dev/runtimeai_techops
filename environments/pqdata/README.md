# Environment: pqdata

See parent directory README.md for general context.

## Key Files
- Kubernetes manifests: ../../k8s/pqdata/
- Helm values: ../../helm/pqdata/values.yaml
- Terraform: ../../terraform/
- Deploy script: ../../scripts/build/pqdata/build-push-deploy.sh

## Pre-Deploy Checklist
- [ ] Verify `.env` or secrets are NOT in git (blocked by .gitignore)
- [ ] Test K8s manifests: `kubectl apply --dry-run=client -f ...`
- [ ] Helm lint: `helm lint ../../helm/<chart>`
- [ ] Run QA: `cd ../../qa/pqdata && bash run_suite.sh`


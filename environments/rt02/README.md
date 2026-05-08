# Environment: rt02

See parent directory README.md for general context.

## Key Files
- Kubernetes manifests: ../../k8s/rt02/
- Helm values: ../../helm/rt02/values.yaml
- Terraform: ../../terraform/
- Deploy script: ../../scripts/build/rt02/build-push-deploy.sh

## Pre-Deploy Checklist
- [ ] Verify `.env` or secrets are NOT in git (blocked by .gitignore)
- [ ] Test K8s manifests: `kubectl apply --dry-run=client -f ...`
- [ ] Helm lint: `helm lint ../../helm/<chart>`
- [ ] Run QA: `cd ../../qa/rt02 && bash run_suite.sh`


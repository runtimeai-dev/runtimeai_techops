# Environment: rt01

See parent directory README.md for general context.

## Key Files
- Kubernetes manifests: ../../k8s/rt01/
- Helm values: ../../helm/rt01/values.yaml
- Terraform: ../../terraform/
- Deploy script: ../../scripts/build/rt01/build-push-deploy.sh

## Pre-Deploy Checklist
- [ ] Verify `.env` or secrets are NOT in git (blocked by .gitignore)
- [ ] Test K8s manifests: `kubectl apply --dry-run=client -f ...`
- [ ] Helm lint: `helm lint ../../helm/<chart>`
- [ ] Run QA: `cd ../../qa/rt01 && bash run_suite.sh`


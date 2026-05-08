# Environment: local

See parent directory README.md for general context.

## Key Files
- Kubernetes manifests: ../../k8s/local/
- Helm values: ../../helm/local/values.yaml
- Terraform: ../../terraform/
- Deploy script: ../../scripts/build/local/build-push-deploy.sh

## Pre-Deploy Checklist
- [ ] Verify `.env` or secrets are NOT in git (blocked by .gitignore)
- [ ] Test K8s manifests: `kubectl apply --dry-run=client -f ...`
- [ ] Helm lint: `helm lint ../../helm/<chart>`
- [ ] Run QA: `cd ../../qa/local && bash run_suite.sh`


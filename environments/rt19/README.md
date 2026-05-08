# Environment: rt19

See parent directory README.md for general context.

## Key Files
- Kubernetes manifests: ../../k8s/rt19/
- Helm values: ../../helm/rt19/values.yaml
- Terraform: ../../terraform/
- Deploy script: ../../scripts/build/rt19/build-push-deploy.sh

## Pre-Deploy Checklist
- [ ] Verify `.env` or secrets are NOT in git (blocked by .gitignore)
- [ ] Test K8s manifests: `kubectl apply --dry-run=client -f ...`
- [ ] Helm lint: `helm lint ../../helm/<chart>`
- [ ] Run QA: `cd ../../qa/rt19 && bash run_suite.sh`


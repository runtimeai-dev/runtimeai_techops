# Deployment Guide

## Quick Start

### rt19 (Staging)
```bash
# Redeploy control-plane
cd /Users/roshanshaik/work/runtimeai-enterprise
git checkout dev && git pull
bash deployment/scripts/rt19/build-push-deploy.sh control-plane
# Test: curl https://app.rt19.runtimeai.io/api/v1/health
```

### rt01/rt02 (Production)
```bash
# Create PR on dev → main first
# Merge PR
git checkout main && git pull
# Deploy from main
bash deployment/scripts/rt01/build-push-deploy.sh control-plane
```

### Full Deployment Checklist
- [ ] Code merged to dev
- [ ] QA tests passing
- [ ] PR created dev → main
- [ ] Team approved PR
- [ ] PR merged
- [ ] Pull main branch
- [ ] Run build-push-deploy.sh
- [ ] Verify health endpoints
- [ ] Check application logs
- [ ] Test user-facing features

# AEP Deployment Checklist

**Date**: May 6, 2026  
**Estimated Duration**: 30 minutes  
**Owner**: DevOps / SRE lead

---

## Pre-Deployment (1 hour before)

- [ ] **All tests passing locally**
  - Run: `bash qa_testing_local/run_suite.sh` in runtimeai-enterprise/
  - Verify: Exit code 0, all services marked [✓]
  - If failed: Do NOT proceed; fix tests first

- [ ] **Code reviewed and approved**
  - Check: GitHub PR has ✅ Approved review
  - Check: No outstanding review comments
  - If not: Get review approval before deploying

- [ ] **Secrets are rotated**
  - Check: JWT secrets not expired: `kubectl get secret -n aep -o jsonpath='{.items[0].metadata.creationTimestamp}'`
  - Check: DB password last rotated <90 days ago
  - Check: All secrets in aep-secrets ConfigMap match expectations
  - If expired: Rotate secrets before proceeding

- [ ] **DNS is configured**
  - Check: `nslookup aep-api.rt19.runtimeai.io` resolves
  - Check: Response is CNAME or A record (not NXDOMAIN)
  - Check: Certificate is not expired: `openssl s_client -connect aep-api.rt19.runtimeai.io:443 | grep "Not After"`

- [ ] **K8s manifests are valid**
  - Run: `kubectl apply -f deployment/scripts/rt19/k8s/13-aep-*.yaml --dry-run=client`
  - Verify: No errors in output
  - If errors: Fix manifests, commit, PR, then retry

- [ ] **Helm chart renders correctly**
  - Run: `helm template aep ./helm/aep/ --values ./helm/aep/values.yaml`
  - Verify: No ERR_ output, valid YAML
  - If errors: Fix values.yaml or templates

- [ ] **Backup is taken**
  - Run: `kubectl get all -n aep -o yaml > /tmp/aep-backup-$(date +%Y%m%d-%H%M).yaml`
  - Verify: File size >1MB (contains all resources)
  - Store: Upload to Azure storage or Git backup branch

- [ ] **Rollback plan is documented**
  - Write: How to rollback (git revert / kubectl rollout undo)
  - Write: Which service was changed
  - Write: Previous image tags to revert to
  - Example: "If pod crashes, run: kubectl rollout undo deployment/cost-control -n aep"

- [ ] **Status page is updated**
  - Note: Planned maintenance window (if applicable)
  - Notify: Status page shows "Scheduled Maintenance: AEP Deploy 10:00-10:30 UTC"
  - If critical change: Notify customers via email

---

## Deployment Phase (30 minutes)

- [ ] **Scale down replicas to 1 (to conserve resources during rollout)**
  - Run: `kubectl scale deployment/<service> -n aep --replicas=1` (for each changed service)
  - Verify: `kubectl get deployment -n aep | grep <service>`

- [ ] **Build and push new image**
  - Run: `bash deployment/scripts/rt19/build-push-deploy.sh <service>`
  - Verify: Image uploaded to ACR: `az acr repository show --name runtimeaicr --repository aep/<service>`
  - Verify: Image tag matches deploy manifest

- [ ] **Apply K8s manifests**
  - Run: `kubectl apply -f deployment/scripts/rt19/k8s/13-aep-<service>.yaml`
  - Verify: Deployment shows "1 replicas, 1 updated, 1 total"
  - Watch: `kubectl rollout status deployment/<service> -n aep --timeout=5m`

- [ ] **Verify pod is running**
  - Run: `kubectl get pod -l app=<service> -n aep -o wide`
  - Verify: Phase = Running, Ready = 1/1 (not CrashLoopBackOff)
  - If crash: `kubectl logs <pod-name> -n aep | head -50` to diagnose

- [ ] **Verify health endpoint**
  - Run: `kubectl port-forward -n aep svc/<service> 8xxx:8xxx &`
  - Run: `curl http://localhost:8xxx/healthz`
  - Verify: Response 200 OK or 204 No Content

- [ ] **Test via gateway API (external)**
  - Run: `ADMIN_SECRET=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv) && curl -X POST https://aep-api.rt19.runtimeai.io/api/admin/impersonate -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" -d '{"tenant_id":"equinix-demo"}' | jq .token -r | xargs -I {} curl -H "Authorization: Bearer {}" https://aep-api.rt19.runtimeai.io/api/<service>/health`
  - Verify: 200 response (service is publicly accessible)

- [ ] **Run full QA test suite**
  - Run: `bash qa_testing_local/run_suite.sh`
  - Verify: All 14 services pass health checks
  - Verify: Cross-service DNS resolution works
  - If failed: Rollback immediately with `kubectl rollout undo deployment/<service> -n aep`

- [ ] **Check metrics are flowing**
  - Port-forward prometheus: `kubectl port-forward -n aep svc/prometheus 9090:9090 &`
  - Navigate: http://localhost:9090/graph
  - Search: `http_requests_total{service="<service>"}`
  - Verify: Graph shows data (not empty)

- [ ] **Scale back up to target replicas (if needed)**
  - Run: `kubectl scale deployment/<service> -n aep --replicas=2` (or per HPA target)
  - Verify: Both pods Running: `kubectl get pod -l app=<service> -n aep`
  - Watch HPA if enabled: `kubectl get hpa <service> -n aep -w`

- [ ] **Verify no new alerts firing**
  - Check: AlertManager not showing new critical/high alerts
  - Check: Slack channel #aep-alerts is quiet (no new errors)
  - If alerts: Investigate and fix or rollback

---

## Post-Deployment (15 minutes after)

- [ ] **Monitor error rate**
  - Check Grafana: aep_error_rate metric
  - Verify: <0.1% error rate (or previous baseline)
  - If spike: Wait 5 min (HPA may still be scaling), then investigate

- [ ] **Check pod restarts**
  - Run: `kubectl get pod -n aep -o wide | grep <service>`
  - Verify: RESTARTS column is 0 (no unexpected restarts)
  - If >0: Check logs for startup issues

- [ ] **Verify request latency**
  - Check Grafana: http_request_duration_seconds_bucket
  - Verify: P99 latency <500ms (or previous baseline)
  - If slow: Check pod resources, DB latency

- [ ] **Test end-to-end flow**
  - Run: A critical user journey (e.g., Cost Control agent audit → memory vault lookup → PII tokenization)
  - Verify: Request succeeds, data is returned, no errors
  - If failed: Investigate cross-service communication

- [ ] **Notify stakeholders**
  - Slack: Post to #aep-alerts: "✅ AEP <service> deployed successfully (image: <tag>). Metrics healthy."
  - Email: If customer-impacting change, send notification: "AEP service upgraded, no downtime"

- [ ] **Document what was deployed**
  - Create commit message with deployment details:
    ```
    OPER_RT19-103e: Deploy <service> v1.2.3
    
    - Fix: [issue]
    - Change: [behavior change]
    - Testing: All tests pass, 0 regressions
    - Metrics: p99 latency <500ms, error rate <0.1%
    ```
  - Reference: PR link, commit hash, deployed image tag

- [ ] **Update status page to "All Systems Operational"**
  - Remove maintenance banner
  - Clear any previous incident notes
  - Confirm deploy went well in status page history

---

## Rollback Checklist (if needed)

- [ ] **Immediately stop further deployments**
  - Alert: Page SRE on-call
  - Slack: Post: "🚨 AEP <service> deploy FAILED, rolling back"

- [ ] **Revert to previous image**
  - Run: `kubectl rollout undo deployment/<service> -n aep`
  - Verify: `kubectl rollout status deployment/<service> -n aep --timeout=5m`

- [ ] **Verify health post-rollback**
  - Run: `curl http://localhost:8xxx/healthz` (port-forward first)
  - Verify: 200 response

- [ ] **Run test suite**
  - Run: `bash qa_testing_local/run_suite.sh`
  - Verify: All tests pass again

- [ ] **Notify stakeholders**
  - Slack: "✅ Rollback complete, service restored"
  - Post-mortem: Schedule review of what failed

- [ ] **Fix root cause**
  - Debug: Why did deploy fail?
  - Fix: Code, tests, or deployment config
  - Test locally: Verify fix before re-deploying

---

## Automated Checks (build-push-deploy.sh does these)

The deployment script automatically runs:

```bash
# 1. Validate manifests
kubectl apply -f <manifest> --dry-run=client

# 2. Build image (ARM64)
docker buildx build --platform linux/arm64 ...

# 3. Push to ACR
docker push runtimeaicr.azurecr.io/aep/<service>:latest

# 4. Update deployment
kubectl set image deployment/<service> -n aep <service>=runtimeaicr.azurecr.io/aep/<service>:${TAG}

# 5. Monitor rollout
kubectl rollout status deployment/<service> -n aep --timeout=10m

# 6. Run post-deploy tests
bash qa_testing_local/rt19_full_platform_test.sh https://aep-api.rt19.runtimeai.io
```

---

## Success Criteria

✅ Deploy is successful if:
- Pod phase is Running
- Health endpoint responds 200
- Gateway API accessible
- Test suite passes 100%
- Error rate <0.1%
- P99 latency <500ms
- No new alerts
- No pod restarts

❌ Deploy failed if:
- Pod stuck in CrashLoopBackOff >3 min
- Health endpoint returns 500
- Test suite fails
- Error rate >1%
- AlertManager fires critical alert

---

**Last Updated**: May 6, 2026  
**Next Review**: After 3rd deployment  
**Owner**: DevOps Lead

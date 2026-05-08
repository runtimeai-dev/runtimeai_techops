# RuntimeAI Platform — Troubleshooting Guide

**Version**: 1.0.0  
**Date**: 2026-03-27  
**Classification**: Confidential — Equinix Trial Delivery

---

## Quick Diagnostics

```bash
# Check all pod status
kubectl get pods -n rt19 -o wide

# Check for CrashLoopBackOff or Error pods
kubectl get pods -n rt19 --field-selector status.phase!=Running

# Check events for recent issues
kubectl get events -n rt19 --sort-by='.lastTimestamp' | tail -20

# Check resource usage
kubectl top pods -n rt19
```

---

## Common Issues

### 1. Pod CrashLoopBackOff

**Symptoms**: Pod keeps restarting, status shows `CrashLoopBackOff`

**Diagnosis**:
```bash
kubectl logs deployment/<SERVICE_NAME> -n rt19 --previous
```

**Common causes**:
| Cause | Fix |
|-------|-----|
| Database connection failed | Verify `rt19-db-secret` has correct `DATABASE_URL` |
| Redis connection failed | Verify `rt19-app-secrets` has correct `REDIS_URL` |
| Port conflict | Check another service isn't using the same port |
| OOM killed | Increase memory limits in K8s manifest |

### 2. Database Connection Issues

**Symptoms**: `Failed to connect to DB` or `connection refused` in logs

```bash
# Test DB connectivity from inside cluster
kubectl run pg-test -n rt19 --rm -it --image=postgres:16 -- \
  psql "postgres://authzion:<PASSWORD>@<DB_HOST>:5432/authzion"

# Check DB secret
kubectl get secret rt19-db-secret -n rt19 -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

### 3. Redis Connection Issues

**Symptoms**: Kill switch not working, rate limiting broken

```bash
# Test Redis connectivity
kubectl run redis-test -n rt19 --rm -it --image=redis:7 -- \
  redis-cli -h <REDIS_HOST> -p 6379 PING

# Flush rate limiting after 429 errors
kubectl exec -n rt19 deploy/control-plane -- redis-cli -h <REDIS_HOST> FLUSHALL
```

### 4. RLS (Row-Level Security) Violations

**Symptoms**: `new row violates row-level security policy` errors

```bash
# Check which tables have RLS enabled
kubectl exec -n rt19 deploy/control-plane -- env PGPASSWORD=<PASSWORD> \
  psql -U authzion -d authzion -c "SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND rowsecurity=true;"

# Verify tenant context is being set
# Look for "RLS violation" in control-plane logs
kubectl logs deployment/control-plane -n rt19 | grep -i "RLS\|row-level"
```

### 5. Audit Chain Integrity Failure

**Symptoms**: `/api/audit/verify` returns `{"valid": false}`

```bash
# Check unprocessed audit logs
kubectl exec -n rt19 deploy/control-plane -- env PGPASSWORD=<PASSWORD> \
  psql -U authzion -d authzion -c "SELECT COUNT(*) FROM audit_logs WHERE processed = FALSE;"

# Check for Poller errors
kubectl logs deployment/control-plane -n rt19 | grep -i "Audit Poller"

# Check evidence chain
kubectl exec -n rt19 deploy/control-plane -- env PGPASSWORD=<PASSWORD> \
  psql -U authzion -d authzion -c "SELECT COUNT(*) FROM audit_evidence WHERE tenant_id='<TENANT_ID>';"
```

### 6. Health Check Failures

**Symptoms**: Service shows `0/1` ready

```bash
# Check specific readiness probe
kubectl describe pod <POD_NAME> -n rt19 | grep -A5 "Readiness"

# Port-forward and test manually
kubectl port-forward -n rt19 deploy/<SERVICE_NAME> 9999:<PORT> &
curl http://localhost:9999/healthz
```

---

## Service-Specific Troubleshooting

### Control Plane (:8080)
```bash
kubectl logs deployment/control-plane -n rt19 -f
# Common issues: DB migration failures, OPA bundle errors
```

### Flow Enforcer (:8083)
```bash
kubectl logs deployment/flow-enforcer -n rt19 -f
# Common issues: Wasm contextID errors → check WASM build
# Fix: kubectl rollout restart deployment/flow-enforcer -n rt19
```

### Discovery (:5090)
```bash
kubectl logs deployment/discovery -n rt19 -f
# Common issues: Scanner timeout, Python venv issues
# Fix: pip install -r requirements.txt inside container
```

### eSign Service (:3001)
```bash
kubectl logs deployment/esign-service -n rt19 -f
# Common issues: SendGrid API key, storage path permissions
```

---

## Network Troubleshooting

### DNS Resolution
```bash
# Test internal DNS resolution
kubectl run dns-test -n rt19 --rm -it --image=busybox -- nslookup control-plane.rt19.svc.cluster.local

# Test identity-dns DoH
kubectl exec -n rt19 deploy/identity-dns -- curl -s http://localhost:8053/health
```

### TLS Issues
```bash
# Check certificate expiry
kubectl get certificate -n rt19
openssl s_client -connect <YOUR_ENDPOINT>:443 2>/dev/null | openssl x509 -noout -dates

# Check ingress TLS config
kubectl describe ingress -n rt19
```

### Inter-Service Communication
```bash
# Test CP → DP connectivity
kubectl exec -n rt19 deploy/control-plane -- curl -s http://drift-engine:8099/healthz
kubectl exec -n rt19 deploy/control-plane -- curl -s http://vendor-wrapper:8103/healthz
```

---

## Log Locations

| Service | Command |
|---------|---------|
| All services | `kubectl logs deployment/<NAME> -n rt19` |
| Previous crash | `kubectl logs deployment/<NAME> -n rt19 --previous` |
| Follow logs | `kubectl logs deployment/<NAME> -n rt19 -f` |
| All pods | `kubectl logs -l tier=platform -n rt19 --max-log-requests=20` |

---

## Hybrid Deployment (DEPLOY_MODE=dataplane-only) Troubleshooting

### ErrImagePull / ImagePullBackOff on all DP pods

**Cause**: ACR pull secret format incorrect, or wrong username.

**Diagnosis**:
```bash
kubectl describe pod <POD_NAME> -n eqix-rt19 | grep -A5 "Failed\|Error\|Back-off"
```

**Fix**: Re-create the pull secret with the correct ACR token name:
```bash
kubectl delete secret runtimeai-pull-secret -n eqix-rt19
kubectl create secret docker-registry runtimeai-pull-secret \
  --docker-server=runtimeaicr.azurecr.io \
  --docker-username=dp-pull-token \        # ACR token name (NOT SP ID)
  --docker-password=<ACR_TOKEN_PASSWORD> \
  -n eqix-rt19
kubectl rollout restart deployment -n eqix-rt19
```

> ⚠️ If using ACR tokens (created via `az acr token create`), `REGISTRY_USER` must be the **token name** (e.g. `dp-pull-token`), not the service principal ID (`00000000-0000-0000-0000-000000000000`).

### vendor-wrapper 0/1 (Readiness probe failing)

**Cause**: Manifest was generated with wrong port (8095 vs actual 8103).

**Fix** (temporary):
```bash
kubectl patch deployment vendor-wrapper -n eqix-rt19 \
  --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/ports/0/containerPort","value":8103},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":8103}
  ]'
```

**Permanent fix**: Ensure you are using `configure-environment.sh` from runtimeai#367 or later.

### identity-dns 0/1 (Readiness probe failing)

**Cause**: Manifest was generated with wrong port (8096 vs actual 8053) or wrong probe path (`/healthz` vs `/health`).

**Fix** (temporary):
```bash
kubectl patch deployment identity-dns -n eqix-rt19 \
  --type=json -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/ports/0/containerPort","value":8053},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":8053},
    {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/health"}
  ]'
```

**Permanent fix**: Ensure you are using `configure-environment.sh` from runtimeai#367 or later.

### bundle-cache failing to pull OPA bundles from CP

**Symptoms**: bundle-cache logs show `404` or `403` on bundle fetch; DP policies stale.

**Check logs**:
```bash
kubectl logs deployment/bundle-cache -n eqix-rt19 | grep -i "bundle\|ERROR\|403\|404"
```

**Common causes**:

| Error | Cause | Fix |
|-------|-------|-----|
| `CP returned HTTP 403` | `ADMIN_SECRET` missing or wrong | Verify `rt19-cp-connectivity` secret contains correct `ADMIN_SECRET` |
| `CP returned HTTP 404` | Bundle path wrong or tenant not provisioned | Verify tenant exists on CP; path must be `/opa/bundles/{tenant_id}/bundle.tar.gz` |
| `ADMIN_SECRET is required` | `ADMIN_SECRET` not in environment | Re-run `configure-environment.sh` with `ADMIN_SECRET` set in `.env` |

**Verify secret**:
```bash
kubectl get secret rt19-cp-connectivity -n eqix-rt19 \
  -o jsonpath='{.data.ADMIN_SECRET}' | base64 -d
# Should match the value from: kubectl get secret rt19-app-secrets -n rt19 -o jsonpath='{.data.ADMIN_SECRET}' | base64 -d
```

**Test bundle endpoint directly**:
```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "X-RuntimeAI-Admin-Secret: <ADMIN_SECRET>" \
  https://api.rt19.runtimeai.io/opa/bundles/equinix-demo/bundle.tar.gz
# Expected: 200
```

### validate_dp_cp_connectivity.sh failures

**Run the validator**:
```bash
NAMESPACE=eqix-rt19 \
CONTROL_PLANE_URL=https://api.rt19.runtimeai.io \
INTERNAL_SERVICE_TOKEN=<token> \
ADMIN_SECRET=<secret> \
TENANT_ID=equinix-demo \
bash validate_dp_cp_connectivity.sh
```

| Test | Failure | Fix |
|------|---------|-----|
| CP /health → not 200 | CP unreachable | Check egress firewall; verify `CONTROL_PLANE_URL` |
| OPA bundle → 401/403 | Wrong `ADMIN_SECRET` | Re-obtain from RuntimeAI; update `rt19-cp-connectivity` secret |
| OPA bundle → 404 | Tenant not provisioned on CP | Contact RuntimeAI to provision `equinix-demo` tenant |
| Audit → 401 | Wrong `INTERNAL_SERVICE_TOKEN` | Re-obtain from RuntimeAI; update `rt19-cp-connectivity` secret |
| Pod not Running | Readiness probe fail or image pull | See sections above |

### rt19-cp-connectivity secret missing or wrong values

**Re-create the secret**:
```bash
kubectl delete secret rt19-cp-connectivity -n eqix-rt19 2>/dev/null || true
kubectl create secret generic rt19-cp-connectivity -n eqix-rt19 \
  --from-literal=CONTROL_PLANE_URL=https://api.rt19.runtimeai.io \
  --from-literal=INTERNAL_SERVICE_TOKEN=<token> \
  --from-literal=ADMIN_SECRET=<secret> \
  --from-literal=BUNDLE_CACHE_URL=https://api.rt19.runtimeai.io
kubectl rollout restart deployment/bundle-cache deployment/flow-enforcer deployment/cost-ledger -n eqix-rt19
```

---

## Recovery Procedures

### Full Service Restart
```bash
kubectl rollout restart deployment -n rt19
kubectl rollout status deployment -n rt19 --timeout=300s
```

### DP Full Restart (Hybrid Mode)
```bash
kubectl rollout restart deployment -n eqix-rt19
kubectl rollout status deployment -n eqix-rt19 --timeout=300s
kubectl get pods -n eqix-rt19
```

### Database Recovery
```bash
# From backup
pg_restore -h <DB_HOST> -U authzion -d authzion < backup.sql

# Re-run migrations (idempotent)
kubectl rollout restart deployment/control-plane -n rt19
```

### Redis Recovery
```bash
# Redis data is ephemeral (sessions, rate limits, kill switch state)
# Restarting Redis clears all data — services auto-recover
kubectl rollout restart deployment/redis -n rt19
```

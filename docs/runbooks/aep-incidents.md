# AEP Operational Runbooks

**Date**: May 6, 2026  
**For**: AEP Phase 1-4 production incidents  
**MTTR Target**: <30 minutes

---

## Incident 1: Pod CrashLoopBackOff

**Symptoms**: 
- Pod status shows `CrashLoopBackOff`
- Logs show repeated restart attempts
- Service unavailable for <5 minutes, then briefly available

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n aep
kubectl logs <pod-name> -n aep --tail=100
kubectl logs <pod-name> -n aep --previous  # If current logs empty
```

**Root Causes** (in order of likelihood):
1. Startup panics (nil pointer, bad config) → See logs for panic trace
2. Liveness probe failing → Check health endpoint: `kubectl exec <pod> -- curl localhost:PORT/healthz`
3. Database connection refused → Check `aep-postgres` Pod Ready status: `kubectl get pod -n aep -l app=aep-postgres`
4. Secrets missing → `kubectl get secrets -n aep | grep aep-`

**Remediation**:
- **If panics in logs**: Check recent code deploy; rollback with `kubectl rollout undo deployment/<service> -n aep`
- **If health probe failing**: Service may be overloaded; scale up with `kubectl scale deployment/<service> -n aep --replicas=3`
- **If postgres down**: Restart postgres: `kubectl delete pod -n aep -l app=aep-postgres` (StatefulSet redeploys)
- **If secrets missing**: Create them: `kubectl create secret generic aep-secrets -n aep --from-literal=db-password=$PASSWORD`

**Verify Fix**:
- Pod phase is `Running`: `kubectl get pod <pod-name> -n aep -o wide`
- Health endpoint responds: `curl https://aep-api.rt19.runtimeai.io/api/<service>/healthz -H "Authorization: Bearer $TOKEN"`

**MTTR**: 2-5 minutes | **Escalate**: If >3 restarts in 5 min, page SRE

---

## Incident 2: High Error Rate (>1%)

**Symptoms**:
- Grafana shows error rate spike >1%
- Alert fires: "AEP Error Rate High"
- User reports seeing 500 errors

**Diagnosis**:
```bash
# Check which service is erroring
kubectl logs -n aep -l app=<service> --tail=200 | grep ERROR

# Count errors by type
kubectl logs -n aep -l app=cost-control --tail=500 | grep -c "error\|ERROR\|fail"

# Check metrics
kubectl port-forward -n aep svc/<service> 9090:9090 &
curl http://localhost:9090/metrics | grep http_requests_total
```

**Root Causes** (in order):
1. Recent code deploy introduced bug → Check last 3 commits: `git log -3 --oneline`
2. Database query timeout → Check postgres CPU/memory: `kubectl top pods -n aep`
3. Upstream service down (fraud-shield calling cost-control) → Check circuit breaker logs
4. Rate limiting triggered → Check response headers: `curl -v ... | grep X-Rate`

**Remediation**:
- **If bad deploy**: Immediate rollback with `kubectl rollout undo deployment/<service> -n aep`
- **If DB slow**: Scale postgres: `kubectl scale statefulset aep-postgres -n aep --replicas=2` or `kubectl patch statefulset aep-postgres -n aep -p '{"spec":{"resources":{"requests":{"memory":"512Mi"}}}}'`
- **If upstream down**: Wait 30 sec for HPA to scale; if still down, page on-call for upstream team
- **If rate-limited**: Check if legitimate traffic spike (check request logs) or DDoS (block IP if suspicious)

**Verify Fix**:
- Error rate drops <1%: `kubectl logs -n aep -l app=<service> --tail=1000 | grep -c "error" | awk '{print ($1/1000)*100}'`
- Health checks pass: `bash qa_testing_local/run_suite.sh` returns 0

**MTTR**: 5-15 minutes | **Escalate**: If >5% error rate for >10 min, page SRE

---

## Incident 3: Slow Responses (P99 Latency >500ms)

**Symptoms**:
- Grafana shows p99 latency spike
- Alert fires: "AEP P99 Latency High"
- Customers report slow API responses

**Diagnosis**:
```bash
# Get latency breakdown from traces (Jaeger)
# URL: http://localhost:16686 (port-forward: kubectl port-forward -n aep svc/jaeger 16686:16686)

# Check service CPU/memory utilization
kubectl top pods -n aep -l app=<service>

# Check if HPA is scaling
kubectl get hpa -n aep
kubectl describe hpa <service> -n aep | grep -A 5 "Current number of replicas"

# Check slow queries in postgres logs
kubectl logs -n aep -l app=aep-postgres --tail=200 | grep "duration:"
```

**Root Causes** (in order):
1. Slow database queries (missing index) → Check EXPLAIN plans in postgres
2. Service under-scaled (HPA lagging) → Check HPA metrics: `kubectl get hpa <service> -n aep -o wide`
3. Upstream service slow → Use traces to identify bottleneck
4. Resource contention (node at capacity) → Check node CPU: `kubectl top nodes`

**Remediation**:
- **If slow queries**: Add index: `kubectl exec -n aep aep-postgres-0 -- psql -U aep -d aep -c "CREATE INDEX idx_tenant_created ON <table>(tenant_id, created_at)"`
- **If under-scaled**: Manually scale: `kubectl scale deployment/<service> -n aep --replicas=5`
- **If upstream slow**: Check upstream service status (page their team)
- **If node at capacity**: Evict non-essential pods or add nodes: `az aks nodepool add --resource-group rt19-rg --cluster-name rt19 --name aep2 --node-count 3`

**Verify Fix**:
- P99 latency <500ms: Check Grafana dashboard
- Response times normal: `time curl https://aep-api.rt19.runtimeai.io/api/cost-control/agents -H "Authorization: Bearer $TOKEN"`

**MTTR**: 10-20 minutes | **Escalate**: If >1 second p99, page SRE

---

## Incident 4: Pod Memory Exhaustion / OOMKilled

**Symptoms**:
- Pod status shows `OOMKilled` or `OOMKilledRestarting`
- Memory usage at 100%
- Service becomes unavailable after 5-10 minutes

**Diagnosis**:
```bash
kubectl describe pod <pod-name> -n aep | grep -A 5 "State:"
kubectl top pod <pod-name> -n aep

# Check if it's a query result set issue
kubectl logs <pod-name> -n aep | grep "memory\|OOM\|rows"
```

**Root Causes**:
1. Memory request too low → Increase in manifest
2. Large query result set not paginated → Code bug in list endpoint
3. Memory leak in service code → Check for goroutine leaks

**Remediation**:
- **Quick fix**: Increase memory request in manifest and redeploy: `kubectl patch deployment/<service> -n aep -p '{"spec":{"template":{"spec":{"containers":[{"name":"<service>","resources":{"requests":{"memory":"512Mi"}}}]}}}}'`
- **Permanent fix**: Update manifest file, commit, and redeploy
- **If list endpoint**: Implement cursor pagination with limit=100; EXPLAIN ANALYZE the query

**Verify Fix**:
- Pod stays Running: `kubectl get pod <pod-name> -n aep -w` (watch for 2 minutes)
- Memory usage stable: `kubectl top pod <pod-name> -n aep`

**MTTR**: 5-10 minutes | **Escalate**: If memory request >2Gi, contact platform team

---

## Incident 5: JWT Authentication Failures

**Symptoms**:
- Requests return 401 Unauthorized
- Alert fires: "AEP JWT Errors High"
- All endpoints affected equally
- Users cannot log in or use API

**Diagnosis**:
```bash
# Get JWT token
ADMIN_SECRET=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv)
curl -X POST https://api.rt19.runtimeai.io/api/admin/impersonate \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d '{"tenant_id":"test-tenant"}' | jq .

# Decode token to check claims
jq -R 'split(".") | .[1] | @base64d | fromjson' <<< "$TOKEN"

# Check if JWT secret is rotated
kubectl get secret -n aep -l app=<service> -o jsonpath='{.items[*].data.jwt-secret}' | base64 -d
```

**Root Causes**:
1. JWT secret rotated but service didn't reload → Restart service: `kubectl rollout restart deployment/<service> -n aep`
2. Token expired → Client needs to request new token
3. Issuer URL mismatch → Check env var `JWT_ISSUER` in deployment
4. Algorithm mismatch (RS256 vs HS256) → Check JWT signing config

**Remediation**:
- **If secret rotated**: `kubectl rollout restart deployment/<service> -n aep` (pick up new secret from mount)
- **If issuer wrong**: Update env in manifest: `kubectl set env deployment/<service> -n aep JWT_ISSUER=https://auth.rt19.runtimeai.io`
- **If expired token**: Client should request new token via `/api/auth/login`

**Verify Fix**:
- Get new token and test: `curl -X POST ... /api/cost-control/agents -H "Authorization: Bearer $TOKEN"`
- Health endpoint accessible: `curl https://aep-api.rt19.runtimeai.io/api/<service>/healthz`

**MTTR**: 5-10 minutes | **Escalate**: If auth-service down, page SRE

---

## Incident 6: Budget Alert / High Cost Spike

**Symptoms**:
- Cost Control alert fires: "Tenant budget exceeded"
- Alert fires: "Cost spike detected"
- Customer reports unexpected charges

**Diagnosis**:
```bash
# Get recent cost ledger entries
kubectl exec -n aep aep-postgres-0 -- psql -U aep -d aep -c \
  "SELECT tenant_id, SUM(cost_usd) FROM cost_ledger WHERE created_at > NOW() - INTERVAL '1 hour' GROUP BY tenant_id ORDER BY SUM(cost_usd) DESC LIMIT 10;"

# Check which service generated the costs
kubectl logs -n aep -l app=cost-control --tail=500 | grep -i "cost\|charge"

# Check if it's from a specific agent
curl -H "Authorization: Bearer $TOKEN" https://aep-api.rt19.runtimeai.io/api/cost-control/agents | jq '.[] | {agent_id, cost_24h}'
```

**Root Causes**:
1. Agent running in a loop (infinite calls) → Check agent logs and pause it
2. Model price changed (token cost increase) → Check vendor wrapper logs
3. User accidentally deployed high-volume agent → Check deployment logs
4. Legitimate spike (high volume = expected) → Review with product team

**Remediation**:
- **If runaway agent**: Pause agent immediately: `curl -X PATCH https://aep-api.rt19.runtimeai.io/api/cost-control/agents/<agent_id> -H "Authorization: Bearer $TOKEN" -d '{"status":"paused"}'`
- **If price changed**: Update vendor-wrapper pricing cache: `kubectl rollout restart deployment/vendor-wrapper -n rt19`
- **If legitimate**: Adjust budget via Cost Control API or notify customer

**Verify Fix**:
- Cost rate returns to baseline: Monitor cost ledger
- Agent is paused: `curl https://aep-api.rt19.runtimeai.io/api/cost-control/agents/<agent_id> | jq .status`

**MTTR**: 10-15 minutes | **Escalate**: If >$10k/day spike, page finance team

---

## Runbook Summary

| Incident | Diagnosis Time | Fix Time | MTTR | Escalation |
|----------|---|---|---|---|
| CrashLoopBackOff | 2 min | 2-3 min | 5 min | Pod won't start after 3 retries |
| High Error Rate | 3 min | 3-10 min | 15 min | >5% error rate for >10 min |
| Slow Responses | 5 min | 5-15 min | 20 min | >1 second p99 latency |
| Memory OOM | 2 min | 3-5 min | 10 min | Memory request >2Gi |
| JWT Failures | 3 min | 2-5 min | 10 min | Auth service down |
| Cost Spike | 5 min | 5-10 min | 15 min | >$10k/day spike |

---

## Post-Incident Actions

1. **Check error logs** for patterns
2. **Update alert thresholds** if false positives
3. **Document root cause** in incident ticket
4. **Add test case** to prevent recurrence
5. **Notify stakeholders** of resolution

---

**Last Updated**: May 6, 2026  
**Next Review**: May 13, 2026 (weekly)

# Troubleshooting Guide

## Common Issues & Solutions

### 1. Service Pod CrashLooping
**Symptoms**: Pod restarting repeatedly
**Root Causes**: OOMKilled, readiness probe failing, bad config
**Quick Fix**:
```bash
kubectl logs -n rt19 pod/<name> --tail=50
kubectl describe pod -n rt19 <name>
# If OOMKilled: increase memory request
kubectl set resources deployment/<service> --limits=memory=2Gi -n rt19
```

### 2. Database Connection Pool Exhausted
**Symptoms**: "too many connections" errors
**Quick Fix**:
```bash
psql -h rt19-db -c "SELECT count(*) FROM pg_stat_activity;"
# Kill idle connections
psql -h rt19-db -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state='idle' AND query_start < now() - interval '1 hour';"
```

### 3. High Latency / Slow Requests
**Symptoms**: p99 latency > 500ms
**Debug**:
```bash
# Check pod metrics
kubectl top pod -n rt19 | grep <service>
# Check Prometheus
curl http://prometheus:9090/api/v1/query?query=histogram_quantile(0.99,http_request_duration_seconds_bucket{job=\"<service>\"})
```

### 4. Out of Disk Space
**Symptoms**: WriteConflict errors, failed writes
**Quick Fix**:
```bash
kubectl df-pvc  # Check PVC usage
# If PVC full: scale down pod, delete data, restart
kubectl scale deployment/<service> --replicas=0 -n rt19
# Manual cleanup or resize PVC
```

### 5. Certificate Expiration
**Symptoms**: TLS handshake failures
**Check**:
```bash
kubectl get certificate -A
# cert-manager auto-renews; check cert-manager logs if failing
kubectl logs -n cert-manager deployment/cert-manager -f | grep error
```

See incident response playbooks for detailed procedures.

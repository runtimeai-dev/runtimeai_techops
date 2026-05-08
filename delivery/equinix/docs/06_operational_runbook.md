# RuntimeAI Platform — Operational Runbook

**Version**: 1.0.0  
**Date**: 2026-03-27  
**Classification**: Confidential — Equinix Trial Delivery

---

## Backup Procedures

### PostgreSQL Backup

```bash
# Full database dump (recommended: daily)
pg_dump -h <DB_HOST> -U authzion -d authzion -Fc -f runtimeai_backup_$(date +%Y%m%d).dump

# Schema only
pg_dump -h <DB_HOST> -U authzion -d authzion --schema-only -f schema_$(date +%Y%m%d).sql

# Specific tables (audit evidence — critical for compliance)
pg_dump -h <DB_HOST> -U authzion -d authzion -t audit_evidence -t audit_logs -Fc \
  -f audit_backup_$(date +%Y%m%d).dump
```

### Redis Snapshot

```bash
# Trigger RDB snapshot
redis-cli -h <REDIS_HOST> BGSAVE

# Copy RDB file
kubectl cp rt19/<REDIS_POD>:/data/dump.rdb ./redis_backup_$(date +%Y%m%d).rdb
```

### Backup Schedule

| Component | Frequency | Retention | Method |
|-----------|-----------|-----------|--------|
| PostgreSQL (full) | Daily | 30 days | `pg_dump` to object storage |
| PostgreSQL (WAL) | Continuous | 7 days | WAL archiving |
| Redis (RDB) | Every 6 hours | 7 days | `BGSAVE` |
| K8s manifests | On change | Git history | Version controlled |

---

## Upgrade Procedure

### Rolling Update (Zero-Downtime)

```bash
# 1. Pull latest images
# For Azure:
az acr login --name runtimeaiprod
docker pull runtimeaiprod.azurecr.io/<SERVICE>:latest

# For air-gapped: load new images from tar
docker load -i <SERVICE>.tar

# 2. Rolling restart all services
kubectl rollout restart deployment -n rt19

# 3. Wait for rollout
kubectl rollout status deployment -n rt19 --timeout=300s

# 4. Verify health
for svc in control-plane dashboard auth-service; do
  kubectl rollout status deployment/$svc -n rt19
done
```

### Database Migration

Migrations run automatically when the control-plane starts. They are idempotent (safe to re-run).

```bash
# Check migration status
kubectl logs deployment/control-plane -n rt19 | grep "migration"
```

---

## Rollback Procedure

```bash
# Rollback single service
kubectl rollout undo deployment/<SERVICE_NAME> -n rt19

# Rollback to specific revision
kubectl rollout history deployment/<SERVICE_NAME> -n rt19
kubectl rollout undo deployment/<SERVICE_NAME> -n rt19 --to-revision=<N>

# Rollback all services (nuclear option)
kubectl rollout undo deployment -n rt19
```

---

## Scaling Guidance

### Horizontal Scaling

| Service | Can Scale? | Notes |
|---------|-----------|-------|
| control-plane | ✅ Yes (2+ replicas) | Stateless, uses connection pooling |
| dashboard | ✅ Yes | Stateless static files |
| flow-enforcer | ✅ Yes | Each replica handles independent traffic |
| data-proxy | ✅ Yes | Stateless proxy |
| auth-service | ✅ Yes | Stateless JWT validation |
| drift-engine | ⚠️ Limited | Ensure only one consumes from Redis pub/sub |
| identity-dns | ✅ Yes | Stateless DNS resolver |

```bash
# Scale a service
kubectl scale deployment/<SERVICE_NAME> -n rt19 --replicas=3

# Auto-scale based on CPU
kubectl autoscale deployment/<SERVICE_NAME> -n rt19 \
  --min=2 --max=5 --cpu-percent=70
```

---

## Monitoring Setup

### Prometheus

```bash
# Deploy Prometheus via Helm
helm install prometheus prometheus-community/prometheus -n monitoring --create-namespace

# All RuntimeAI services expose metrics at /metrics (where available)
# Configure scrape targets in prometheus.yml:
```

```yaml
scrape_configs:
  - job_name: 'runtimeai'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: ['rt19']
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

### Grafana

```bash
# Deploy Grafana
helm install grafana grafana/grafana -n monitoring

# Import RuntimeAI dashboards
# Dashboard JSON files are in: deployment/grafana/dashboards/
```

### Key Metrics to Monitor

| Metric | Alert Threshold | Action |
|--------|----------------|--------|
| Pod restart count | > 3 in 15 min | Investigate logs |
| API latency (p99) | > 2s | Scale CP replicas |
| DB connection pool | > 80% utilized | Increase pool size |
| Redis memory | > 80% | Increase Redis memory |
| Disk usage | > 85% | Expand PV or cleanup |
| Audit chain lag | > 100 unprocessed | Check Poller health |

---

## Alert Configuration

### Critical Alerts

```yaml
# Prometheus alert rules
groups:
  - name: runtimeai-critical
    rules:
      - alert: ServiceDown
        expr: up{namespace="rt19"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "RuntimeAI service {{ $labels.job }} is down"

      - alert: HighRestartCount
        expr: increase(kube_pod_container_status_restarts_total{namespace="rt19"}[1h]) > 5
        for: 5m
        labels:
          severity: warning

      - alert: AuditChainLag
        expr: runtimeai_audit_unprocessed_count > 100
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Audit chain has {{ $value }} unprocessed logs"
```

---

## Log Aggregation

### ELK Stack (Recommended)

```bash
# Deploy Filebeat as DaemonSet
helm install filebeat elastic/filebeat -n monitoring \
  --set daemonset.tolerations[0].operator=Exists

# Configure index pattern: runtimeai-*
# Kibana filter: kubernetes.namespace:rt19
```

### Fluentd (Alternative)

```bash
helm install fluentd fluent/fluentd -n monitoring \
  --set output.host=<ELASTICSEARCH_HOST>
```

---

## Maintenance Windows

### Recommended Schedule

| Task | Frequency | Window | Duration |
|------|-----------|--------|----------|
| PostgreSQL vacuum | Weekly | Sun 02:00-03:00 | 1 hour |
| Certificate renewal | Monthly | First Mon 01:00 | 30 min |
| Image updates | Bi-weekly | Tue 01:00-02:00 | 1 hour |
| Full backup test | Monthly | Last Sat 00:00 | 2 hours |
| Redis cleanup | Weekly | Sun 03:00 | 15 min |

---

## Production Hardening (OPER-047 — Applied 2026-04-09)

### Infrastructure Fixes Applied

| Fix | What | Impact |
|-----|------|--------|
| Prometheus WAL truncation | Deleted 700+ stale WAL segments, increased memory to 1Gi, added WAL compression | Monitoring restored from CrashLoopBackOff |
| aaic-service secret key | Fixed `jwt-secret` → `JWT_SECRET` key reference in K8s manifest | AI Compliance service fully operational |
| TLS certificate renewal | Deleted stuck `proxy-rt19-tls` cert for cert-manager retry | Transparent proxy HTTPS restored |
| DB backup CronJob | `postgres-backup` runs daily at 2 AM, pg_dump + gzip | Data loss protection |
| HPA | control-plane (2-6), dashboard (2-4), auth-service (2-4) at 70% CPU | Auto-scaling on load |
| PDBs | control-plane, dashboard, auth-service, flow-enforcer: minAvailable=1 | Safe node maintenance |
| Network policies | Default deny ingress + allow from nginx-ingress, intra-namespace, monitoring | Security hardening |
| Audit chain repair | `POST /api/audit/repair-chain?tenant_id=X` re-computes SHA-256 hashes | SOC 2 compliance |

### Audit Chain Repair

If the audit chain verification fails (`/api/audit/verify` returns `valid: false`), repair it:

```bash
ADMIN_SECRET=$(kubectl get secret rt19-app-secrets -n rt19 -o jsonpath='{.data.RUNTIMEAI_ADMIN_SECRET}' | base64 -d)
curl -X POST "https://api.rt19.runtimeai.io/api/audit/repair-chain?tenant_id=equinix-onprem" \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET"
# Expected: {"status":"repaired","records_repaired":N,"tenant_id":"equinix-onprem"}
```

### Prometheus WAL Maintenance

If Prometheus enters CrashLoopBackOff (WAL accumulation):

```bash
kubectl scale deployment prometheus -n monitoring --replicas=0
kubectl run wal-cleanup -n monitoring --image=alpine:3.20 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"c","image":"alpine:3.20","command":["sh","-c","cd /prometheus/wal && ls | sort -n | head -700 | xargs rm -rf && echo done"],"volumeMounts":[{"name":"d","mountPath":"/prometheus"}]}],"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"prometheus-data"}}]}}'
sleep 20 && kubectl logs wal-cleanup -n monitoring
kubectl delete pod wal-cleanup -n monitoring
kubectl scale deployment prometheus -n monitoring --replicas=1
```

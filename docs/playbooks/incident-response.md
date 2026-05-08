# Incident Response Playbooks — TOPS-039

## Overview
This document defines incident response procedures by severity level and alert category.

### Severity Levels
- **CRITICAL (P1)**: System down, data loss, security breach → 5-minute response SLA
- **HIGH (P2)**: Degraded service, partial outage → 15-minute response SLA
- **MEDIUM (P3)**: Minor issues, non-user-impacting bugs → 1-hour response SLA
- **LOW (P4)**: Documentation, cleanup → next business day

### Escalation Matrix

| Severity | On-Call | Manager | VP | CEO |
|----------|---------|---------|-----|-----|
| CRITICAL | 5 min | 15 min | 30 min | 1 hr |
| HIGH | 15 min | 30 min | 1 hr | - |
| MEDIUM | 1 hr | 3 hrs | - | - |
| LOW | Next day | - | - | - |

---

## Playbook 1: Service Outage (Pod Crash Loop)

**Alert**: `PodCrashLooping` in Prometheus

### Initial Response (5 min)
1. Get pod logs: `kubectl logs -n rt19 pod/<name> --tail=100`
2. Check pod events: `kubectl describe pod -n rt19 <name>`
3. Check node status: `kubectl get nodes -o wide`
4. Check resource requests/limits: `kubectl get pod <name> -n rt19 -o yaml | grep -A5 resources`

### Investigation (10 min)
- Is it OOMKilled? → Increase memory request
- Readiness probe failing? → Check /health endpoint (curl from pod)
- CrashLoopBackOff? → Check logs for error message
- ImagePullBackOff? → Check image exists in registry

### Remediation
```bash
# Option 1: Increase memory
kubectl set resources deployment/<service> -n rt19 --limits=memory=2Gi --requests=memory=1Gi

# Option 2: Fix code issue (rollback)
kubectl rollout undo deployment/<service> -n rt19

# Option 3: Delete bad pod (controller recreates)
kubectl delete pod <name> -n rt19

# Verify recovery
kubectl rollout status deployment/<service> -n rt19 --timeout=5m
```

### Post-Incident
1. Root cause analysis: Was it code, config, or infrastructure?
2. Document in `/Users/roshanshaik/work/runtimeai_techops/docs/incidents/INCIDENT-<date>-<service>.md`
3. Update runbook if needed
4. Notify security@runtimeai.io if data-bearing pod (database, secrets)

---

## Playbook 2: Database Connection Pool Exhaustion

**Alert**: `PostgreSQLConnections > 95`

### Initial Response (5 min)
1. Check active connections: `SELECT count(*) FROM pg_stat_activity WHERE state = 'active';`
2. Find long-running queries: `SELECT query, now() - query_start FROM pg_stat_activity WHERE state != 'idle' ORDER BY query_start;`
3. Kill idle connections: `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND query_start < now() - interval '1 hour';`

### Investigation
- Did a service deploy recently? → Check logs for query issues
- Is one service hogging all connections? → Check `pg_stat_activity.application_name`
- Are queries hanging? → Identify blocking queries: `SELECT * FROM pg_blocking_pids(...)`

### Remediation
```bash
# Increase connection pool
kubectl set env deployment/control-plane -n rt19 \
  DB_POOL_SIZE=50 \
  DB_POOL_MIN=10 \
  DB_POOL_IDLE_TIMEOUT=300

# Or kill long-running query
psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query_start < now() - interval '30 minutes';"
```

---

## Playbook 3: Disk Space Critical

**Alert**: `NodeDiskPressure` or `PersistentVolumeUsageHigh > 85%`

### Initial Response (5 min)
1. Check node disk: `kubectl describe node <node>`
2. Check PVC usage: `kubectl get pvc -A -o wide`
3. Identify large files: `kubectl exec -n rt19 pod/<name> -- du -sh /* | sort -h`

### Investigation
- Is it logs? → Check `/var/log/` size
- Is it container data? → Check `/var/lib/docker/`
- Is it PVC? → Check mounted data in pod

### Remediation
```bash
# Clean up old logs
kubectl exec -n rt19 pod/<name> -- find /var/log -mtime +7 -delete

# If PVC: scale down pod, delete data, restart
kubectl scale deployment/<service> --replicas=0 -n rt19
kubectl delete pvc <pvc-name> -n rt19
kubectl scale deployment/<service> --replicas=1 -n rt19

# If persistent: request larger PVC from cloud provider
# Azure: Resize disk in Azure Portal, then remount pod
```

---

## Playbook 4: High Error Rate (5xx Errors)

**Alert**: `HighErrorRate > 5%`

### Initial Response (5 min)
1. Check service logs: `kubectl logs -n rt19 deployment/<service> -f | tail -100`
2. Check recent changes: `git log --oneline -n 10`
3. Check dependencies: `curl -s http://<dep-service>:8080/health | jq`

### Investigation
```bash
# Check error types
kubectl logs -n rt19 deployment/<service> | grep -i error | head -20

# Check HTTP status distribution
kubectl logs -n rt19 deployment/<service> | jq '.http_status' 2>/dev/null | sort | uniq -c | sort -rn

# Check if downstream service is down
for svc in postgres redis quantumvault mcp-gateway; do
  echo "Checking $svc..."
  kubectl exec -n rt19 deployment/<service> -- curl -s http://$svc:8080/health
done
```

### Remediation
- If upstream service down: restart that service (Playbook 1)
- If code issue: rollback, fix, redeploy
- If db connection issue: run Playbook 2

---

## Playbook 5: Security Breach (Unauthorized Access)

**Alert**: `UnauthorizedAPIAccess` or `PrivilegeEscalation`

### IMMEDIATE (1 min)
1. **DO NOT RUN `kubectl delete` or tear down pods** — need evidence for forensics
2. Notify security@runtimeai.io and compliance@runtimeai.io immediately
3. Isolate affected pod: `kubectl label pod <pod> quarantine=true`
4. Apply NetworkPolicy to block pod: `kubectl apply -f incident-isolation-policy.yaml`

### Investigation (30 min - security team)
1. Collect logs: `kubectl logs <pod> -n rt19 > /tmp/pod-logs-$(date +%s).txt`
2. Check RBAC: `kubectl auth can-i --as=system:serviceaccount:rt19:<sa> create deployments`
3. Review auth events: `kubectl get events -A | grep -i authorization`
4. Check secrets accessed: `grep -i secret /var/log/audit.log`

### Remediation (security team decides)
- Revoke compromised token: `kubectl delete secret <token-secret> -n rt19`
- Rotate credentials: `/Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-rotate-keys.sh`
- Restart affected service: `kubectl rollout restart deployment/<service> -n rt19`

---

## Playbook 6: QuantumVault Encryption Failure

**Alert**: `QuantumVaultEncryptionError` rate > 0

### IMMEDIATE (2 min)
1. Check QuantumVault health: `kubectl exec -n rt19 pod/quantumvault -- curl -s http://localhost:8200/health`
2. Check key status: `bash /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-audit.sh --filter=key_rotation_failed`
3. Check if keys are accessible: `kubectl get secrets -n rt19 | grep qv`

### Investigation
- Is QuantumVault pod running? → Check pod status (Playbook 1)
- Are keys corrupted? → Check audit log for recent key operations
- Is key rotation stuck? → Check rotation job status: `kubectl get job -n rt19`

### Remediation
```bash
# Restart QuantumVault
kubectl rollout restart deployment/quantumvault -n rt19
kubectl rollout status deployment/quantumvault -n rt19

# If rotation stuck
kubectl delete job quantumvault-rotation-job -n rt19
bash /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-rotate-keys.sh --dry-run

# If data loss suspected
# ESCALATE: This requires DR procedure (Playbook 7)
```

---

## Playbook 7: Data Loss / Database Corruption

**Alert**: Database replication lag > 5 min, RLS policy violation detected

### CRITICAL — STOP ALL WRITES
1. Immediately scale down all services: `kubectl scale deployment --all --replicas=0 -n rt19`
2. Stop database writes: `psql -c "ALTER DATABASE rt19 SET default_transaction_read_only = on;"`
3. Notify C-level, legal, compliance, customers within 5 minutes

### Investigation (forensics, 1 hour)
1. Snapshot database state: `pg_dump -Fd rt19 > /tmp/rt19-backup-$(date +%s).tar`
2. Check replication status: `SELECT * FROM pg_stat_replication;`
3. Review audit logs: `SELECT * FROM audit_log WHERE action = 'DELETE' OR action = 'UPDATE' ORDER BY created_at DESC LIMIT 100;`
4. Check backup integrity: Restore latest backup to test database, verify data

### Remediation (depends on findings)
- If recent backup is valid: restore from backup (RTO: 2-4 hours)
- If corruption is known: manually repair affected rows from backup
- If data is truly lost: file incident report, notify customers, begin RTO/RPO assessment

### Post-Incident
- Full forensic report (48 hours)
- Root cause analysis (what caused data corruption?)
- Infrastructure review (are backups working? Are they tested?)
- Communication to customers (transparency, next steps)

---

## Contact Information

| Role | Email | Slack | Phone |
|------|-------|-------|-------|
| On-Call Engineer | oncall@runtimeai.io | #oncall | +1-XXX-XXX-XXXX |
| Platform Lead | platform-lead@runtimeai.io | @platform-lead | - |
| Security Lead | security@runtimeai.io | @security-lead | - |
| VP Ops | vpops@runtimeai.io | @vpops | - |
| CEO | ceo@runtimeai.io | @ceo | - |

---

## Alert Routing Rules

**Critical Alerts** → PagerDuty (5 min response)
**High Alerts** → Slack + Email (15 min response)
**Medium Alerts** → Slack (#alerts-warnings)
**Low Alerts** → Jira ticket creation

See `/Users/roshanshaik/work/runtimeai_techops/monitoring/alertmanager/alertmanager.yml` for config.

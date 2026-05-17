# Runbook: shared-data postgres ExclusiveLock Recovery

**Service**: shared-data/postgres-0 (authzion DB)  
**Alert**: `PostgresExclusiveLockAccumulation` / `PostgresCatalogQueryTimeout`  
**Symptom**: QuantoSign / Enterprise Dashboard / RuntimeCRM magic link returns 500 or hangs  
**Root cause**: pgbouncer ExclusiveLocks on `pg_class` blocking all catalog queries  

---

## Quick Reference

```
Symptom chain:
postgres logs "you don't own a lock of type ExclusiveLock" (repeating)
  → pg_class ExclusiveLock accumulated
  → auth-service: context canceled after 10-30s
  → all magic link requests → HTTP 500
  → users cannot log in to any app
```

---

## Step 1 — Confirm the issue

```bash
# Check postgres logs for the lock warning
kubectl logs -n shared-data statefulset/postgres --since=10m | grep "ExclusiveLock"

# Check if pg_class is locked (if this hangs >3s → confirmed)
timeout 3 kubectl exec -n shared-data postgres-0 -- \
  psql -U postgres -d authzion -c \
  "SELECT count(*) FROM pg_locks WHERE relation = 'pg_class'::regclass AND mode = 'ExclusiveLock';"
```

---

## Step 2 — Restart pgbouncer FIRST (stops connection storm)

```bash
kubectl rollout restart deployment/pgbouncer -n shared-data
kubectl rollout status deployment/pgbouncer -n shared-data --timeout=60s
```

Wait 30s. Check if catalog queries work now:
```bash
timeout 3 kubectl exec -n shared-data postgres-0 -- \
  psql -U postgres -d authzion -c "SELECT count(*) FROM pg_class WHERE relkind='r';"
```

If this works → done, lock was cleared by pgbouncer restart. Skip to Step 5.

---

## Step 3 — Restart postgres (if locks persist)

```bash
kubectl rollout restart statefulset/postgres -n shared-data
```

Wait up to 2 minutes. If stuck in Terminating (postgres shutdown blocked by its own locks):

```bash
kubectl delete pod -n shared-data postgres-0 --force --grace-period=0
```

---

## Step 4 — If postgres-0 stuck in ContainerCreating (orphaned containerd sandbox)

Check for the sandbox reservation error:
```bash
kubectl get events -n shared-data | grep "sandbox name"
# Expect: "Failed to reserve sandbox name postgres-0_shared-data_..."
```

Identify the node:
```bash
kubectl describe pod -n shared-data postgres-0 | grep "Node:"
```

**Fix: Reboot the VMSS node** (instance 1 = the postgres node):
```bash
az vmss restart \
  --resource-group MC_runtimeai-rg_runtimeai-aks_westus2 \
  --name aks-nodepool2-28391752-vmss \
  --instance-ids 1
```

Wait 3-5 minutes. Monitor:
```bash
kubectl get nodes -w
kubectl get pod -n shared-data -w
```

---

## Step 5 — Verify recovery

```bash
# postgres-0 should be 1/1 Running
kubectl get pod -n shared-data postgres-0

# Catalog query should respond in <1s
kubectl exec -n shared-data postgres-0 -- \
  psql -U postgres -d authzion -c "SELECT count(*) FROM pg_class WHERE relkind='r';"

# Verify magic link works from esign-service
kubectl exec -n rt01 deployment/esign-service -- \
  wget -q -O- --post-data='{"email":"smoke@test.runtimeai.io","persona":"esign"}' \
  --header='Content-Type: application/json' \
  http://auth-service:8097/api/auth/magic-link
# Expect: {"message":"..."}  HTTP 200
```

---

## Step 6 — Run smoke test suite

```bash
bash /Users/roshanshaik/work/runtimeai/auth-service/qa_testing_local/smoke_magic_link_all_apps.sh
# All 5 apps must PASS before declaring recovery complete
```

---

## Root Cause & Prevention

**Root cause (2026-05-16)**: pgbouncer `pool_mode=transaction` + DDL statements (migrations / `LOCK TABLE`) through the pool. When clients disconnect mid-transaction, `DISCARD ALL` (server_reset_query) cannot roll back uncommitted DDL, leaving ExclusiveLocks on `pg_class` permanently.

**Fix applied (OPER_RT19-123)**: Switched pgbouncer to `pool_mode=session`. Session mode holds a dedicated server connection per client session, so `DISCARD ALL` runs correctly on disconnect.

**File changed**: `runtimeai_techops/k8s/esign-pods/shared-data/02-pgbouncer.yaml`

**Prometheus alert**: `PostgresExclusiveLockAccumulation` fires at >3 warnings/5min (30-60 min before outage).

---

## Node Identity

- postgres-0 node: `aks-nodepool2-28391752-vmss000001` (VMSS instance ID **1**)
- 2 CPU cores, 4GB RAM, Azure Premium disk (50GB)
- 30-pod limit on this node
- Rebooting evicts all 30 pods; they reschedule automatically on other nodes (~3 min)

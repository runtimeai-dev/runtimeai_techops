# RuntimeAI Platform — Disaster Recovery Runbook

**Version**: 1.0.0-trial
**Date**: 2026-03-28

---

## Recovery Targets

| Metric | Target (Trial) | Target (Production) |
|--------|----------------|---------------------|
| **RTO** (Recovery Time Objective) | 4 hours | 1 hour |
| **RPO** (Recovery Point Objective) | 24 hours | 1 hour |
| Backup frequency | Daily | Hourly (DB) + Daily (full) |
| Backup retention | 14 days | 90 days |

---

## Scenario 1: Single Pod Crash

**Symptoms**: Individual service is not responding, pod in CrashLoopBackOff.
**Impact**: Partial (specific feature unavailable).
**RTO**: < 5 minutes (automatic).

```bash
# K8s will auto-restart pods. Check status:
kubectl get pods -n rt19 -w

# If stuck in CrashLoopBackOff, check logs:
kubectl logs -n rt19 deploy/<service-name> --tail=50

# Force restart a specific service:
kubectl rollout restart deploy/<service-name> -n rt19

# Common causes:
# - OOM kill → increase memory limit
# - DB connection failure → check postgres pod
# - Missing secret → verify secrets exist
```

---

## Scenario 2: Database Corruption / Data Loss

**Symptoms**: API errors, inconsistent data, audit chain broken.
**Impact**: Critical — all services affected.
**RTO**: 30 minutes – 2 hours.

### Step 1: Stop Application Traffic

```bash
# Scale down control-plane to prevent further writes
kubectl scale deploy/control-plane -n rt19 --replicas=0
```

### Step 2: Restore PostgreSQL from Backup

```bash
# Find latest backup
ls -la /path/to/backups/runtimeai_backup_*.tar.gz | tail -3

# Extract
BACKUP="runtimeai_backup_20260328_020000"
tar xzf ${BACKUP}.tar.gz
cd ${BACKUP}

# Drop and recreate database
kubectl exec -n rt19 deploy/postgres -- psql -U runtimeai -c "DROP DATABASE authzion;"
kubectl exec -n rt19 deploy/postgres -- psql -U runtimeai -c "CREATE DATABASE authzion OWNER runtimeai;"

# Restore from dump
gunzip -c postgres_*.sql.gz | kubectl exec -i -n rt19 deploy/postgres -- pg_restore -U runtimeai -d authzion --no-owner --no-privileges

# Restore roles
gunzip -c postgres_roles_*.sql.gz | kubectl exec -i -n rt19 deploy/postgres -- psql -U runtimeai
```

### Step 3: Verify RLS Intact

```bash
kubectl exec -n rt19 deploy/postgres -- psql -U runtimeai -d authzion -c \
  "SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND rowsecurity=true ORDER BY tablename;"
```

### Step 4: Restart Services

```bash
kubectl scale deploy/control-plane -n rt19 --replicas=1
kubectl rollout restart deploy -n rt19 --selector=app!=postgres,app!=redis

# Wait for all pods
kubectl get pods -n rt19 -w
```

### Step 5: Verify Audit Chain

```bash
# Login and check audit chain integrity
curl -s -b "$CK" "$API_BASE/api/audit/verify?tenant_id=<your-tenant>"
# Expected: {"valid": true}
```

---

## Scenario 3: Full Cluster Loss

**Symptoms**: Entire K8s cluster destroyed (accidental deletion, hardware failure).
**Impact**: Total outage.
**RTO**: 2-4 hours.

### Step 1: Provision New Cluster

```bash
# On-prem K8s (kubeadm)
kubeadm init --pod-network-cidr=10.244.0.0/16
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Or Azure AKS
az aks create -g runtimeai-rg -n runtimeai-cluster --node-count 3 --node-vm-size Standard_D4s_v3
```

### Step 2: Recreate Namespace and Secrets

```bash
kubectl create namespace rt19

# Recreate secrets from vault/backup
# Option A: From vault
export ADMIN_SECRET=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv)
# ... (repeat for all secrets)

# Option B: From backup manifest (secrets_list.txt + vault)
./configure-environment.sh  # Regenerates from .env
kubectl apply -f k8s-configured/00-secrets-generated.yaml
```

### Step 3: Deploy Infrastructure

```bash
kubectl apply -f k8s-configured/00-namespaces.yaml
kubectl apply -f k8s-configured/01-postgres.yaml
kubectl apply -f k8s-configured/02-redis.yaml

# Wait for DB to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n rt19 --timeout=120s
```

### Step 4: Restore Database

```bash
# Copy backup into postgres pod
kubectl cp postgres_*.sql.gz rt19/<postgres-pod>:/tmp/

# Restore
kubectl exec -n rt19 deploy/postgres -- bash -c \
  "gunzip -c /tmp/postgres_*.sql.gz | pg_restore -U runtimeai -d authzion --no-owner"
```

### Step 5: Deploy All Services

```bash
kubectl apply -f k8s-configured/
kubectl get pods -n rt19 -w
```

### Step 6: Verify

```bash
# Run smoke test
./testing_output/smoke_test.sh
# Run SoW validation
./testing_output/sow_test_suite.sh
```

---

## Scenario 4: Redis Failure

**Symptoms**: Kill switch slow, rate limiting not working, session cache miss.
**Impact**: Performance degradation (not data loss).
**RTO**: < 10 minutes.

```bash
# Redis is ephemeral cache — restart is sufficient
kubectl rollout restart deploy/redis -n rt19

# If persistent data needed:
kubectl cp /path/to/backup/redis_*.rdb rt19/<redis-pod>:/data/dump.rdb
kubectl rollout restart deploy/redis -n rt19

# Verify
kubectl exec -n rt19 deploy/redis -- redis-cli ping
kubectl exec -n rt19 deploy/redis -- redis-cli info memory | grep used_memory_human
```

---

## Scenario 5: Secret Exposure

**Symptoms**: Suspect that JWT_SECRET, ADMIN_SECRET, or API_KEY_SECRET has been compromised.
**Impact**: Security breach — all sessions and API keys potentially compromised.
**RTO**: 30 minutes.

```bash
# 1. Rotate all secrets immediately
JWT_SECRET=$(openssl rand -hex 32)
ADMIN_SECRET=$(openssl rand -hex 16)
API_KEY_SECRET=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)

# 2. Update vault
az keyvault secret set --vault-name runtimeai-rt19-kv --name jwt-secret --value "$JWT_SECRET"
az keyvault secret set --vault-name runtimeai-rt19-kv --name admin-secret --value "$ADMIN_SECRET"

# 3. Update K8s secrets
kubectl create secret generic rt19-app-secrets -n rt19 \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=ADMIN_SECRET="$ADMIN_SECRET" \
  --from-literal=API_KEY_SECRET="$API_KEY_SECRET" \
  --from-literal=SESSION_SECRET="$SESSION_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Restart all services to pick up new secrets
kubectl rollout restart deploy -n rt19

# 5. Invalidate all existing sessions (Redis flush)
kubectl exec -n rt19 deploy/redis -- redis-cli FLUSHDB

# 6. Audit log review
curl -s -b "$CK" "$API_BASE/api/audit?tenant_id=<tenant>&limit=100" | \
  python3 -c 'import sys,json; [print(e) for e in json.load(sys.stdin)]'
```

---

## Backup Verification

Run monthly to ensure backups are restorable:

```bash
# 1. Create a test namespace
kubectl create namespace rt19-dr-test

# 2. Deploy postgres in test namespace
kubectl apply -f k8s-configured/01-postgres.yaml -n rt19-dr-test

# 3. Restore latest backup into test namespace
kubectl exec -n rt19-dr-test deploy/postgres -- pg_restore -U runtimeai -d authzion /tmp/backup.sql

# 4. Verify table count and row counts
kubectl exec -n rt19-dr-test deploy/postgres -- psql -U runtimeai -d authzion -c \
  "SELECT schemaname, count(*) as tables FROM pg_tables WHERE schemaname='public' GROUP BY schemaname;"

# 5. Cleanup
kubectl delete namespace rt19-dr-test
```

---

## Contacts

| Role | Contact |
|------|---------|
| RuntimeAI Support | support@runtimeai.io |
| Escalation (P1/P0) | Slack #runtimeai-support or email with subject "URGENT" |
| On-prem Vault admin | Customer's infrastructure team |

# Database Connection Pool Exhaustion

## Symptoms
- Slow queries
- Connection timeout errors: `FATAL: remaining connection slots reserved for non-replication superuser connections`
- Max connections: `PG_MAX_CONNECTIONS`

## Recovery

```bash
# Check current connections
kubectl exec -n rt19 postgres-0 -- psql -U postgres -d rt19 -c \
  "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

# Kill idle connections
kubectl exec -n rt19 postgres-0 -- psql -U postgres -d rt19 -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
   WHERE state = 'idle' AND query_start < now() - interval '1 hour';"

# Increase max connections (if persistent)
kubectl patch statefulset postgres -n rt19 --type merge \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"postgres","env":[{"name":"POSTGRES_MAX_CONNECTIONS","value":"300"}]}]}}}}'
```

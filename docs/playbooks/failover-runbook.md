# Failover Runbook & Testing (monthly DR drill) — TOPS-053

## Failover Procedure: rt19 (staging) → rt01/rt02 (production)

### Pre-Failover Checklist (before incident)
- [ ] Weekly backup tested and verified
- [ ] DNS failover configured (app.runtimeai.io → rt01/rt02)
- [ ] Application ready to read from rt01/rt02 database
- [ ] All services scaled up in rt01/rt02 (prod replicas)
- [ ] Status page updated with "investigating" message

### Failover Steps (5 minutes → 60 minutes RTO)

#### Phase 1: Detect Failure (2 minutes)
1. Alert fires: `ServiceDown` for control-plane in rt19
2. Confirm: `kubectl get nodes -n rt19`; if >50% nodes down → failover
3. Escalate: Page platform-lead + VP ops immediately

#### Phase 2: Activate Failover (5-10 minutes)
```bash
# 1. Scale down rt19 (stop accepting requests)
kubectl scale deployment --all --replicas=0 -n rt19

# 2. Point DNS to rt01/rt02
az network dns record-set a update \
  --resource-group runtimeai-rg \
  --zone-name runtimeai.io \
  --name app \
  --ipv4-address <rt01-lb-ip>

# 3. Run latest restore on rt01/rt02 database
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier rt01-prod-current \
  --db-snapshot-identifier <latest-backup> \
  --db-instance-class db.standard_d2s_v3

# 4. Verify rt01/rt02 services health
for svc in control-plane dashboard cost-ledger waf mcp-gateway; do
  kubectl get deployment $svc -n rt01 -o jsonpath='{.status.readyReplicas}/{.spec.replicas}'
done
```

#### Phase 3: Verify Recovery (10-30 minutes)
```bash
# 1. Test API endpoints
curl -s https://api.runtimeai.io/api/v1/health | jq
curl -s https://app.runtimeai.io | head -100

# 2. Check data consistency
psql -h rt01-db -c "SELECT COUNT(*) FROM tenants;"
psql -h rt01-db -c "SELECT COUNT(*) FROM users ORDER BY created_at DESC LIMIT 1;"

# 3. Monitor logs for errors
kubectl logs -n rt01 deployment/control-plane -f | grep -i error | head -20

# 4. Run smoke tests
bash /Users/roshanshaik/work/runtimeai_techops/qa/platform/run_platform_suite.sh --env=rt01
```

#### Phase 4: Notify Customers (5 minutes after recovery)
```bash
# Send status page update
curl -X POST https://status.runtimeai.io/api/incidents \
  -H "Authorization: Bearer $STATUS_PAGE_TOKEN" \
  -d '{
    "title": "Production failover completed",
    "status": "investigating",
    "impact": "degraded",
    "message": "We experienced an issue in our staging environment and activated automatic failover to production. Services are being validated."
  }'

# Send customer email
sendgrid_template_id=sg-failover-customer-email \
to=customers@runtimeai.io \
subject="Production Failover Update - Services Restored"
```

### Post-Failover Steps (30-60 minutes)

1. **Analyze root cause** — why did rt19 fail?
   - Check cloud provider events: Azure Service Health
   - Check application logs: Elasticsearch audit logs
   - Check infrastructure: Prometheus metrics

2. **Investigate data loss** — any data in rt19 since last backup?
   - Query audit log: `SELECT * FROM audit_log WHERE created_at > backup_time;`
   - If data exists: manually reconcile or restore customer data from backup

3. **Return to normal** — rt19 recovery procedure:
   ```bash
   # 1. Replace failed nodes
   az aks nodepool upgrade --resource-group runtimeai-rg --cluster-name rt19 --nodepool-name default
   
   # 2. Restore rt19 database from rt01/rt02
   pg_dump -h rt01-db rt19 | psql -h rt19-db -U postgres rt19
   
   # 3. Scale rt19 back to normal
   kubectl scale deployment --all --replicas=2 -n rt19  # Staging = 2 replicas
   
   # 4. Verify health
   kubectl rollout status deployment --all -n rt19
   ```

4. **Status page** — mark as resolved
   ```bash
   curl -X POST https://status.runtimeai.io/api/incidents/{incident_id}/update \
     -d '{"status":"resolved"}'
   ```

5. **Post-incident review** (24 hours)
   - Root cause analysis
   - Timeline of events
   - Action items to prevent recurrence
   - Presentation to stakeholders

### Monthly DR Drill (fire-drill practice)

**Every last Friday of the month, 2:00 PM UTC**

```bash
# 1. Create test instance from backup
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier rt19-test-dr-drill-$(date +%s) \
  --db-snapshot-identifier <latest-backup>

# 2. Simulate rt19 failure (without impact)
kubectl scale deployment --all --replicas=0 -n rt19-test-ns

# 3. Execute failover procedure (to rt01-test)
# Follow steps above, but targeting test namespace

# 4. Record time to recover
TIME_TO_RECOVER=$(date -d@$(($(date +%s) - $START_TIME)) -u +%H:%M:%S)
echo "DR Drill RTO: $TIME_TO_RECOVER"

# 5. Cleanup
aws rds delete-db-instance --db-instance-identifier rt19-test-dr-drill-* --skip-final-snapshot
```

### Failover Success Criteria

- [ ] DNS updated < 5 minutes
- [ ] rt01/rt02 database restored < 30 minutes
- [ ] All services healthy < 45 minutes
- [ ] Customer-facing API responding < 60 minutes (RTO 1h)
- [ ] No data loss (RPO 15 min)
- [ ] Alerts triggered automatically (no manual intervention needed)
- [ ] Team notified within 5 minutes

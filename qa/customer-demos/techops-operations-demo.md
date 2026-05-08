# TechOps Operations Demo

## Demo Overview

This 45-minute walkthrough demonstrates RuntimeAI TechOps platform operations, suitable for:
- SRE candidates
- Customer operations teams
- Sales engineering demos
- Training sessions

---

## Scenario 1: Deploy a Service (10 minutes)

**Goal**: Show deployment process from code to running pods

**Prerequisites**: Access to rt19 cluster, kubectl, helm

**Steps**:

1. **Show git state**
   ```bash
   git status
   # Expected: Feature branch with Helm chart changes
   ```

2. **Validate Helm chart**
   ```bash
   helm lint helm/control-plane/
   # Expected: Chart valid, all tests pass
   ```

3. **Template and dry-run**
   ```bash
   helm template control-plane helm/control-plane/ \
     -f helm/control-plane/values-rt19.yaml | \
     kubectl apply --dry-run=client -f -
   # Expected: Dry-run succeeds, 0 errors
   ```

4. **Deploy**
   ```bash
   helm upgrade --install control-plane helm/control-plane/ \
     -n rt19 -f helm/control-plane/values-rt19.yaml
   # Expected: Release updated/installed
   ```

5. **Monitor rollout**
   ```bash
   kubectl rollout status deployment/control-plane -n rt19
   # Expected: Rollout succeeds within 60s
   ```

**Success Criteria**:
- ✓ Deployment completes without errors
- ✓ Pods transition to Ready state
- ✓ Services become Available

---

## Scenario 2: Monitor Service Health (10 minutes)

**Goal**: Show real-time monitoring and alerting

**Steps**:

1. **Access Grafana**
   ```bash
   kubectl port-forward -n rt19 svc/grafana 3000:3000
   # Open http://localhost:3000/d/control-plane-metrics
   ```

2. **Show dashboards**
   - API Latency (p50/p95/p99)
   - Request rate by method
   - Error rate trending
   - Pod resource utilization

3. **Check Prometheus**
   ```bash
   kubectl port-forward -n rt19 svc/prometheus 9090:9090
   # Open http://localhost:9090
   # Query: rate(control_plane_http_requests_total[5m])
   ```

4. **Verify alerts firing**
   - Show AlertManager dashboard
   - Demonstrate routing to Slack/PagerDuty
   - Simulate alert (high error rate)

**Success Criteria**:
- ✓ Dashboards loading with live data
- ✓ Metrics flowing from services
- ✓ Alerts triggering correctly

---

## Scenario 3: Respond to an Alert (10 minutes)

**Goal**: Show incident response workflow

**Steps**:

1. **Receive alert**
   - "High error rate (>5%) on control-plane"
   - Alert fired in Slack #alerts channel

2. **Investigate**
   ```bash
   kubectl logs -n rt19 deployment/control-plane --tail=50 | grep ERROR
   ```

3. **Check metrics**
   - Jump to Grafana dashboard
   - Identify error spike
   - Note correlation with deployment

4. **Execute runbook**
   - Access doc/runbooks/pod-crash-loop-recovery.md
   - Check pod status: `kubectl get pods -n rt19`
   - Review events: `kubectl describe pod <name> -n rt19`

5. **Fix (if needed)**
   - Restart pods, or
   - Rollback deployment
   - Monitor for recovery

**Success Criteria**:
- ✓ Root cause identified
- ✓ Appropriate action taken
- ✓ Recovery confirmed in metrics

---

## Scenario 4: Disaster Recovery Failover (10 minutes)

**Goal**: Show failover from rt19 (staging) to rt01 (production)

**Steps**:

1. **Current state**
   ```bash
   kubectl cluster-info --context rt19
   # Expected: rt19 cluster healthy
   ```

2. **Simulate primary failure**
   - Disconnect rt19 cluster
   - Show timeout when accessing

3. **Failover decision**
   - Check rt01 cluster health
   - Confirm backup is recent
   - Declare failover

4. **Execute failover**
   ```bash
   bash scripts/disaster-recovery/failover-automation.sh rt01
   # Expected: DNS updated, traffic routed to rt01
   ```

5. **Verify failover**
   ```bash
   kubectl cluster-info --context rt01
   curl https://app.runtimeai.io/health
   # Expected: Responding from rt01
   ```

**Success Criteria**:
- ✓ Failover completes < 5 minutes
- ✓ Services healthy on rt01
- ✓ Data consistency maintained

---

## Scenario 5: Secret Rotation (5 minutes)

**Goal**: Show zero-downtime secret rotation

**Steps**:

1. **Check current secret**
   ```bash
   kubectl get secret api-secret -n rt19 -o yaml | head -20
   ```

2. **Rotate secret**
   ```bash
   bash scripts/secrets/rotate-integration.sh rt19 api-secret
   # Expected: Secret updated, pods restarted, service healthy
   ```

3. **Verify health**
   ```bash
   kubectl get pods -n rt19 --watch
   # Expected: Pods cycling, all returning to Ready
   ```

**Success Criteria**:
- ✓ Rotation completes without downtime
- ✓ Services remain healthy
- ✓ New secret in use

---

## Q&A

**Common questions**:
- How is data protected during rotation? (QuantumVault encryption)
- What's the RTO for failover? (< 4 hours per spec)
- How are configurations managed? (GitOps - all in version control)
- What's the monitoring coverage? (15 dashboards, 30+ alert rules)

---

## Follow-up Resources

- Architecture docs: `docs/architecture/`
- Runbooks: `docs/runbooks/`
- Scripts: `scripts/deployment/`, `scripts/disaster-recovery/`
- Specifications: `todo-list/TOPS-*.md`

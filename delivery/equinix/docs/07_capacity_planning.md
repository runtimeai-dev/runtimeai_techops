# RuntimeAI Platform — Capacity Planning Guide

**Version**: 1.0.0-trial
**Date**: 2026-03-28

---

## Equinix Trial Sizing (Reference)

| Parameter | Expected |
|-----------|----------|
| Tenants | 2 |
| Users per tenant | 5-10 |
| Registered agents | 250 |
| Discovered agents | 500+ |
| API calls/day | 10,000–50,000 |
| Token throughput | 1M/day |
| DLP scans/hour | 500 |
| Kill switch activations/day | <10 |
| Audit events/day | 5,000–10,000 |

---

## Resource Allocation by Tier

### Tier 1: Trial / PoC (Equinix)

| Component | Replicas | CPU Req/Lim | Memory Req/Lim | Storage |
|-----------|----------|-------------|----------------|---------|
| control-plane | 1 | 200m/1000m | 256Mi/1Gi | — |
| dashboard | 1 | 50m/200m | 64Mi/128Mi | — |
| auth-service | 1 | 50m/200m | 64Mi/128Mi | — |
| discovery | 1 | 50m/200m | 128Mi/256Mi | — |
| mcp-gateway | 1 | 100m/500m | 128Mi/512Mi | — |
| flow-enforcer | 1 | 100m/500m | 128Mi/256Mi | — |
| PostgreSQL | 1 | 500m/2000m | 512Mi/2Gi | 50Gi SSD |
| Redis | 1 | 100m/500m | 256Mi/512Mi | 5Gi |
| **Total** | **8** | **~1.2 cores** | **~1.5 GB** | **55 Gi** |

All 27+ services at minimum allocation: **~4 CPU cores, 6 GB RAM**

### Tier 2: Production (250 agents, 10 users)

| Component | Replicas | CPU Req/Lim | Memory Req/Lim | Storage |
|-----------|----------|-------------|----------------|---------|
| control-plane | 2 | 500m/2000m | 512Mi/2Gi | — |
| dashboard | 2 | 100m/500m | 128Mi/256Mi | — |
| auth-service | 2 | 100m/500m | 128Mi/256Mi | — |
| mcp-gateway | 2 | 200m/1000m | 256Mi/1Gi | — |
| flow-enforcer | 2 | 200m/1000m | 256Mi/512Mi | — |
| PostgreSQL | 1 (primary) | 1000m/4000m | 1Gi/4Gi | 200Gi NVMe |
| Redis | 1 (sentinel) | 200m/1000m | 512Mi/1Gi | 10Gi |
| **Total** | **~35** | **~8 cores** | **~12 GB** | **210 Gi** |

### Tier 3: Enterprise (1000+ agents, 50+ users, multi-region)

| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| control-plane | 3 | 1/4 cores | 1Gi/4Gi | — |
| All DP services | 3 each | varies | varies | — |
| PostgreSQL | 2 (HA) | 2/8 cores | 4Gi/16Gi | 1Ti NVMe |
| Redis | 3 (cluster) | 500m/2 cores | 1Gi/4Gi | 50Gi |
| **Total** | **~90** | **~32 cores** | **~48 GB** | **~1.1 Ti** |

---

## Scaling Guidelines

### Horizontal Pod Autoscaling (HPA)

```yaml
# control-plane HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: control-plane-hpa
  namespace: rt19
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: control-plane
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### When to Scale

| Metric | Threshold | Action |
|--------|-----------|--------|
| Control-plane CPU > 70% sustained | 5 min | Add replica |
| API latency p99 > 500ms | 5 min | Add CP replica + investigate DB |
| PostgreSQL connections > 80% max | Immediate | Increase `max_connections` or add PgBouncer |
| Redis memory > 70% | Monitor | Increase memory limit or add eviction policy |
| Kill switch latency > 200ms | Immediate | Check Redis connectivity, add local replica |
| DLP scan latency > 100ms | Monitor | Add CP replica |
| Discovery scan queue > 100 | Monitor | Add discovery replica |

### Database Scaling

| Agents | DB CPU | DB Memory | DB Storage | Connection Pool |
|--------|--------|-----------|------------|-----------------|
| < 100 | 500m | 512Mi | 20Gi | max 25 |
| 100-500 | 1000m | 2Gi | 100Gi | max 50 |
| 500-2000 | 2000m | 4Gi | 500Gi | max 100 + PgBouncer |
| 2000+ | 4000m | 8Gi | 1Ti | PgBouncer required |

---

## Storage Projections

| Data Type | Growth Rate | 30-day | 1-year |
|-----------|-------------|--------|--------|
| Audit logs | ~10 KB/event × 5K/day | 1.5 GB | 18 GB |
| Discovery data | ~2 KB/agent × 500 agents | 50 MB | 200 MB |
| eSign documents | ~500 KB/doc × 100/month | 50 MB | 600 MB |
| PostgreSQL total | | 5 GB | 25 GB |
| Redis (hot data) | | 500 MB | 2 GB |
| Prometheus metrics | | 5 GB | 20 GB |

---

## Network Requirements

| Flow | Protocol | Bandwidth | Latency |
|------|----------|-----------|---------|
| Client → Ingress | HTTPS | 10 Mbps | < 50ms |
| CP → PostgreSQL | TCP/5432 | 100 Mbps | < 5ms |
| CP → Redis | TCP/6379 | 50 Mbps | < 1ms |
| CP → DP services | HTTP/gRPC | 50 Mbps | < 10ms |
| Discovery → External | HTTPS | 10 Mbps | < 500ms |
| SIEM export | HTTPS | 5 Mbps | < 100ms |

# Architecture Overview

## System Components

```
┌─────────────────────────────────────────────────────────────┐
│  AWS/Azure/GCP/Oracle Cloud (Multi-Cloud)                  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  K8s Cluster (rt19/rt01/rt02/pqdata/runtimecrm)     │  │
│  │                                                      │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │  Ingress (Nginx) → TLS/cert-manager            │  │  │
│  │  │  ↓                                              │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  Services (31 total)                     │  │  │  │
│  │  │  │  ├─ control-plane (8080)                 │  │  │  │
│  │  │  │  ├─ dashboard (4000)                     │  │  │  │
│  │  │  │  ├─ cost-ledger                          │  │  │  │
│  │  │  │  ├─ drift-engine                         │  │  │  │
│  │  │  │  ├─ waf                                  │  │  │  │
│  │  │  │  ├─ mcp-gateway (8091)                   │  │  │  │
│  │  │  │  └─ ... (25 more services)               │  │  │  │
│  │  │  └──────────────────────────────────────────┘  │  │  │
│  │  │                ↓                                │  │  │
│  │  │  ┌──────────────────────────────────────────┐  │  │  │
│  │  │  │  Data Services                          │  │  │  │
│  │  │  ├─ PostgreSQL RDS (multi-tenant, RLS)     │  │  │  │
│  │  │  ├─ Redis Cache                            │  │  │  │
│  │  │  ├─ QuantumVault (PQC encryption)          │  │  │  │
│  │  │  └─ etcd (K8s state, encrypted)            │  │  │  │
│  │  └──────────────────────────────────────────────┘  │  │  │
│  │                                                      │  │  │
│  │  ┌────────────────────────────────────────────────┐  │  │  │
│  │  │  Observability                               │  │  │  │
│  │  ├─ Prometheus (metrics)                         │  │  │  │
│  │  ├─ Loki (logs)                                 │  │  │  │
│  │  ├─ Jaeger (traces)                             │  │  │  │
│  │  ├─ Grafana (dashboards)                        │  │  │  │
│  │  └─ Alertmanager (routing → PagerDuty/Slack)    │  │  │  │
│  │  └────────────────────────────────────────────────┘  │  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **User Request** → Ingress (Nginx) → Control Plane API
2. **Authentication** → auth-service → jwt validation → RLS enforcement
3. **Database Query** → PostgreSQL with RLS (tenant isolation)
4. **Secrets** → QuantumVault (PQC ML-KEM-1024 encryption)
5. **Metrics** → Prometheus scrapers → Grafana
6. **Logs** → Fluent-bit → Loki
7. **Traces** → Jaeger OTLP

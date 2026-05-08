# RuntimeAI — rt19 Monitoring Guide

> **Complete guide** to monitoring the rt19 pod on Azure AKS.
> Covers dashboards, traffic analysis, health checks, alerting, and troubleshooting.
>
> **Last Updated**: March 14, 2026
>
> **Public Sites Being Monitored**:
> | Site | URL | Service |
> |------|-----|---------|
> | Landing | `https://www.runtimeai.io` | runtimeai-landing |
> | SaaS Admin | `https://admin.runtimeai.io` | saas-admin-app |
> | Dashboard | `https://app.rt19.runtimeai.io` | dashboard |
> | API | `https://api.rt19.runtimeai.io` | control-plane |
> | eSign | `https://esign.rt19.runtimeai.io` | esign-landing |
> | Auditor | `https://auditor.rt19.runtimeai.io` | auditor-dashboard |
> | Marketplace | `https://marketplace.rt19.runtimeai.io` | marketplace-service |
> | FinOps | `https://finops.rt19.runtimeai.io` | ai-finops-service |

---

## Table of Contents

1. [Quick Start — Deploy Monitoring](#1-quick-start--deploy-monitoring)
2. [Monitoring Architecture](#2-monitoring-architecture)
3. [Grafana Dashboards](#3-grafana-dashboards)
4. [Health Monitor Script](#4-health-monitor-script)
5. [Azure Monitor Integration](#5-azure-monitor-integration)
6. [Traffic Analysis](#6-traffic-analysis)
7. [Alerting Setup](#7-alerting-setup)
8. [Troubleshooting Runbook](#8-troubleshooting-runbook)
9. [Cost Impact](#9-cost-impact)

---

## 1. Quick Start — Deploy Monitoring

```bash
# Deploy the full monitoring stack (Prometheus + Grafana + Blackbox + kube-state-metrics)
kubectl apply -f deployment/scripts/rt19/k8s/05-monitoring.yaml

# Wait for pods to be ready (~2 minutes)
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s

# Access Grafana locally
kubectl port-forward svc/grafana 3000:3000 -n monitoring &
echo "Grafana: http://localhost:3000"
echo "Login: admin / RuntimeAI2026!"

# Or run the health check script
cd deployment/scripts/rt19
./health-monitor.sh
```

---

## 2. Monitoring Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │                 MONITORING NAMESPACE            │
                    │                                                  │
Internet ──────────▶│  ┌─────────────────┐   ┌────────────────────┐  │
(public endpoints)  │  │  Blackbox        │   │  kube-state-       │  │
                    │  │  Exporter        │   │  metrics           │  │
                    │  │  (HTTPS probes)  │   │  (pod/deploy state)│  │
                    │  └────────┬─────────┘   └────────┬───────────┘  │
                    │           │                       │               │
                    │           ▼                       ▼               │
                    │  ┌─────────────────────────────────────────────┐ │
                    │  │           PROMETHEUS                         │ │
                    │  │  • Scrapes every 30s                        │ │
                    │  │  • 15-day retention / 5GB cap               │ │
                    │  │  • Probes 8 public endpoints                │ │
                    │  │  • Collects pod/node metrics                │ │
                    │  └────────────────────┬────────────────────────┘ │
                    │                       │                          │
                    │                       ▼                          │
                    │  ┌─────────────────────────────────────────────┐ │
                    │  │              GRAFANA                         │ │
                    │  │  • Pre-built rt19 Overview dashboard        │ │
                    │  │  • 10 panels (health, TLS, CPU, memory)    │ │
                    │  │  • Port-forward or expose via ingress      │ │
                    │  └─────────────────────────────────────────────┘ │
                    └─────────────────────────────────────────────────┘
                              ▲                    ▲
        ┌─────────────────────┤                    │
        │                     │                    │
┌───────┴──────┐  ┌───────────┴────────┐  ┌───────┴──────────┐
│  rt19 ns     │  │  landing ns        │  │  AKS Nodes       │
│  Pods        │  │  Pods              │  │  kubelet metrics  │
│  /metrics    │  │  /metrics          │  │  node-exporter    │
└──────────────┘  └────────────────────┘  └──────────────────┘
```

### Components Deployed

| Component | Image | Purpose | Resources |
|-----------|-------|---------|-----------|
| Prometheus | `prom/prometheus:v2.52.0` | Metrics collection & storage | 256Mi-512Mi |
| Grafana | `grafana/grafana:11.1.0` | Dashboards & visualization | 128Mi-512Mi |
| Blackbox Exporter | `prom/blackbox-exporter:v0.25.0` | HTTPS endpoint probing | 64Mi-128Mi |
| kube-state-metrics | `kube-state-metrics:v2.12.0` | K8s object state metrics | 64Mi-256Mi |

**Total overhead**: ~512Mi RAM, ~300m CPU (minimal impact on 2-node cluster)

### rt19 Service Inventory (12 Services)

| Service | Image | Port | Type | Health Check |
|---------|-------|------|------|--------------|
| control-plane | `control-plane:latest` | 8080 | Backend (Go) | `/health` |
| dashboard | `dashboard:latest` | 8080 | Frontend (Nginx→React) | `/` |
| auth-service | `auth-service:latest` | 8097 | Backend (Go) | — |
| mcp-gateway | `mcp-gateway:latest` | 8091 | Backend (Go) | `/healthz` |
| discovery | `discovery:latest` | 8090 | Backend (Python) | `/health` |
| esign-service | `esign-service:latest` | 8096 | Backend (Go) | — |
| **esign-landing** | `esign-landing:latest` | 3001 | Frontend (Nginx→React) | `/healthz` |
| **aaic-service** | `aaic-service:latest` | 5056 | Backend (Go) | `/api/aaic/info` |
| **auditor-dashboard** | `auditor-dashboard:latest` | 80 | Frontend (Nginx→React) | `/` |
| **marketplace-service** | `marketplace-service:latest` | 8097 | Backend (Go) | `/healthz` |
| **ai-finops-service** | `ai-finops-service:latest` | 8092 | Backend (Go) | `/healthz` |
| postgres + redis | Official images | 5432/6379 | Data stores | TCP |

### AKS Deployment Gotchas (Learned the Hard Way)

> These were discovered during the live rt19 deployment on Azure AKS. Apply to ALL cloud K8s clusters.

| # | Issue | Symptom | Fix |
|---|-------|---------|-----|
| 1 | **PVC permissions — Prometheus** | `permission denied` on `/prometheus/queries.active` | Add `securityContext.fsGroup: 65534` + `runAsUser: 65534` |
| 2 | **PVC permissions — Grafana** | `'/var/lib/grafana' is not writable` | Add `securityContext.fsGroup: 472` + `runAsUser: 472` |
| 3 | **initContainer blocked on AKS** | `Init:CreateContainerConfigError` | Don't use `runAsUser: 0` in initContainers — AKS blocks it. Use `fsGroup` alone |
| 4 | **Grafana dashboards empty** | File provisioning ignores JSON | Dashboard JSON must be raw object, NOT wrapped in `{"dashboard": {...}, "overwrite": true}` (that format is for the HTTP API, not file provisioning) |
| 5 | **Dashboard ConfigMap mount conflict** | Dashboards not loaded | Mount dashboards to `/etc/grafana/dashboards`, NOT `/var/lib/grafana/dashboards` — the data PVC at `/var/lib/grafana` shadows it |
| 6 | **Datasource UID mismatch** | Panels show "No data" | Add `uid: prometheus` to datasource config; dashboard panels reference it by UID |
| 7 | **CPU/Memory panels empty** | "No data" on CPU, Memory, Node panels | Install `node-exporter` via Helm + add `kubelet-cadvisor` and `kubelet` scrape jobs to Prometheus config |
| 8 | **metrics-server resource limit** | `Invalid value: "200Mi": must be less than or equal to memory limit of 104Mi` | Patch: `kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"256Mi"}}}]'` |
| 9 | **ConfigMap not picked up after update** | Prometheus uses old config after `kubectl apply` | Delete the pod (`kubectl delete pod -l app=prometheus -n monitoring`) — `rollout restart` may mount stale ConfigMap |
| 10 | **Dashboard port 80 permission denied** | `bind() to 0.0.0.0:80 failed (13: Permission denied)` | Dockerfile has `USER nginx` (non-root) — change nginx to `listen 8080`, set `targetPort: 8080` in K8s |
| 11 | **Secret name mismatch** | `CreateContainerConfigError` — secret not found | Secret is `rt19-db-secret` (singular), not `rt19-db-secrets`. Always `kubectl get secrets -n rt19` to verify |
| 12 | **Dashboard env vars default to Docker** | nginx crashes on `host.docker.internal` | Add env overrides in K8s: `FINOPS_UPSTREAM`, `AAIC_UPSTREAM`, `MARKETPLACE_UPSTREAM`, `BILLING_UPSTREAM` |
| 13 | **ARM64 image platform** | `no match for platform in manifest` | AKS `Standard_B2pls_v2` nodes are ARM. Build with `--platform linux/arm64` |

### Post-Deploy Extras (Not in 05-monitoring.yaml)

These are installed separately after the initial monitoring stack:

```bash
# 1. Install node-exporter (fills Node CPU & Memory panel)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring

# 2. Install metrics-server (enables kubectl top)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Then patch resource limits if needed (see gotcha #8)
```

---

## 3. Grafana Dashboards

### Pre-Configured: rt19 Overview Dashboard

The `05-monitoring.yaml` includes a pre-provisioned Grafana dashboard with 10 panels:

| # | Panel | What It Shows |
|---|-------|---------------|
| 1 | **Public Endpoints — Up/Down** | Green/Red status for all 5 public sites |
| 2 | **TLS Certificate Expiry** | Days until cert expiry (red < 14d, green > 30d) |
| 3 | **Endpoint Response Time** | Latency graph per public endpoint (ms) |
| 4 | **Pod Status — rt19** | Table of all pods and their phase (Running/Pending/Failed) |
| 5 | **Pod Status — Landing** | Same for landing namespace |
| 6 | **Container CPU Usage** | CPU % per container over time |
| 7 | **Container Memory Usage** | Memory MB per container over time |
| 8 | **Pod Restarts (1h)** | Restart count (orange > 1, red > 3) |
| 9 | **Node CPU & Memory** | Node-level resource utilization |
| 10 | **Persistent Volume Usage** | PVC usage % (red > 90%) |

### Access Grafana

```bash
# Option 1: Port-forward (private, no setup)
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Option 2: Expose via ingress (public — uncomment in 05-monitoring.yaml)
# Add DNS: grafana.rt19.runtimeai.io → Load Balancer IP
# Uncomment the Ingress block at the bottom of 05-monitoring.yaml
kubectl apply -f deployment/scripts/rt19/k8s/05-monitoring.yaml
```

### Useful PromQL Queries

```promql
# ── Public endpoint uptime ──
probe_success{job="blackbox-https"}

# ── Response time per endpoint ──
probe_duration_seconds{job="blackbox-https"} * 1000

# ── TLS cert days remaining ──
(probe_ssl_earliest_cert_expiry{job="blackbox-https"} - time()) / 86400

# ── Pods not running ──
kube_pod_status_phase{namespace=~"rt19|runtimeai-landing", phase!="Running"} == 1

# ── Container restarts in last hour ──
increase(kube_pod_container_status_restarts_total{namespace=~"rt19|runtimeai-landing"}[1h])

# ── CPU usage per pod (%) ──
rate(container_cpu_usage_seconds_total{namespace="rt19", container!="POD"}[5m]) * 100

# ── Memory usage per pod (MB) ──
container_memory_working_set_bytes{namespace="rt19", container!="POD"} / 1048576

# ── PV usage (%) ──
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100
```

---

## 4. Health Monitor Script

A standalone bash script that doesn't require Prometheus/Grafana.

### Usage

```bash
cd deployment/scripts/rt19

# One-shot health check
./health-monitor.sh

# Continuous monitoring (refreshes every 30s)
./health-monitor.sh --watch

# JSON output (for CI/CD pipelines or alerting)
./health-monitor.sh --json

# Slack notification
SLACK_WEBHOOK="https://hooks.slack.com/services/..." ./health-monitor.sh --slack
```

### What It Checks

| Category | Checks |
|----------|--------|
| **Public Endpoints** | HTTP status + response time for all 5 sites |
| **TLS Certificates** | Expiry date for all 5 domains (warns < 30d, alerts < 7d) |
| **rt19 Pods** | Status + restart count for 8 services |
| **Landing Pods** | Status + restart count for 3 services |
| **PostgreSQL** | `pg_isready` connectivity check |
| **Redis** | `PING` → `PONG` check |
| **Node Resources** | `kubectl top nodes` CPU/Memory |
| **PVC Usage** | Persistent volume claim status |

### Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RuntimeAI rt19 — Health Monitor
  Fri Mar 14 02:00:00 PDT 2026
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

── Public Endpoints ────────────────────────────────────────
  ✓  Landing Page              HTTP 200   234ms
  ✓  SaaS Admin                HTTP 200   189ms
  ✓  Dashboard                 HTTP 200   312ms
  ✓  Control Plane API         HTTP 200   145ms
  ✓  eSign Landing             HTTP 200   201ms

── TLS Certificates ────────────────────────────────────────
  ✓  www.runtimeai.io          TLS: Valid for 89d
  ✓  admin.runtimeai.io        TLS: Valid for 89d
  ✓  app.rt19.runtimeai.io     TLS: Valid for 89d
  ✓  api.rt19.runtimeai.io     TLS: Valid for 89d
  ✓  esign.rt19.runtimeai.io   TLS: Valid for 89d

── rt19 Pods ───────────────────────────────────────────────
  ✓  control-plane             Running (0 restarts)
  ✓  dashboard                 Running (0 restarts)
  ✓  auth-svc                  Running (0 restarts)
  ✓  mcp-gateway               Running (0 restarts)
  ✓  discovery                 Running (0 restarts)
  ✓  esign-service             Running (0 restarts)
  ✓  postgres                  Running (0 restarts)
  ✓  redis                     Running (0 restarts)

── Landing Pods ────────────────────────────────────────────
  ✓  runtimeai-landing         Running (0 restarts)
  ✓  landing-backend           Running (0 restarts)
  ✓  saas-admin-app            Running (0 restarts)

── Data Layer ──────────────────────────────────────────────
  ✓  PostgreSQL                Accepting connections
  ✓  Redis                     PONG

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ALL CHECKS PASSED  —  24/24 passed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Automate with Cron

```bash
# Check every 5 minutes, alert on failure
*/5 * * * * /path/to/health-monitor.sh --slack >> /var/log/rt19-health.log 2>&1
```

---

## 5. Azure Monitor Integration

### Enable AKS Monitoring Add-on (Optional)

Azure Monitor provides managed monitoring without running Prometheus in-cluster.

```bash
# Enable Container Insights (adds ~$10/mo for basic tier)
az aks enable-addons \
  --resource-group runtimeai-rg \
  --name runtimeai-aks \
  --addons monitoring \
  --workspace-resource-id "/subscriptions/<SUB_ID>/resourceGroups/runtimeai-rg/providers/Microsoft.OperationalInsights/workspaces/runtimeai-logs"

# Create Log Analytics workspace first (if not exists)
az monitor log-analytics workspace create \
  --resource-group runtimeai-rg \
  --workspace-name runtimeai-logs \
  --location westus2

# View in Azure Portal:
# Azure Portal → Kubernetes services → runtimeai-aks → Insights
```

### Azure Monitor vs Self-Hosted Prometheus

| Feature | Azure Monitor | Prometheus (05-monitoring.yaml) |
|---------|--------------|-------------------------------|
| **Cost** | ~$10-30/mo | $0 (runs in existing nodes) |
| **Setup** | One command | `kubectl apply` |
| **Dashboards** | Azure Portal | Grafana (richer) |
| **Custom metrics** | KQL queries | PromQL (more flexible) |
| **Public endpoint probing** | ❌ (needs separate setup) | ✅ Built-in (Blackbox Exporter) |
| **Alerting** | Azure Alerts (email, SMS) | Grafana Alerts + Slack |
| **Retention** | 30d free, 90d paid | 15d (configurable) |
| **Recommendation** | Use for node-level insights | Use for app-level monitoring |

> **Our setup**: Use **self-hosted Prometheus + Grafana** for application monitoring
> and **optionally** add Azure Monitor for node-level insights if budget allows.

---

## 6. Traffic Analysis

### NGINX Ingress Metrics

The NGINX ingress controller exposes Prometheus metrics by default.

```bash
# Enable metrics (if not already enabled)
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true
```

### Key Traffic PromQL Queries

```promql
# ── Requests per second by host ──
sum by (host) (rate(nginx_ingress_controller_requests[5m]))

# ── Requests per second by status code ──
sum by (status) (rate(nginx_ingress_controller_requests[5m]))

# ── 4xx errors by host ──
sum by (host) (rate(nginx_ingress_controller_requests{status=~"4.."}[5m]))

# ── 5xx errors by host ──
sum by (host) (rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))

# ── Request latency (p95) by host ──
histogram_quantile(0.95, sum by (host, le) (rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])))

# ── Bandwidth by host ──
sum by (host) (rate(nginx_ingress_controller_bytes_sent[5m]))

# ── Top paths (by request count) ──
topk(10, sum by (path) (rate(nginx_ingress_controller_requests[5m])))
```

### Traffic Dashboard Panels

Add these to your Grafana dashboard for traffic analysis:

| Panel | Query | Type |
|-------|-------|------|
| Requests/sec by Site | `sum by (host) (rate(nginx_ingress_controller_requests[5m]))` | Time series |
| Error Rate | `sum by (host) (rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))` | Time series |
| p95 Latency | `histogram_quantile(0.95, ...)` | Time series |
| Status Code Breakdown | `sum by (status) (rate(nginx_ingress_controller_requests[5m]))` | Pie chart |
| Top 10 Paths | `topk(10, sum by (path) (rate(...)))` | Table |
| Bandwidth (MB/s) | `sum by (host) (rate(nginx_ingress_controller_bytes_sent[5m])) / 1048576` | Time series |

---

## 7. Alerting Setup

### Grafana Alerts (Built-in)

Configure alerts in Grafana UI:

1. **Navigate**: Grafana → Alerting → Alert Rules → New
2. **Create rules** for:

| Alert | Condition | Severity |
|-------|-----------|----------|
| Endpoint Down | `probe_success == 0` for 2m | Critical |
| TLS Cert Expiring | `cert_expiry_days < 14` | Warning |
| TLS Cert Expired | `cert_expiry_days < 1` | Critical |
| Pod CrashLooping | `restarts > 5 in 1h` | Critical |
| High CPU | `cpu_usage > 80%` for 5m | Warning |
| High Memory | `memory_usage > 80%` for 5m | Warning |
| PV Nearly Full | `pv_usage > 90%` | Critical |
| High Error Rate | `5xx_rate > 1/s` for 5m | Warning |

### Slack Notification Channel

```bash
# In Grafana:
# 1. Go to: Alerting → Contact Points → Add
# 2. Select: Slack
# 3. Webhook URL: https://hooks.slack.com/services/...
# 4. Channel: #runtimeai-alerts
# 5. Test → Save
```

### Prometheus AlertManager (Alternative)

If you prefer AlertManager over Grafana alerts:

```yaml
# Add to 05-monitoring.yaml:
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      slack_api_url: 'https://hooks.slack.com/services/...'
    route:
      group_by: ['alertname']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'slack'
    receivers:
      - name: 'slack'
        slack_configs:
          - channel: '#runtimeai-alerts'
            send_resolved: true
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

---

## 8. Troubleshooting Runbook

### Endpoint Down

```bash
# 1. Check if pod is running
kubectl get pods -n rt19 -l app=control-plane

# 2. Check pod logs
kubectl logs -n rt19 -l app=control-plane --tail=50

# 3. Check ingress
kubectl get ingress -n rt19

# 4. Check cert status
kubectl get certificates -n rt19

# 5. Restart the service
kubectl rollout restart deployment/control-plane -n rt19
```

### High Memory / OOMKilled

```bash
# 1. Check current usage
kubectl top pods -n rt19

# 2. Find OOMKilled events
kubectl get events -n rt19 --field-selector reason=OOMKilled

# 3. Increase limits (edit deployment)
kubectl edit deployment/control-plane -n rt19
# Change resources.limits.memory

# 4. Or scale horizontally
kubectl scale deployment/control-plane -n rt19 --replicas=2
```

### Database Connection Issues

```bash
# 1. Check PostgreSQL pod
kubectl get pods -n rt19 -l app=postgres
kubectl logs -n rt19 -l app=postgres --tail=20

# 2. Test connectivity
kubectl exec -n rt19 deploy/postgres -- pg_isready -U runtimeai

# 3. Check connection count
kubectl exec -n rt19 deploy/postgres -- psql -U runtimeai -d authzion \
  -c "SELECT count(*) FROM pg_stat_activity;"

# 4. If too many connections, restart the DB
kubectl rollout restart deployment/postgres -n rt19
```

### TLS Certificate Not Renewing

```bash
# 1. Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager --tail=50

# 2. Check certificate status
kubectl get certificates -A
kubectl describe certificate <name> -n rt19

# 3. Check challenges
kubectl get challenges -A

# 4. Force renewal
kubectl delete certificate <name> -n rt19
kubectl apply -f deployment/scripts/rt19/k8s/04-ingress-tls.yaml
```

### Pod CrashLooping

```bash
# 1. Check events
kubectl describe pod <pod-name> -n rt19

# 2. Check previous logs
kubectl logs <pod-name> -n rt19 --previous

# 3. Common causes:
#    - OTEL crash → Set OTEL_SDK_DISABLED=true
#    - DB not ready → Check postgres pod first
#    - Secret missing → kubectl get secrets -n rt19
#    - Port conflict → Check targetPort matches container port
```

---

## 9. Cost Impact

### Self-Hosted Monitoring Cost

| Component | Additional Cost |
|-----------|----------------|
| Prometheus PVC (10Gi) | ~$0.80/mo (Azure managed disk) |
| Grafana PVC (2Gi) | ~$0.16/mo |
| CPU/Memory overhead | $0 (uses spare capacity on existing nodes) |
| **Total** | **~$1/mo** |

### Azure Monitor Cost (Optional)

| Feature | Cost |
|---------|------|
| Container Insights (basic) | ~$10/mo |
| Log Analytics (500MB/day) | ~$5/mo |
| Alerts (10 rules) | ~$1.50/mo |
| **Total** | **~$17/mo** |

> **Recommendation**: Start with self-hosted Prometheus + Grafana (~$1/mo).
> Add Azure Monitor later if you need native Azure integration or longer retention.

---

## Quick Reference

| Task | Command |
|------|---------|
| Deploy monitoring | `kubectl apply -f k8s/05-monitoring.yaml` |
| Access Grafana | `kubectl port-forward svc/grafana 3000:3000 -n monitoring` |
| Health check | `./health-monitor.sh` |
| Watch mode | `./health-monitor.sh --watch` |
| JSON output | `./health-monitor.sh --json` |
| Check Prometheus | `kubectl port-forward svc/prometheus 9090:9090 -n monitoring` |
| View pod metrics | `kubectl top pods -n rt19` |
| View node metrics | `kubectl top nodes` |
| View logs | `kubectl logs -n rt19 -l app=<service> --tail=50` |
| Restart a service | `kubectl rollout restart deployment/<service> -n rt19` |

# TOPS-023: Monitoring — Prometheus Configuration & Scrape Targets

## Specification

Create complete Prometheus configuration (`monitoring/prometheus/prometheus.yml`) with scrape targets for all 31 rt19 services, external dependencies (RDS, Redis, QuantumVault), and K8s cluster metrics.

Scrape targets include:
- K8s API server and kubelet (cluster health)
- Node exporter (host metrics: CPU, memory, disk, network)
- Container metrics (cAdvisor via kubelet)
- Service metrics (per-service: latency, error rate, throughput)
- External: PostgreSQL exporter, Redis exporter, QuantumVault exporter
- Alerts: define alert rules (high CPU, high error rate, crashes)

## Acceptance Criteria

- [ ] Configuration file created at `monitoring/prometheus/prometheus.yml`
- [ ] Global scrape interval: 30s (default), evaluation interval: 30s
- [ ] K8s cluster scrape: kube-apiserver, kubelet, kube-proxy (all nodes)
- [ ] Service discovery: K8s service discovery labels (all services auto-discovered)
- [ ] Relabeling: extract namespace, pod, service from K8s metadata
- [ ] Scrape targets for all 31 rt19 services (port-based discovery)
- [ ] External targets: RDS (via RDS exporter), Redis (6379), QuantumVault (8200)
- [ ] Retention policy: 30 days default, 90 days for production
- [ ] Alert rules defined in separate file: `alert.rules.yml`
- [ ] Alerts include: high CPU (> 80%), high memory (> 85%), pod crash loops, high error rate (> 5%)
- [ ] Committed to feature branch `TOPS-023-monitoring-prometheus-config`

## Effort Estimate

3 hours

## Dependencies

Blocked by: TOPS-001 through TOPS-008 (services must be deployed)
Blocks: TOPS-024 (Grafana dashboards), TOPS-025 (Alertmanager)

## Implementation Notes

- Prometheus scrapes every pod in rt19 namespace on port 9090 (default metrics port)
- K8s service discovery uses bearer token from prometheus service account
- Relabeling renames labels (e.g., kubernetes_namespace → ns) for dashboard display
- Alert rules use PromQL (Prometheus Query Language)
- Retention: 1.5GB per day (estimate); allocate storage accordingly
- Thresholds (CPU, memory) configurable via ConfigMap

## Verification

```bash
cd monitoring/prometheus
# Validate prometheus.yml syntax
promtool check config prometheus.yml
# Check alert rules
promtool check rules alert.rules.yml
# Simulate scrape targets (requires prometheus running)
curl http://localhost:9090/api/v1/targets
```

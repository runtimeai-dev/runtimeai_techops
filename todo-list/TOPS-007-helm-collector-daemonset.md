# TOPS-007: Helm Chart — Collector Agent (DaemonSet)

## Specification

Create Helm chart for Collector DaemonSet. Collector is a lightweight agent that runs on every K8s node to:
- Collect kernel metrics (CPU, memory, I/O, network)
- Gather container logs (stdout/stderr)
- Send metrics to Prometheus via node-exporter protocol
- Send logs to log aggregator (ELK/Loki)

## Acceptance Criteria

- [ ] Chart created at `helm/collector/`
- [ ] Deployment type: DaemonSet (runs on every node)
- [ ] `values.yaml` includes: image, resources, metrics_port, log_endpoint
- [ ] `helm lint collector/` passes
- [ ] `helm template collector/` renders valid DaemonSet
- [ ] Resource limits: requests 100m CPU, 128Mi mem; limits 200m, 256Mi
- [ ] Node affinity configured (tolerate all taints)
- [ ] Volume mounts: /var/log, /var/run (read-only)
- [ ] Service monitor configured for Prometheus scraping
- [ ] Committed to feature branch `TOPS-007-helm-collector-daemonset`

## Effort Estimate

2 hours

## Dependencies

Blocked by: None
Blocks: TOPS-023 (monitoring stack)

## Implementation Notes

- DaemonSet ensures 1 collector pod per node (tolerates all taints/nodeSelectors)
- Collector is designed to be low-overhead (< 100m CPU per node)
- Metrics exported in Prometheus format on port 9100 (node_exporter convention)
- Logs streamed to aggregator endpoint (gRPC or HTTP)
- Does not require cluster-admin; reads pod events via RBAC

## Verification

```bash
helm lint helm/collector/
helm template helm/collector/ | grep "kind: DaemonSet"
helm template helm/collector/ | grep -A 5 "tolerations"
# Ensure it renders without missing values
helm template helm/collector/ --debug | grep -i "error\|fail"
```

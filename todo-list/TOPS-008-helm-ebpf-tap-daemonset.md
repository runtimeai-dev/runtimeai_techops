# TOPS-008: Helm Chart — eBPF TAP Agent (DaemonSet)

## Specification

Create Helm chart for eBPF TAP (Traffic Analysis Probe) DaemonSet. eBPF TAP runs on every node and provides:
- Kernel-level network traffic capture (zero-copy via eBPF)
- Packet loss detection and flow reconstruction
- Per-pod egress/ingress metrics
- Anomaly detection (unusual port activity, protocol violations)

## Acceptance Criteria

- [ ] Chart created at `helm/ebpf-tap/`
- [ ] Deployment type: DaemonSet with privileged containers
- [ ] `values.yaml` includes: image, resources, metrics_port, capture_interface
- [ ] `helm lint ebpf-tap/` passes
- [ ] `helm template ebpf-tap/` renders valid DaemonSet
- [ ] Container security context: privileged=true, capability NET_ADMIN
- [ ] Resource limits: requests 200m CPU, 256Mi mem; limits 500m, 512Mi
- [ ] hostNetwork: true (required for packet capture)
- [ ] Host mount: /proc (read-only)
- [ ] Service monitor configured for Prometheus scraping (port 8090)
- [ ] Committed to feature branch `TOPS-008-helm-ebpf-tap-daemonset`

## Effort Estimate

2.5 hours

## Dependencies

Blocked by: None
Blocks: TOPS-023 (monitoring stack), anomaly detection features

## Implementation Notes

- eBPF TAP requires Linux kernel 5.10+ (check node prerequisites)
- Privileged container required for packet capture (security trade-off; only on trusted nodes)
- Kernel eBPF module compiled at container startup (adds ~10s init delay)
- Metrics exported in Prometheus format (custom metrics for packet loss, flow count, anomalies)
- Node affinity can exclude nodes if eBPF not available
- Generates high cardinality metrics; ensure Prometheus has sufficient disk

## Verification

```bash
helm lint helm/ebpf-tap/
helm template helm/ebpf-tap/ | grep "kind: DaemonSet"
helm template helm/ebpf-tap/ | grep -A 5 "securityContext"
# Check for privileged flag
helm template helm/ebpf-tap/ | grep "privileged"
```

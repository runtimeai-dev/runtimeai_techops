# Disk Space Critical

## Symptoms
- Kubelet eviction: `DiskPressure`, `InodesPressure`
- Pod eviction: `Evicted`
- Application errors: `No space left on device`

## Recovery

```bash
# Check disk usage per node
kubectl top nodes

# Check disk usage per pod
kubectl top pods -A --sort-by=memory

# Find large containers
kubectl get pods -A -o json | jq '.items[] | {pod: .metadata.name, ns: .metadata.namespace, size: .spec.containers[].resources.limits.ephemeralStorage}'

# Clean up old images
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# Restart kubelet on node with high disk
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# Clean host disk manually
# kubectl uncordon <node>

# Check Loki logs storage
du -sh /var/lib/loki/
# Reduce retention: edit loki-config.yaml
```

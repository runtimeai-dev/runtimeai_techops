# Pod Crash-Loop Recovery

## Symptoms
- Pod repeatedly restarting: `kubectl get pod -n rt19 <pod-name>`
- Status: `CrashLoopBackOff` or `Error`
- Restart count increasing

## Diagnostics

```bash
# Check pod status
kubectl get pod -n rt19 <pod-name> -o json | jq '.status'

# View logs from crashed pod
kubectl logs -n rt19 <pod-name> --previous

# Describe pod events
kubectl describe pod -n rt19 <pod-name>

# Check resource limits
kubectl get pod -n rt19 <pod-name> -o json | jq '.spec.containers[0].resources'
```

## Common Causes & Solutions

### 1. OOMKilled (Out of Memory)
**Symptom**: `Exit Code: 137`, events show `OOMKilled`

**Recovery**:
```bash
# Increase memory limit in deployment
kubectl set resources deployment/<name> -n rt19 \
  --limits=memory=2Gi --requests=memory=1Gi

# Or edit directly
kubectl edit deployment <name> -n rt19
# Change: spec.template.spec.containers[0].resources.limits.memory
```

### 2. Unhealthy Liveness Probe
**Symptom**: Pod starts but fails liveness probe

**Recovery**:
```bash
# Check probe endpoints
kubectl get pod -n rt19 <pod-name> -o json | jq '.spec.containers[0].livenessProbe'

# Manually test endpoint
kubectl exec -n rt19 <pod-name> -- curl http://localhost:8080/health

# If endpoint is wrong, update:
kubectl set env deployment/<name> -n rt19 HEALTH_CHECK_PATH=/healthz
```

### 3. Missing ConfigMap or Secret
**Symptom**: Pod exits with "No such file or directory"

**Recovery**:
```bash
# Verify ConfigMap exists
kubectl get configmap -n rt19

# If missing, restore from git
kubectl apply -f k8s/rt19/configmap.yaml

# Or create manually
kubectl create configmap <name> --from-file=config.yaml -n rt19
```

### 4. Image Pull Error
**Symptom**: Events show `ImagePullBackOff`

**Recovery**:
```bash
# Check image URL
kubectl get pod -n rt19 <pod-name> -o json | jq '.spec.containers[0].image'

# Verify image exists in registry
az acr repository show --name runtimeaicr --image <image>

# If missing, rebuild and push
docker build -t runtimeaicr.azurecr.io/rt19/<service>:latest .
docker push runtimeaicr.azurecr.io/rt19/<service>:latest

# Update deployment
kubectl set image deployment/<name> -n rt19 \
  <container>=runtimeaicr.azurecr.io/rt19/<service>:latest
```

## Verification

```bash
# Monitor pod recovery
kubectl get pod -n rt19 <pod-name> --watch

# Confirm pod is ready
kubectl wait --for=condition=Ready pod/<pod-name> -n rt19 --timeout=300s
```

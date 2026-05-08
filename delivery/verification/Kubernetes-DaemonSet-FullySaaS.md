# Kubernetes DaemonSet Discovery — Fully SaaS Deployment Guide

> **Version**: 1.0.0
> **Last Updated**: 2026-04-16
> **Target Environment**: RuntimeAI Fully SaaS (api.rt19.runtimeai.io)
> **Minimum Requirements**: Kubernetes 1.24+, Helm 3.x

---

## Overview

The RuntimeAI DaemonSet collector deploys a lightweight pod on every node in your Kubernetes cluster. It scans for AI workloads (containers, services, pods running LLM inference), reports findings to the RuntimeAI control plane, and tags them in the Shadow AI Inbox.

### What Gets Discovered

| # | Category | Method |
|---|---|---|
| 1 | AI container images | Image name matching (ollama, vllm, triton, tgi, jupyter, comfyui) |
| 2 | GPU workloads | Pods with `nvidia.com/gpu` resource requests |
| 3 | AI service ports | Services exposing known AI ports (11434, 8080, 8000) |
| 4 | MCP servers | Pods with MCP-related labels or environment variables |
| 5 | Model volumes | PVCs mounted at `/models`, `/weights`, `/checkpoints` |
| 6 | LLM egress | DNS queries to known LLM API domains from pods |

---

## Prerequisites

1. **Kubernetes 1.24+** (EKS, AKS, GKE, or self-managed)
2. **Helm 3.x** installed
3. **kubectl** configured for your cluster
4. **Tenant credentials**: Tenant ID + API Key (from Dashboard → Settings → API Keys)
5. **RBAC**: The DaemonSet needs read-only access to pods, services, and nodes

---

## Installation

### Method 1: Helm Chart (Recommended)

```bash
helm repo add runtimeai https://charts.runtimeai.io
helm repo update

helm install runtimeai-discovery runtimeai/discovery-agent \
  --namespace runtimeai-system \
  --create-namespace \
  --set tenant.id=<your-tenant-id> \
  --set tenant.apiKey=<your-api-key> \
  --set controlPlane.url=https://api.rt19.runtimeai.io \
  --set scanner.schedule="0 */6 * * *"
```

### Method 2: kubectl Apply

```yaml
# runtimeai-discovery-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: runtimeai-discovery
  namespace: runtimeai-system
  labels:
    app: runtimeai-discovery
spec:
  selector:
    matchLabels:
      app: runtimeai-discovery
  template:
    metadata:
      labels:
        app: runtimeai-discovery
    spec:
      serviceAccountName: runtimeai-discovery
      containers:
      - name: scanner
        image: runtimeaicr.azurecr.io/discovery-agent:latest
        env:
        - name: RUNTIMEAI_TENANT_ID
          value: "<your-tenant-id>"
        - name: RUNTIMEAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: runtimeai-discovery-secret
              key: api-key
        - name: RUNTIMEAI_API_URL
          value: "https://api.rt19.runtimeai.io"
        - name: SCAN_INTERVAL
          value: "21600"  # 6 hours
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
        securityContext:
          readOnlyRootFilesystem: true
          runAsNonRoot: true
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: runtimeai-discovery
  namespace: runtimeai-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: runtimeai-discovery
rules:
- apiGroups: [""]
  resources: ["pods", "services", "nodes", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: runtimeai-discovery
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: runtimeai-discovery
subjects:
- kind: ServiceAccount
  name: runtimeai-discovery
  namespace: runtimeai-system
```

```bash
kubectl create namespace runtimeai-system
kubectl create secret generic runtimeai-discovery-secret \
  --namespace runtimeai-system \
  --from-literal=api-key=<your-api-key>
kubectl apply -f runtimeai-discovery-daemonset.yaml
```

---

## Verification

```bash
# Check DaemonSet is running on all nodes
kubectl get ds -n runtimeai-system
# Expected: DESIRED = CURRENT = READY

# Check logs
kubectl logs -n runtimeai-system -l app=runtimeai-discovery --tail=20

# Verify in Dashboard
# Navigate to Discovery → Shadow AI Inbox → filter by source: daemonset_collector
```

---

## Dashboard Verification

1. Log into `https://app.rt19.runtimeai.io`
2. Go to **Discovery → Shadow AI Inbox**
3. Filter by **Source: daemonset_collector**
4. Verify findings include pod names, namespaces, and image names

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Pods stuck in `Pending` | Check node resources: `kubectl describe ds runtimeai-discovery -n runtimeai-system` |
| `403 Forbidden` from K8s API | Verify ClusterRoleBinding exists: `kubectl get clusterrolebinding runtimeai-discovery` |
| No findings in Dashboard | Check pod logs: `kubectl logs -n runtimeai-system -l app=runtimeai-discovery` |
| High memory usage | Reduce scan frequency via `SCAN_INTERVAL` env var |
| Cannot pull image | Ensure cluster has access to `runtimeaicr.azurecr.io` (or use `imagePullSecrets`) |

---

## Uninstall

```bash
# Helm
helm uninstall runtimeai-discovery -n runtimeai-system

# kubectl
kubectl delete -f runtimeai-discovery-daemonset.yaml
kubectl delete namespace runtimeai-system
```

# 01 — Azure rt19 Setup (No Docker)

**Audience**: DevOps / Platform Engineer
**Pod**: rt19 — Azure AKS
**Last Updated**: 2026-03-17

---

## Prerequisites

- Azure CLI (`az`) installed and logged in
- `kubectl` installed (v1.28+)
- `helm` installed (v3.12+)
- Access to Azure subscription `87e9e058-3b71-4d1b-b736-4d8475ac5299`
- Access to resource group `runtimeai-rg`

---

## 1. Connect to the AKS Cluster

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "87e9e058-3b71-4d1b-b736-4d8475ac5299"

# Get kubectl credentials
az aks get-credentials --resource-group runtimeai-rg --name runtimeai-aks

# Verify connection
kubectl get nodes
# Expected: 2 nodes (Standard_B2pls_v2, ARM64)
```

## 2. Verify Namespaces

```bash
kubectl get namespaces
# Expected:
#   rt19                Active
#   runtimeai-landing   Active
#   ingress-nginx       Active
#   cert-manager        Active
```

## 3. Verify All Pods Are Running

```bash
kubectl get pods -n rt19
# Expected: All pods in Running/Ready state
#   control-plane-xxx       2/2     Running
#   dashboard-xxx           2/2     Running
#   auth-svc-xxx            2/2     Running
#   mcp-gateway-xxx         2/2     Running
#   discovery-xxx           1/1     Running
#   esign-service-xxx       1/1     Running
#   esign-landing-xxx       1/1     Running
#   aaic-service-xxx        1/1     Running
#   auditor-dashboard-xxx   1/1     Running
#   marketplace-xxx         1/1     Running
#   ai-finops-xxx           1/1     Running
#   postgres-0              1/1     Running
#   redis-xxx               1/1     Running
```

```bash
kubectl get pods -n runtimeai-landing
# Expected:
#   website-singlepage-xxx  1/1     Running
#   saas-admin-app-xxx      1/1     Running
#   landing-backend-xxx     1/1     Running
```

## 4. Verify Ingress & TLS

```bash
kubectl get ingress -n rt19
kubectl get ingress -n runtimeai-landing

# Verify TLS certificates
kubectl get certificates -n rt19
kubectl get certificates -n runtimeai-landing
# All should show READY = True
```

## 5. Verify DNS Resolution

```bash
# Test all public endpoints
for domain in \
  runtimeai.io \
  admin.runtimeai.io \
  app.rt19.runtimeai.io \
  api.rt19.runtimeai.io \
  esign.rt19.runtimeai.io \
  auditor.rt19.runtimeai.io \
  marketplace.rt19.runtimeai.io \
  finops.rt19.runtimeai.io; do
  echo -n "$domain → "
  curl -so /dev/null -w "%{http_code}" "https://$domain" 2>/dev/null || echo "UNREACHABLE"
done
```

## 6. Azure Resources Reference

### Compute

| Resource | Value |
|----------|-------|
| Cluster Name | `runtimeai-aks` |
| Resource Group | `runtimeai-rg` |
| Region | `westus2` |
| AKS Tier | Free (no SLA) |
| Node Pool | 2× `Standard_B2pls_v2` (ARM64, 2 vCPU, 4 GB) |
| Auto-scaling | min: 2, max: 4 |
| Network Plugin | `azure` (CNI) |
| Network Policy | `calico` |
| Service CIDR | `172.16.0.0/16` |
| DNS Service IP | `172.16.0.10` |

### Storage

| Resource | Value |
|----------|-------|
| PostgreSQL PVC | 10 Gi (`managed-csi`) |
| PGDATA Path | `/var/lib/postgresql/data/pgdata` |
| Redis Memory | 256 MB limit |

### Container Registry

| Resource | Value |
|----------|-------|
| Registry | `runtimeaicr.azurecr.io` |
| Tier | Basic (10 GB) |
| Auth | Managed identity (AcrPull) |

### Networking

| Resource | Value |
|----------|-------|
| VNet | `runtimeai-vnet` (`10.0.0.0/16`) |
| AKS Subnet | `aks-subnet` (`10.0.1.0/24`) |
| DB Subnet | `db-subnet` (`10.0.2.0/24`) |
| Ingress | NGINX Ingress Controller |
| TLS | cert-manager + Let's Encrypt (HTTP-01) |

### Secrets (K8s)

| Secret Name | Contents |
|-------------|----------|
| `rt19-db-secret` | `DATABASE_URL` |
| `rt19-app-secrets` | `RUNTIMEAI_ADMIN_SECRET`, `JWT_SECRET`, `API_KEY_SECRET`, `SESSION_SECRET`, `REDIS_URL` |
| `rt19-email-secrets` | `SENDGRID_API_KEY`, `ESIGN_JWT_SECRET` |
| `rt19-storage-secrets` | `AZURE_STORAGE_ACCOUNT`, `AZURE_STORAGE_KEY` |

---

## 7. Common Operations

### Restart a Service

```bash
kubectl rollout restart deployment/control-plane -n rt19
kubectl rollout status deployment/control-plane -n rt19
```

### View Logs

```bash
kubectl logs -n rt19 deployment/control-plane --tail=100 -f
kubectl logs -n rt19 deployment/mcp-gateway --tail=100 -f
```

### Scale a Service

```bash
kubectl scale deployment/control-plane -n rt19 --replicas=3
```

### Access PostgreSQL

```bash
kubectl exec -it postgres-0 -n rt19 -- psql -U authzion -d authzion
```

### Access Redis

```bash
kubectl exec -it deployment/redis -n rt19 -- redis-cli
```

### Build and Deploy a Service (from runtimeai-enterprise)

```bash
cd /Users/roshanshaik/work/runtimeai-enterprise
./deployment/scripts/rt19/deploy.sh control-plane
# OR deploy all:
./deployment/scripts/rt19/deploy.sh
```

### Build for ARM64 (required for rt19 nodes)

```bash
docker buildx build --platform linux/arm64 \
  -t runtimeaicr.azurecr.io/control-plane:latest \
  --push .
```

---

## 8. Known Gotchas (Lessons from rt19 Deployment)

| # | Issue | Cause | Fix |
|---|-------|-------|-----|
| 1 | `Standard_B2s` unavailable | Region capacity | Use ARM `Standard_B2pls_v2` |
| 2 | PostgreSQL `lost+found` error | Azure PVC mount | Set `PGDATA=/var/lib/postgresql/data/pgdata` |
| 3 | Service CIDR overlap | Default CIDR conflicts | Custom `--service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10` |
| 4 | Control-plane readiness fail | Wrong probe path | Probe path is `/health` (not `/healthz`) |
| 5 | Auth service port collision | K8s env injection | Name K8s service `auth-svc` (not `auth-service`) |
| 6 | Dashboard 502 | Port mismatch | Container listens on 8080, use `targetPort: 8080` |
| 7 | Landing nginx crash | Upstream DNS fail | Use `resolver 172.16.0.10 valid=30s` + FQDN variables |
| 8 | Control-plane OTEL crash | No collector | Set `OTEL_SDK_DISABLED=true` |
| 9 | Wrong admin secret env | Naming mismatch | Env var is `RUNTIMEAI_ADMIN_SECRET` (not `ADMIN_SECRET`) |
| 10 | eSign CreateContainerConfigError | Missing storage secrets | Create `rt19-storage-secrets` |
| 11 | Redis URL missing | Secret not mounted | `REDIS_URL` must be in `rt19-app-secrets` |
| 12 | ARM64 image crash | x86 image on ARM node | Build with `--platform linux/arm64` |
| 13 | Dashboard env vars wrong | Hardcoded in Dockerfile | Override `FINOPS_UPSTREAM`, `AAIC_UPSTREAM`, `MARKETPLACE_UPSTREAM` in K8s manifest |

---

## FAQ

**Q: How do I add a new node to the cluster?**
A: `az aks nodepool scale --resource-group runtimeai-rg --cluster-name runtimeai-aks --name nodepool1 --node-count 3`

**Q: How do I rotate TLS certificates?**
A: cert-manager handles rotation automatically. Force renewal: `kubectl delete certificate <name> -n rt19` and it will re-issue.

**Q: How do I update a container image?**
A: Push new image to ACR, then `kubectl set image deployment/<service> <service>=runtimeaicr.azurecr.io/<service>:<new-tag> -n rt19`

**Q: The cluster is unresponsive — what do I check?**
A: 1) `az aks show -g runtimeai-rg -n runtimeai-aks --query powerState` 2) `kubectl get nodes` 3) Check Azure portal for cluster health alerts.

**Q: How do I add a new service?**
A: 1) Add Dockerfile to the service repo 2) Build for ARM64 and push to ACR 3) Add deployment + service to `03-services.yaml` 4) Add ingress rule to `04-ingress-tls.yaml` 5) Apply manifests.

**Q: How much headroom do the nodes have?**
A: Each B2pls_v2 node has 2 vCPU + 4 GB RAM. With ~7 services per node, you're tight on memory. Monitor with `kubectl top nodes`. Scale to 3-4 nodes if needed.

**Q: Can I use Azure Managed PostgreSQL instead?**
A: Yes, but the cheapest Flexible Server is ~$13/mo. Self-hosted in AKS saves money for dev/staging. Use managed PG for production with HA requirements.

### Advanced Setup Questions

**Q: How do I set up a second pod (e.g., rt20) for a different customer?**
A: 1) Create new namespace `rt20` 2) Copy K8s manifests, update namespace and domain names 3) Add DNS records for `*.rt20.runtimeai.io` 4) Apply manifests 5) Run seed script with new tenant ID. Each pod is ~$20-30/mo incremental (shared nodes).

**Q: How do I enable network policies for pod isolation?**
A: Apply `05-sre-hardening.yaml` which includes Calico network policies. By default, only ingress from ingress-nginx and intra-namespace traffic is allowed.

**Q: How do I set up monitoring?**
A: Apply `05-monitoring.yaml` (Prometheus + Grafana + Blackbox Exporter). Access Grafana via port-forward: `kubectl port-forward svc/grafana -n monitoring 3000:3000`.

**Q: How do I do blue-green deployments?**
A: Currently not automated. Manual approach: 1) Deploy new version as separate deployment (e.g., `control-plane-v2`) 2) Update service selector to point to new deployment 3) Verify 4) Delete old deployment.

**Q: How do I back up the database?**
A: `kubectl exec postgres-0 -n rt19 -- pg_dump -U authzion authzion | gzip > backup_$(date +%Y%m%d).sql.gz`. For production, use Azure Backup or CronJob with PVC snapshots.

# AEP Gateway Routing Architecture

**Date**: May 6, 2026  
**Purpose**: Expose all 14 AEP services via public gateway API  
**Endpoint**: `https://aep-api.rt19.runtimeai.io`

---

## Overview

The AEP Gateway provides a unified API entry point for all 14 AEP services. Instead of direct port-forwarding or internal service calls, external clients call service endpoints via the gateway.

### Design Pattern

```
Client
  ↓
HTTPS → aep-api.rt19.runtimeai.io (nginx ingress)
  ↓
Path Routing
  ├─ /api/cost-control/* → cost-control:8302
  ├─ /api/audit-black-box/* → audit-black-box:8303
  ├─ /api/pii-shield/* → pii-shield:8304
  └─ ... (11 more services)
  ↓
Service Pod (JWT auth enforced)
```

### Benefits

1. **Single Endpoint**: One domain for all services (simplifies firewall rules, DNS, certs)
2. **Path-Based Routing**: Each service gets its own URL path
3. **JWT Propagation**: Auth headers pass through gateway to backend service
4. **TLS Termination**: HTTPS handled by ingress controller (not per-service)
5. **Rate Limiting**: Can apply global rate limiting at ingress layer
6. **Load Balancing**: Ingress distributes traffic to pods

---

## Architecture Details

### Ingress Configuration

**File**: `deployment/scripts/rt19/k8s/27-aep-gateway-routing-ingress.yaml`

Key components:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aep-service-routing-ingress
  namespace: aep
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
spec:
  ingressClassName: nginx
  rules:
  - host: aep-api.rt19.runtimeai.io
    http:
      paths:
      - path: /api/cost-control(/|$)(.*)    # Regex: matches /api/cost-control or /api/cost-control/...
        pathType: ImplementationSpecific
        backend:
          service:
            name: cost-control
            port:
              number: 8302
      # ... (13 more paths)
```

### Path Rewriting Rules

The nginx annotation `rewrite-target: /$2` ensures that:

- **Request**: `GET /api/cost-control/agents`
- **Path captured**: `/api/cost-control` matches group 1, `/agents` matches group 2
- **Rewrite**: Request forwarded to backend as `GET /agents`
- **Backend sees**: `GET http://cost-control:8302/agents`

This prevents double-pathing (e.g., `/api/cost-control/agents` hitting `/api/cost-control/agents` on backend).

### TLS Certificate

- **Issuer**: Let's Encrypt (via cert-manager)
- **Certificate Name**: `aep-api-rt19-tls`
- **Auto-renewal**: Yes (cert-manager handles renewal 30 days before expiry)

### Service Discovery

Kubernetes internal DNS resolves:
- `cost-control.aep.svc.cluster.local` → 10.0.x.x (service IP)
- Ingress → service IP → pod IP (via iptables)

---

## Service Routing Table

| Service | Port | Endpoint | Purpose |
|---------|------|----------|---------|
| KYA | 8301 | `/api/kya/*` | Know Your Agent (agent identity) |
| Cost Control | 8302 | `/api/cost-control/*` | Agent budget management |
| Audit Black Box | 8303 | `/api/audit-black-box/*` | Immutable audit trail (PQ-signed) |
| PII Shield | 8304 | `/api/pii-shield/*` | PII tokenization (FPE) |
| Observability | 8305 | `/api/observability/*` | Metrics & tracing |
| Fraud Shield | 8306 | `/api/fraud-shield/*` | Transaction fraud detection |
| Memory Vault | 8307 | `/api/memory-vault/*` | Encrypted context storage (QV) |
| Commerce Rails | 8308 | `/api/commerce-rails/*` | Commerce transaction processing |
| Commerce Protocol | 8309 | `/api/commerce-protocol/*` | Commerce protocol handler |
| Marketplace | 8310 | `/api/marketplace/*` | Agent marketplace registry |
| Developer Hub | 8311 | `/api/developer-hub/*` | Agent development toolkit |
| Contract Manager | 8312 | `/api/contract-manager/*` | Contract lifecycle (CLM) |
| Procurement Hub | 8313 | `/api/procurement-hub/*` | Procurement workflow |
| Finance Rail | 8314 | `/api/finance-rail/*` | Financial transaction rail |

---

## Usage Examples

### Authentication

All endpoints require JWT bearer token:

```bash
# 1. Get token (admin impersonation for testing)
ADMIN_SECRET=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv)
TOKEN=$(curl -X POST https://api.rt19.runtimeai.io/api/admin/impersonate \
  -H "X-RuntimeAI-Admin-Secret: $ADMIN_SECRET" \
  -d '{"tenant_id":"equinix-demo"}' | jq -r .token)

# 2. Call AEP service via gateway
curl -H "Authorization: Bearer $TOKEN" \
  https://aep-api.rt19.runtimeai.io/api/cost-control/agents
```

### Example Endpoints

**List agents** (Cost Control):
```
GET https://aep-api.rt19.runtimeai.io/api/cost-control/agents
Authorization: Bearer $TOKEN

Response:
{
  "agents": [
    {"id": "agent-123", "name": "Fraud-Detector", "status": "running"},
    ...
  ],
  "total": 45
}
```

**Create audit entry** (Audit Black Box):
```
POST https://aep-api.rt19.runtimeai.io/api/audit-black-box/logs
Authorization: Bearer $TOKEN
Content-Type: application/json

{
  "event_type": "AGENT_DEPLOYED",
  "details": {"agent_id": "agent-123", "version": "1.2.3"},
  "timestamp": "2026-05-06T10:30:00Z"
}

Response:
{
  "log_id": "log-abc123",
  "signature": "ML-DSA-87:...",  # PQ-safe signature
  "verified": true
}
```

**Tokenize PII** (PII Shield):
```
POST https://aep-api.rt19.runtimeai.io/api/pii-shield/tokenize
Authorization: Bearer $TOKEN
Content-Type: application/json

{
  "data": "john.doe@example.com",
  "format": "email"
}

Response:
{
  "token": "pii_8f2a9c1e...",
  "format": "email",
  "ttl_seconds": 86400
}
```

---

## Adding a New Service Route

### Step 1: Update Ingress Configuration

Add a new path entry to the Ingress spec:

```yaml
- path: /api/my-new-service(/|$)(.*)
  pathType: ImplementationSpecific
  backend:
    service:
      name: my-new-service
      port:
        number: 8999  # Service port
```

### Step 2: Create Kubernetes Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-new-service
  namespace: aep
spec:
  selector:
    app: my-new-service
  ports:
  - port: 8999
    targetPort: 8999
```

### Step 3: Deploy Service Pod

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-new-service
  namespace: aep
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-new-service
  template:
    metadata:
      labels:
        app: my-new-service
    spec:
      containers:
      - name: my-new-service
        image: runtimeaicr.azurecr.io/aep/my-new-service:latest
        ports:
        - containerPort: 8999
```

### Step 4: Test Routing

```bash
kubectl apply -f ingress-update.yaml
curl -v https://aep-api.rt19.runtimeai.io/api/my-new-service/health
```

### Step 5: Update Service Routing Table

Add entry to the table above and commit documentation update.

---

## Troubleshooting

### Service Returns 404

**Cause**: Ingress rule not matching path

**Fix**:
```bash
# Check ingress rules
kubectl get ingress -n aep aep-service-routing-ingress -o yaml | grep -A 5 "my-service"

# Test regex pattern matches
echo "/api/cost-control/agents" | grep -E "^/api/cost-control(/|$)"  # Should match

# Check service exists
kubectl get svc -n aep cost-control
```

### Service Returns 502 Bad Gateway

**Cause**: Service pod not running or not listening on port

**Fix**:
```bash
# Check pod status
kubectl get pods -n aep -l app=cost-control -o wide

# Check port listening
kubectl exec <pod> -n aep -- netstat -tlnp | grep 8302

# Check service DNS
kubectl exec <pod> -n aep -- nslookup cost-control.aep.svc.cluster.local
```

### Slow Response (Gateway → Service)

**Cause**: Service overloaded or network latency

**Fix**:
```bash
# Check pod resources
kubectl top pods -n aep -l app=cost-control

# Increase replicas
kubectl scale deployment cost-control -n aep --replicas=5

# Check network policy restrictions
kubectl get networkpolicy -n aep
```

### TLS Certificate Expired

**Cause**: cert-manager didn't renew certificate

**Fix**:
```bash
# Check certificate status
kubectl get certificate -n aep aep-api-rt19-tls -o yaml

# Force renewal
kubectl delete secret aep-api-rt19-tls -n aep
kubectl apply -f ingress.yaml  # Triggers cert-manager to issue new cert

# Verify new cert
openssl s_client -connect aep-api.rt19.runtimeai.io:443 | grep "Not After"
```

---

## Performance Tuning

### Timeout Configuration

In ingress annotations:
```yaml
nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"  # Connect timeout
nginx.ingress.kubernetes.io/proxy-send-timeout: "30"     # Send timeout
nginx.ingress.kubernetes.io/proxy-read-timeout: "30"     # Read timeout
```

Increase for slow services:
```bash
kubectl patch ingress aep-service-routing-ingress -n aep -p \
  '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-read-timeout":"60"}}}'
```

### Body Size Limit

Currently set to 100MB (for large uploads):
```yaml
nginx.ingress.kubernetes.io/proxy-body-size: "100m"
```

Adjust if needed:
```bash
kubectl patch ingress aep-service-routing-ingress -n aep -p \
  '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-body-size":"500m"}}}'
```

### Rate Limiting

Add per-IP rate limiting:
```yaml
nginx.ingress.kubernetes.io/limit-rps: "1000"  # 1000 requests per second per IP
```

---

## Security Considerations

1. **JWT Enforcement**: All services have `ENFORCE_JWT=true` env var
2. **RLS**: Multi-tenant row-level security enforced on all tables
3. **TLS Only**: HTTP redirects to HTTPS
4. **Network Policy**: Inter-service communication restricted (see security.md)
5. **Rate Limiting**: Per-tenant rate limits enforced (1000 req/min)

---

## Deployment

### Apply Ingress Configuration

```bash
kubectl apply -f deployment/scripts/rt19/k8s/27-aep-gateway-routing-ingress.yaml
```

### Verify Deployment

```bash
# Wait for ingress to get external IP
kubectl get ingress -n aep aep-service-routing-ingress -w

# Once EXTERNAL-IP is populated, test
curl https://aep-api.rt19.runtimeai.io/api/cost-control/health \
  -H "Authorization: Bearer $TOKEN"
```

---

**Last Updated**: May 6, 2026  
**Owner**: Platform Engineering  
**Next Review**: June 6, 2026

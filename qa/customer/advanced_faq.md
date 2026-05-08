# Advanced FAQ — Cross-Product Questions

**Last Updated**: 2026-03-17

---

## Architecture & Deployment

**Q: What's the minimum cluster size for a production deployment?**
A: rt19 runs on 2× Standard_B2pls_v2 (ARM64, 2 vCPU, 4 GB each). This is the absolute minimum — fine for 1 customer with <100 agents. For multi-customer production: 3-4 nodes with B4pls_v2 (4 vCPU, 8 GB). For enterprise: 5+ nodes with Standard_D4s_v5 (4 vCPU, 16 GB).

**Q: Can I run RuntimeAI on-premise instead of Azure?**
A: Yes. The K8s manifests work on any Kubernetes cluster (EKS, GKE, bare-metal). You need: K8s 1.28+, PostgreSQL 16, Redis 7, NGINX Ingress Controller, cert-manager (for TLS). No Azure-specific dependencies in the application layer.

**Q: How do I handle high availability?**
A: 1) Run 2+ replicas for control-plane, dashboard, auth-svc 2) Use managed PostgreSQL with streaming replication 3) Use Redis Sentinel or Redis Cluster 4) Multi-zone node pool in AKS 5) Health-check based pod rescheduling (already configured).

**Q: Can I run multiple tenants on a single pod?**
A: Yes. The platform is multi-tenant by design. Every table is keyed by `tenant_id` with RLS. A single rt19 pod can serve hundreds of tenants. Separate pods are for isolation/compliance, not scalability.

**Q: How do I set up disaster recovery?**
A: 1) PostgreSQL: pg_dump to Azure Blob Storage (daily CronJob) 2) Redis: no persistence needed (cache only) 3) K8s manifests: version-controlled in git 4) Container images: stored in ACR (replicate to second region for DR) 5) DNS failover: Azure Traffic Manager across pods.

---

## Security

**Q: How are secrets managed in production?**
A: Secrets are stored as K8s Secrets (base64-encoded). For production: integrate with Azure Key Vault using the CSI driver (`SecretProviderClass`). This is NOT configured on rt19 yet — see [gaps_issues.md](gaps_issues.md).

**Q: How does zero-trust work across services?**
A: 1) Every API call requires authentication (session cookie or API key) 2) Every request is scoped to a tenant 3) Network policies restrict pod-to-pod communication (via Calico) 4) TLS everywhere (cert-manager). The data plane adds mTLS between agents and services.

**Q: How do I rotate the admin secret?**
A: 1) Generate new secret 2) Update K8s secret: `kubectl edit secret rt19-app-secrets -n rt19` 3) Restart control-plane: `kubectl rollout restart deployment/control-plane -n rt19` 4) Update any scripts/tools using the old secret.

**Q: Can I use my own TLS certificates instead of Let's Encrypt?**
A: Yes. Replace the `ClusterIssuer` with a `Certificate` resource that references your CA. Or use cert-manager with your CA's ACME endpoint.

**Q: How do I implement IP whitelisting?**
A: Configure NGINX Ingress annotations: `nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,203.0.113.0/24"`. Or use Azure NSG rules on the AKS subnet.

---

## Data & Privacy

**Q: Where is customer data stored?**
A: All data is in PostgreSQL within the AKS cluster (self-hosted on rt19). Documents (eSign) are in Azure Blob Storage. No data leaves the Azure region unless explicitly configured (SIEM export, email notifications).

**Q: How do I handle GDPR data deletion requests?**
A: 1) Identify all data for the subject (agent, user, or external person) 2) Use the admin API to delete: `DELETE /api/admin/data-subject/<subject_id>` 3) Audit trail entries are retained (legal requirement) but PII is anonymized.

**Q: Can I encrypt the database at rest?**
A: Azure Managed Disks (backing the PostgreSQL PVC) are encrypted by default with platform-managed keys. For customer-managed keys (CMK), configure Azure Disk Encryption Set.

**Q: How does data isolation work between tenants?**
A: Row-Level Security (RLS) in PostgreSQL. Every query is automatically filtered by `tenant_id`. Even if there's a SQL injection, the RLS policy prevents cross-tenant data access.

---

## Integration

**Q: Can I integrate RuntimeAI with my existing SIEM (Splunk, Sentinel)?**
A: Yes. The audit trail can be exported to SIEM via: 1) API polling (`GET /api/audit/events`) 2) Webhook push to your SIEM's HTTP Event Collector 3) Syslog forwarding (requires data plane). Native Sentinel integration is available for Azure deployments.

**Q: How do I integrate with my IdP (Okta, Azure AD)?**
A: Two paths: 1) Auth-service OIDC integration (for user login) — configure `AUTH_OIDC_*` env vars 2) MCP Gateway Okta integration (for agent identity sync) — install `mcp-server-okta`.

**Q: Can I use RuntimeAI with non-OpenAI/Anthropic models?**
A: Yes. The platform is model-agnostic. Register any AI agent regardless of provider. FinOps supports custom pricing for any provider. The MCP gateway is protocol-agnostic.

**Q: How do I integrate with my CI/CD pipeline?**
A: Use the CLI or SDK in your pipeline: 1) On deploy: register/update agent 2) On test: run compliance check 3) On merge: verify no new shadow AI 4) On release: rotate credentials.

**Q: Can RuntimeAI work with my service mesh (Istio, Linkerd)?**
A: Yes. Deploy services as normal K8s deployments. Service mesh sidecar injection works alongside RuntimeAI services. For the data plane Flow Enforcer, consult the architecture guide for sidecar-vs-gateway decision.

---

## Operations

**Q: How do I upgrade RuntimeAI?**
A: 1) Pull new images from ACR 2) Apply K8s manifest changes (if any) 3) Rolling restart: `kubectl rollout restart deployment -n rt19` 4) Run health checks 5) Run QA suite. Database migrations run automatically on service startup.

**Q: What's the backup strategy?**
A: 1) PostgreSQL: pg_dump daily to Azure Blob Storage 2) K8s state: etcd backup (AKS handles this) 3) Container images: stored in ACR (retained indefinitely) 4) Secrets: document in secure vault.

**Q: How do I troubleshoot a failing service?**
A: 1) `kubectl get pods -n rt19` — check pod status 2) `kubectl describe pod <pod> -n rt19` — check events 3) `kubectl logs <pod> -n rt19 --tail=100` — check logs 4) `kubectl exec -it <pod> -n rt19 -- sh` — access pod shell 5) Check resource limits: `kubectl top pods -n rt19`.

**Q: How do I handle database migrations?**
A: Migrations run automatically on service startup (sequential SQL files in `db/migrations/`). For manual migration: `kubectl exec -it postgres-0 -n rt19 -- psql -U authzion -d authzion -f /path/to/migration.sql`.

**Q: What monitoring should I set up?**
A: 1) Apply `05-monitoring.yaml` for Prometheus + Grafana 2) Configure alerts for: pod restarts, high memory, database connections, 5xx error rates 3) Use the health-check script as a heartbeat: `scripts/health_check_rt19.sh`.

---

## Scaling & Performance

**Q: How many agents can the platform handle?**
A: On rt19 (2 nodes, 4 GB each): ~500 agents. On a proper production cluster (4 nodes, 16 GB each): ~10,000 agents. The bottleneck is typically PostgreSQL connections and Redis memory.

**Q: How do I scale individual services?**
A: `kubectl scale deployment/<service> -n rt19 --replicas=<N>`. Control-plane and dashboard benefit most from horizontal scaling. PostgreSQL scales vertically (bigger PVC, more memory).

**Q: What are the latency targets?**
A: API responses: <200ms (p95). DLP scanning: <5ms inline, <50ms async. Policy evaluation: <10ms (OPA). Audit write: <20ms. MCP tool invocation: depends on backend.

**Q: Can I use a CDN for the dashboard?**
A: Yes. Place Azure CDN or Cloudflare in front of the dashboard domain. The dashboard is a static React SPA — CDN-friendly.

---

## Product-Specific Cross-Cutting Questions

**Q: If I enable all 12 products, how much overhead does that add?**
A: Each product runs as a separate microservice. You only deploy what you need. Full deployment adds ~8 pods. Memory overhead: ~4 GB total (all services). CPU: minimal (event-driven architecture).

**Q: Can I use Discovery findings to auto-populate the Agent Registry?**
A: Yes. Discovery → Shadow AI Inbox → "Register" action creates the agent in the registry with pre-filled metadata from the scan.

**Q: How do FinOps budgets interact with the Kill Switch?**
A: Configure a budget with `hard_limit: true` and `hard_limit_action: "kill_switch"`. When the budget is exceeded, the agent's kill switch is automatically activated.

**Q: Can compliance evidence reference MCP tool invocations?**
A: Yes. MCP audit events are part of the unified audit trail. Evidence auto-generation can pull MCP invocation logs as proof of access control enforcement.

**Q: How does the marketplace interact with the identity fabric?**
A: Installing a marketplace agent automatically creates an entry in the agent registry with the marketplace-provided SBOM, trust score, and risk classification. The agent is governed from day one.

**Q: Can I use eSign for compliance attestations?**
A: Yes. Create a template for "Quarterly Compliance Attestation" and bulk-send to all agent sponsors. Signed attestations are stored as compliance evidence.

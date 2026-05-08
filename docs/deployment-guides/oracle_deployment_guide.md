# RuntimeAI — Oracle Cloud (OCI) Deployment Guide

> **Complete step-by-step guide** to deploy the RuntimeAI platform on Oracle Cloud Infrastructure.
> From account creation to running production with CI/CD automation.
>
> **Last Updated**: March 14, 2026
>
> **Prerequisite**: Read [GCP Deployment Guide](./gcp_deployment_guide.md) first for the full service inventory and architecture overview.
>
> **Cross-Cloud Learnings**: See the [Azure Deployment Guide](./azure_deployment_guide.md#real-world-gotchas-from-rt19-deployment) for real-world deployment gotchas.
> Critical fixes that apply to OCI: health probe path is `/health` (not `/healthz`), auth-service K8s svc must be named `auth-svc`, containers listen on port 80, set `OTEL_SDK_DISABLED=true`, admin env var is `RUNTIMEAI_ADMIN_SECRET`.

---

## Table of Contents

1. [Prerequisites & Account Setup](#1-prerequisites--account-setup)
2. [Architecture Mapping (GCP → OCI)](#2-architecture-mapping-gcp--oci)
3. [Tier 1: Minimum Viable Setup (~$100/mo)](#3-tier-1-minimum-viable-setup-100mo)
4. [Tier 2: Scale-Up Production Setup](#4-tier-2-scale-up-production-setup)
5. [Container Registry & Image Management](#5-container-registry--image-management)
6. [CI/CD Pipeline (GitHub Actions → OKE)](#6-cicd-pipeline-github-actions--oke)
7. [DNS & TLS Setup](#7-dns--tls-setup)
8. [Security Hardening](#8-security-hardening)
9. [Monitoring & Observability](#9-monitoring--observability)
10. [Backup & Disaster Recovery](#10-backup--disaster-recovery)
11. [Cost Breakdown](#11-cost-breakdown)

---

## 1. Prerequisites & Account Setup

### 1.1 Create OCI Account for RuntimeAI

> **OCI has the most generous free tier** of all cloud providers — Always Free includes 2 AMD VMs, 4 Arm VMs, 200GB block storage, Autonomous DB, and more.

```bash
# Step 1: Go to https://www.oracle.com/cloud/free/
# Step 2: Sign up — Oracle gives $300 free credit for 30 days + Always Free tier
# Step 3: Home region selection is permanent — choose your closest region

# Install OCI CLI
brew install oci-cli

# Setup config
oci setup config
# Follow prompts: tenancy OCID, user OCID, region, API key

# Verify
oci --version
kubectl version --client
helm version
terraform version
```

### 1.2 Gather OCI Identifiers

```bash
# Get Tenancy OCID
oci iam tenancy get --query 'data.id' --raw-output

# Get Compartment (create one for RuntimeAI)
oci iam compartment create \
  --compartment-id <TENANCY_OCID> \
  --name "RuntimeAI" \
  --description "RuntimeAI Platform Resources"

# Note the Compartment OCID for Terraform
```

---

## 2. Architecture Mapping (GCP → OCI)

| GCP Service | OCI Equivalent | Notes |
|-------------|---------------|-------|
| GKE | OKE (Oracle Kubernetes Engine) | Managed K8s (free control plane) |
| Cloud SQL PostgreSQL | OCI PostgreSQL (or Autonomous DB) | Managed DB |
| Memorystore Redis | OCI Cache with Redis | Managed Redis |
| Artifact Registry | OCIR (OCI Container Registry) | Container images |
| Cloud DNS | OCI DNS | DNS management |
| Cloud Armor | OCI WAF | Web app firewall |
| Secret Manager | OCI Vault | Secret/key management |
| Cloud Monitoring | OCI Monitoring + Logging | Metrics/logs |
| Workload Identity | OCI Instance Principals | Pod-level IAM |

> **OCI Advantage**: Free OKE control plane, free OCIR (500MB), free monitoring, and Always Free Arm VMs make OCI potentially the cheapest option.
>
> **Self-Hosted Fallback**: If OCI PostgreSQL or Cache creation fails (as happened on Azure), self-host PostgreSQL 16 and Redis 7 inside OKE. Use `PGDATA=/var/lib/postgresql/data/pgdata` to avoid `lost+found` mount errors on cloud PVCs.

---

## 3. Tier 1: Minimum Viable Setup (~$100/mo)

### 3.1 Terraform — Bootstrap Infrastructure

Create `deployment/terraform/oracle/tier1-bootstrap/main.tf`:

```hcl
# =============================================================================
# RuntimeAI — OCI Tier 1 (Bootstrap)
# Estimated cost: ~$80-100/month (leveraging Always Free resources)
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key_path = var.private_key_path
  region       = var.region
}

# ── Variables ──────────────────────────────────────────────────────────────────

variable "tenancy_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }
variable "private_key_path" { type = string }
variable "compartment_ocid" { type = string }

variable "region" {
  type    = string
  default = "us-ashburn-1"
}

variable "db_password" {
  type      = string
  sensitive = true
}

# ── Networking (VCN) ──────────────────────────────────────────────────────────

resource "oci_core_vcn" "runtimeai" {
  compartment_id = var.compartment_ocid
  display_name   = "runtimeai-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "runtimeai"
}

resource "oci_core_subnet" "oke_nodes" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "oke-nodes-subnet"
  cidr_block     = "10.0.1.0/24"
  dns_label      = "okenodes"

  prohibit_public_ip_on_vnic = true  # Private subnet
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.oke.id]
}

resource "oci_core_subnet" "oke_lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "oke-lb-subnet"
  cidr_block     = "10.0.2.0/24"
  dns_label      = "okelb"

  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.lb.id]
}

resource "oci_core_subnet" "db" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "db-subnet"
  cidr_block     = "10.0.3.0/24"
  dns_label      = "db"

  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
}

# Internet & NAT Gateways
resource "oci_core_internet_gateway" "runtimeai" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "runtimeai-igw"
}

resource "oci_core_nat_gateway" "runtimeai" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "runtimeai-natgw"
}

resource "oci_core_service_gateway" "runtimeai" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "runtimeai-svcgw"

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

data "oci_core_services" "all" {}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.runtimeai.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "private-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_nat_gateway.runtimeai.id
  }

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.runtimeai.id
  }
}

# Security Lists
resource "oci_core_security_list" "oke" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "oke-security-list"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "10.0.0.0/16"
  }
}

resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.runtimeai.id
  display_name   = "lb-security-list"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }
}

# ── OKE Cluster (Free control plane) ──────────────────────────────────────

resource "oci_containerengine_cluster" "runtimeai" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = "v1.30.1"
  name               = "runtimeai-cluster"
  vcn_id             = oci_core_vcn.runtimeai.id

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.oke_lb.id
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.oke_lb.id]
  }
}

# Node Pool — Arm-based for cost savings
resource "oci_containerengine_node_pool" "general" {
  cluster_id         = oci_containerengine_cluster.runtimeai.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = "v1.30.1"
  name               = "general-pool"

  node_shape = "VM.Standard.A1.Flex"  # Arm-based (cheapest, or Always Free)

  node_shape_config {
    ocpus         = 2    # 2 OCPUs
    memory_in_gbs = 12   # 12 GB RAM
  }

  node_config_details {
    size = 2  # 2 nodes

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.oke_nodes.id
    }
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = data.oci_containerengine_node_pool_option.all.sources[0].image_id
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_containerengine_node_pool_option" "all" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_ocid
}

# ── OCI PostgreSQL ─────────────────────────────────────────────────────────

resource "oci_psql_db_system" "runtimeai" {
  compartment_id  = var.compartment_ocid
  display_name    = "runtimeai-db"
  db_version      = "16"
  shape           = "PostgreSQL.VM.Standard.E4.Flex.2.32GB"

  instance_count         = 1
  instance_ocpu_count    = 2
  instance_memory_size_in_gbs = 32

  credentials {
    username = "runtimeai"
    password_details {
      password_type = "PLAIN_TEXT"
      password      = var.db_password
    }
  }

  storage_details {
    system_type           = "OCI_OPTIMIZED_STORAGE"
    is_regionally_durable = false  # Tier 1: single AD
    availability_domain   = data.oci_identity_availability_domains.ads.availability_domains[0].name
  }

  network_details {
    subnet_id = oci_core_subnet.db.id
  }

  management_policy {
    backup_policy {
      days_of_the_week   = ["SUNDAY"]
      backup_start       = "03:00"
      retention_in_days  = 7
    }
  }
}

# ── OCI Cache with Redis ──────────────────────────────────────────────────
# Note: OCI Cache is newer service. If not available, use a Redis container in K8s

# ── OCIR (Container Registry — free up to 500MB) ──────────────────────────

# OCIR is automatically available — no Terraform resource needed.
# Push to: <region>.ocir.io/<tenancy-namespace>/runtimeai/<image>

# ── OCI Vault (Secrets) ───────────────────────────────────────────────────

resource "oci_kms_vault" "runtimeai" {
  compartment_id = var.compartment_ocid
  display_name   = "runtimeai-vault"
  vault_type     = "DEFAULT"
}

# ── Outputs ────────────────────────────────────────────────────────────────

output "cluster_id" { value = oci_containerengine_cluster.runtimeai.id }
output "db_endpoint" { value = oci_psql_db_system.runtimeai.network_details[0].primary_db_endpoint_private_ip }
output "ocir_registry" { value = "${var.region}.ocir.io" }
```

### 3.2 Deploy Tier 1

```bash
cd deployment/terraform/oracle/tier1-bootstrap

cat > terraform.tfvars <<EOF
tenancy_ocid     = "ocid1.tenancy.oc1..xxxxx"
user_ocid        = "ocid1.user.oc1..xxxxx"
compartment_ocid = "ocid1.compartment.oc1..xxxxx"
fingerprint      = "xx:xx:xx..."
private_key_path = "~/.oci/oci_api_key.pem"
db_password      = "$(openssl rand -base64 24)"
EOF

terraform init
terraform plan -out tfplan
terraform apply tfplan

# Configure kubectl
oci ce cluster create-kubeconfig \
  --cluster-id <CLUSTER_OCID> \
  --file ~/.kube/config \
  --region us-ashburn-1
```

---

## 4. Tier 2: Scale-Up Production Setup

| Aspect | Tier 1 | Tier 2 |
|--------|--------|--------|
| OKE Nodes | 2x A1.Flex (Arm, 2 OCPU/12GB) | 3x E4.Flex (x86, 4 OCPU/32GB) |
| PostgreSQL | 2 OCPU, Single AD | 4 OCPU, HA (multi-AD) |
| Redis | K8s container | OCI Cache (managed) |
| WAF | None | OCI WAF |
| **Cost** | **~$100/mo** | **~$500-700/mo** |

> **OCI Advantage**: Arm instances (A1.Flex) are significantly cheaper than x86. Use them for Tier 1. OCI also offers 1-year/3-year committed pricing at deep discounts.

### Key Tier 2 Additions

```hcl
# HA PostgreSQL
instance_count = 2  # Primary + standby

# OCI WAF
resource "oci_waf_web_app_firewall_policy" "runtimeai" {
  compartment_id = var.compartment_ocid
  display_name   = "runtimeai-waf-policy"

  actions {
    name = "block"
    type = "RETURN_HTTP_RESPONSE"
    code = 403
  }

  request_rate_limiting {
    rules {
      name        = "rate-limit"
      action_name = "block"
      configurations {
        period_in_seconds           = 60
        requests_limit              = 100
      }
    }
  }
}
```

---

## 5. Container Registry & Image Management

```bash
# Login to OCIR
docker login us-ashburn-1.ocir.io -u '<tenancy-namespace>/oracleidentitycloudservice/<email>' -p '<auth_token>'

# Build & push
REGISTRY="us-ashburn-1.ocir.io/<tenancy-namespace>/runtimeai"
docker tag control-plane:latest $REGISTRY/control-plane:latest
docker push $REGISTRY/control-plane:latest
```

---

## 6. CI/CD Pipeline (GitHub Actions → OKE)

```yaml
# .github/workflows/deploy-oci.yml
name: Deploy to OCI (OKE)

on:
  workflow_dispatch:  # Manual trigger only (cost containment)
  # push:            # Uncomment when ready for auto-deploy
  #   branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure OCI CLI
        uses: oracle-actions/configure-oci-cli@v1.4.0
        with:
          user: ${{ secrets.OCI_USER_OCID }}
          fingerprint: ${{ secrets.OCI_FINGERPRINT }}
          tenancy: ${{ secrets.OCI_TENANCY_OCID }}
          region: ${{ secrets.OCI_REGION }}
          api_key: ${{ secrets.OCI_API_KEY }}

      - name: Login to OCIR
        run: |
          echo "${{ secrets.OCI_AUTH_TOKEN }}" | docker login \
            ${{ secrets.OCI_REGION }}.ocir.io \
            -u "${{ secrets.OCI_TENANCY_NS }}/oracleidentitycloudservice/${{ secrets.OCI_EMAIL }}" \
            --password-stdin

      - name: Build & Push
        run: |
          REGISTRY="${{ secrets.OCI_REGION }}.ocir.io/${{ secrets.OCI_TENANCY_NS }}/runtimeai"
          TAG="${GITHUB_SHA::8}"
          for svc in control-plane dashboard auth-service mcp-gateway; do
            docker compose -f deployment/docker-compose/docker-compose.yml build $svc
            docker tag docker-compose-$svc:latest $REGISTRY/$svc:$TAG
            docker push $REGISTRY/$svc:$TAG
          done

      - name: Setup kubectl
        run: |
          oci ce cluster create-kubeconfig \
            --cluster-id ${{ secrets.OCI_CLUSTER_OCID }} \
            --region ${{ secrets.OCI_REGION }}

      - name: Deploy
        run: |
          TAG="${GITHUB_SHA::8}"
          helm upgrade --install runtimeai ./deployment/helm/runtimeai-control-plane \
            --namespace runtimeai --set image.tag=$TAG --wait
```

---

## 7. DNS & TLS Setup

```bash
# OCI DNS Zone
oci dns zone create --compartment-id $COMPARTMENT_ID \
  --name runtimeai.io --zone-type PRIMARY

# Add A records
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for sub in www app api admin; do
  oci dns record domain update --zone-name-or-id runtimeai.io \
    --domain "${sub}.runtimeai.io" --scope GLOBAL \
    --items "[{\"domain\":\"${sub}.runtimeai.io\",\"rdata\":\"${LB_IP}\",\"rtype\":\"A\",\"ttl\":300}]"
done

# TLS: cert-manager + Let's Encrypt (same as GCP guide)
```

---

## 8. Security Hardening

| Control | Tier 1 | Tier 2 |
|---------|--------|--------|
| Private nodes (no public IPs) | ✅ | ✅ |
| OCI Vault for secrets | ✅ | ✅ |
| Network Security Groups | ✅ | ✅ |
| OCI WAF | — | ✅ |
| Cloud Guard (threat detection) | — | ✅ |
| Vulnerability Scanning | — | ✅ |
| Audit service logging | ✅ | ✅ |
| Instance principals (pod IAM) | ✅ | ✅ |

### Enable Cloud Guard (Tier 2)

```bash
# Enable Cloud Guard
oci cloud-guard configuration update \
  --compartment-id $TENANCY_OCID \
  --reporting-region us-ashburn-1 \
  --status ENABLED
```

### Security Checklist (OCI)

- [ ] Compartment isolation for RuntimeAI resources
- [ ] API keys rotated regularly
- [ ] OCI Vault for all database credentials
- [ ] Network Security Groups restrict traffic
- [ ] OKE nodes in private subnets
- [ ] PostgreSQL SSL-only
- [ ] Audit logs enabled
- [ ] Cloud Guard active (Tier 2)
- [ ] OCIR image scanning enabled

### Frontend Environment Variables

Both the **Enterprise Dashboard** and **SaaS Admin App** use Vite `VITE_*` environment variables. These are baked into the JS bundle at build time.

| Variable | Dashboard | SaaS Admin | Description |
|----------|-----------|------------|-------------|
| `VITE_API_URL` | ✅ | ✅ | Control plane API base URL |
| `VITE_ADMIN_SECRET` | — | ✅ | Admin auth secret (from OCI Vault) |
| `VITE_MARKETPLACE_ADMIN_KEY` | — | ✅ | Marketplace admin key |
| `VITE_LANDING_API_KEY` | ✅ | — | Landing backend API key |
| `VITE_BILLING_API_URL` | ✅ | ✅ | Billing service URL |
| `VITE_MCP_GATEWAY_URL` | ✅ | ✅ | MCP Gateway URL |
| `VITE_ESIGN_URL` | ✅ | ✅ | eSign service URL |
| `VITE_GRAFANA_URL` | ✅ | — | Grafana dashboard (empty in prod to hide) |
| `VITE_PROMETHEUS_URL` | ✅ | — | Prometheus metrics (empty in prod to hide) |
| `VITE_JAEGER_URL` | ✅ | — | Jaeger tracing (empty in prod to hide) |

**Secret Injection at Build Time (OCI)**:
```bash
# Fetch secrets from OCI Vault before Docker build
SAAS_ADMIN_SECRET=$(oci secrets secret-bundle get \
  --secret-id $SAAS_ADMIN_SECRET_OCID \
  --query 'data."secret-bundle-content".content' \
  --output text | base64 -d)

# Inject via --build-arg
docker build \
  --build-arg VITE_ADMIN_SECRET="$SAAS_ADMIN_SECRET" \
  -t $REGISTRY/saas-admin:latest \
  ./SaaSAdminApp
```

### Row-Level Security (RLS) — Tenant Isolation

All tenant-scoped tables have RLS actively enforced via three migration phases. RLS ensures tenant isolation at the database layer — every API query runs under the `runtimeai_app` role with `set_tenant_context()` called per-request.

| Phase | Migration | Tables Covered |
|-------|-----------|---------------|
| Phase 1 | `057_row_level_security.sql` | 43 core tables |
| Phase 2 | `078_rls_post057_tables.sql` | 26 tables (mcp_*, tpm_*, discovery_*, etc.) |
| Phase 3 | `092_rls_comprehensive_repair.sql` | Comprehensive repair — fixes missing policies, ensures all 80+ tables covered |

- **Tenant pool** (`runtimeai_app` role) — RLS enforced via `BeginTenantTx()` in all 23 route handlers
- **Admin pool** (superuser) — BYPASSRLS for background workers and admin ops

> [!IMPORTANT]
> RLS is **actively enforced** as of migration 092. Set `RLS_ENABLED=true` and `RLS_APP_PASSWORD` in the control-plane deployment. All route handlers call `SET ROLE runtimeai_app` and `SELECT set_tenant_context(tenant_id)` on every request.

---

## 9. Monitoring & Observability

```bash
# OCI Monitoring is free and automatic for OCI services

# Install Prometheus + Grafana for app-level metrics
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

---

## 10. Backup & Disaster Recovery

```bash
# PostgreSQL backups are automated in Terraform config

# K8s backup with Velero (OCI Object Storage)
velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket runtimeai-backups --backup-location-config \
  s3Url=https://<namespace>.compat.objectstorage.<region>.oraclecloud.com,region=<region>
```

---

## 11. Cost Breakdown

### Tier 1 (~$80-100/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| OKE Control Plane | Free | $0 |
| OKE Nodes | 2x A1.Flex (2 OCPU, 12GB Arm) | ~$40 |
| PostgreSQL | 2 OCPU, 32GB storage | ~$35 |
| Redis | Self-managed in K8s (or OCI Cache) | ~$0-20 |
| OCIR | Free up to 500MB | $0 |
| OCI DNS | | ~$1 |
| NAT Gateway | 1 | ~$8 |
| **Total** | | **~$85-100** |

> **OCI is the cheapest option** thanks to free OKE control plane, free OCIR, and low-cost Arm instances. Always Free tier VMs can further reduce costs for dev/staging.

### Tier 2 (~$500-700/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| OKE + 3x E4.Flex | 4 OCPU, 32GB each | ~$250 |
| PostgreSQL HA | 4 OCPU, 2-node HA | ~$150 |
| OCI Cache (Redis) | Managed | ~$50 |
| OCI WAF | | ~$20 |
| Object Storage | Backups | ~$5 |
| **Total** | | **~$475-700** |

> **Cost savings**: OCI Universal Credits (prepaid) give 30-60% discounts.

---

## 12. Data Plane Services (OPER_RT19-031)

> **Added**: March 2026 — Sidecar Injector, Flow Enforcer, Data Proxy, GitHub App, IdP Connectors

### 12.1 Sidecar Injector (MutatingAdmissionWebhook)

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Deploy sidecar injector
kubectl apply -f deployment/scripts/rt19/k8s/06-sidecar-injector.yaml

# Enable injection for a namespace
kubectl label namespace runtimeai runtimeai.io/inject-sidecar=true
```

### 12.2 Flow Enforcer (Envoy + WASM)

```bash
cd flow-enforcer/templates && ./generate_config.sh -f values-default.yaml -o ../envoy/envoy.yaml
./deployment/scripts/rt19/build-push-deploy.sh flow-enforcer

# OCI: store service token in Vault
oci vault secret create-base64 --compartment-id <compartment-id> \
  --secret-content-content "$(openssl rand -base64 32 | base64)" \
  --secret-name "runtimeai-flow-enforcer-token" --vault-id <vault-ocid>
```

### 12.3 Data Proxy (DLP + PII Masking)

```bash
./deployment/scripts/rt19/build-push-deploy.sh data-proxy
kubectl apply -f services/data-proxy/k8s/sidecar-template.yaml
```

### 12.4 GitHub App (Organization Scanning)

```bash
# Store private key in OCI Vault
oci vault secret create-base64 --compartment-id <compartment-id> \
  --secret-content-content "$(base64 /path/to/github-app.pem)" \
  --secret-name "runtimeai-github-app-key" --vault-id <vault-ocid>

# Webhook URL: https://api.runtimeai.io/api/github/webhook
```

### 12.5 IdP Connectors (OAuth Discovery)

Supported: Okta, Azure AD, Google Workspace, AWS IAM, **Oracle OCI IAM**, MCP Gateway.

```bash
# OCI: use OCI IAM Identity Domains natively
oci vault secret create-base64 --compartment-id <compartment-id> \
  --secret-content-content "$(echo -n '{"tenancy_ocid":"ocid1.tenancy.oc1..xxx","user_ocid":"ocid1.user.oc1..xxx"}' | base64)" \
  --secret-name "runtimeai-oci-iam-creds" --vault-id <vault-ocid>

curl -X POST https://api.runtimeai.io/api/discovery/idp-connectors \
  -H "Content-Type: application/json" -H "Cookie: session=<session_id>" \
  -d '{
    "provider": "oci",
    "display_name": "Production OCI IAM",
    "vault_secret_path": "runtimeai/idp/oci",
    "config": {"region": "us-ashburn-1"},
    "scan_interval": "6 hours"
  }'
```

---

## SDK Installation & Configuration

> **See also**: [SDK Quickstart Guide](./sdk_quickstart.md) for full reference.

### TypeScript SDK

```bash
npm install @runtimeai/sdk
```

```typescript
import { RuntimeAI } from '@runtimeai/sdk';

const client = new RuntimeAI({
  apiUrl: 'https://api.your-deployment.runtimeai.io',
  apiKey: process.env.RUNTIMEAI_API_KEY!,
});
```

### Python SDK

```bash
pip install runtimeai
```

```python
from runtimeai import RuntimeAI
import os

client = RuntimeAI(
    "https://api.your-deployment.runtimeai.io",
    api_key=os.environ["RUNTIMEAI_API_KEY"]
)
```

### GHCR Container Images

```bash
docker pull ghcr.io/runtimeai-dev/control-plane:latest
docker pull ghcr.io/runtimeai-dev/dashboard:latest
docker pull ghcr.io/runtimeai-dev/auth-service:latest
docker pull ghcr.io/runtimeai-dev/mcp-gateway:latest
```

---

## API-Based Seeding (No Direct SQL)

> **Critical**: All seed operations use API endpoints exclusively.

### Available Seed API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/agents` | POST | Register agents |
| `/api/drift/findings` | POST | Create drift findings |
| `/api/audit/logs` | POST | Create audit log entries |
| `/api/credentials/issued` | POST | Create issued credentials |
| `/api/policies/versions` | POST | Create policy versions + content |
| `/api/mcp/invocations` | POST | Create MCP invocation logs |
| `/api/quotas` | POST | Create quota rows |
| `/api/agents/{id}` | PATCH | Update trust_score, spiffe_id |
| `/api/guardrails` | POST | Create guardrails |
| `/api/governance/sod-rules` | POST | Create SoD rules |
| `/api/discovery/import` | POST | Import scanner findings |

### OCI Vault — Retrieve Secrets for Seeding

```bash
# Retrieve API key from OCI Vault
export RUNTIMEAI_API_KEY=$(oci secrets secret-bundle get \
  --secret-id <api-key-secret-ocid> \
  --query 'data."secret-bundle-content".content' \
  --output text | base64 -d)

# Retrieve admin secret
export ADMIN_SECRET=$(oci secrets secret-bundle get \
  --secret-id <admin-secret-ocid> \
  --query 'data."secret-bundle-content".content' \
  --output text | base64 -d)
```

---

## RLS Verification

```bash
CP_POD=$(kubectl get pods -n runtimeai -l app=control-plane -o jsonpath='{.items[0].metadata.name}')
kubectl logs $CP_POD -n runtimeai | grep "RLS" | tail -5
# Expected: [RLS] ENABLED — 80 tenant_isolation policies
```

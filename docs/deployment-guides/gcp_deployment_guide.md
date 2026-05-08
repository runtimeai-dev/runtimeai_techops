# RuntimeAI — GCP Deployment Guide

> **Complete step-by-step guide** to deploy the RuntimeAI platform on Google Cloud Platform.
> From account creation to running production with CI/CD automation.
>
> **Last Updated**: March 14, 2026
>
> **Cross-Cloud Learnings**: See the [Azure Deployment Guide](./azure_deployment_guide.md#real-world-gotchas-from-rt19-deployment) for 13 real-world gotchas
> discovered during the live `runtimeai.io` deployment. Many apply to GCP too (probe paths, container ports, OTEL, etc.).

---

## Table of Contents

1. [Prerequisites & Account Setup](#1-prerequisites--account-setup)
2. [Architecture Overview](#2-architecture-overview)
3. [Tier 1: Minimum Viable Setup (~$150/mo)](#3-tier-1-minimum-viable-setup-150mo)
4. [Tier 2: Scale-Up Production Setup](#4-tier-2-scale-up-production-setup)
5. [Container Registry & Image Management](#5-container-registry--image-management)
6. [Kubernetes Deployment (Helm)](#6-kubernetes-deployment-helm)
7. [CI/CD Pipeline (GitHub Actions → GKE)](#7-cicd-pipeline-github-actions--gke)
8. [DNS & TLS Setup (runtimeai.io)](#8-dns--tls-setup-runtimeaiio)
9. [Security Hardening](#9-security-hardening)
10. [Monitoring & Observability](#10-monitoring--observability)
11. [Backup & Disaster Recovery](#11-backup--disaster-recovery)
12. [Operational Runbook](#12-operational-runbook)
13. [Cost Breakdown](#13-cost-breakdown)

---

## 1. Prerequisites & Account Setup

### 1.1 Create a GCP Account for RuntimeAI

> **Note**: Google Workspace for Business Starter does NOT include GCP. You need a separate Google Cloud account.

```bash
# Step 1: Go to https://cloud.google.com and click "Get started for free"
# Step 2: Sign in with your Google account (can be your Workspace account)
# Step 3: You get $300 free credit for 90 days — enough for initial setup
```

**After signup:**

```bash
# Install Google Cloud CLI
brew install --cask google-cloud-sdk

# Authenticate
gcloud auth login
gcloud auth application-default login

# Create the RuntimeAI project
gcloud projects create runtimeai-prod --name="RuntimeAI Production"
gcloud config set project runtimeai-prod

# Link billing account (required for any resources)
# Get your billing account ID from: https://console.cloud.google.com/billing
gcloud billing accounts list
gcloud billing projects link runtimeai-prod --billing-account=<BILLING_ACCOUNT_ID>
```

### 1.2 Enable Required APIs

```bash
gcloud services enable \
  container.googleapis.com \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  artifactregistry.googleapis.com \
  dns.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  cloudresourcemanager.googleapis.com \
  certificatemanager.googleapis.com \
  binaryauthorization.googleapis.com
```

### 1.3 Install Tools

```bash
# Kubernetes CLI
brew install kubectl

# Helm
brew install helm

# Terraform
brew install terraform

# Verify
gcloud version
kubectl version --client
helm version
terraform version
```

---

## 2. Architecture Overview

### Service Inventory (50 Services Total)

**Control Plane (runtimeai-enterprise repo — 34 services):**

| Service | Port | Type | Critical? |
|---------|------|------|-----------|
| control-plane | 8080 (→4000 via nginx) | Go | ✅ Core |
| dashboard | 4000 | React/Vite | ✅ Core |
| auth-service | 8199 | Go | ✅ Core |
| postgres | 5432 | PostgreSQL 16 | ✅ Core |
| redis | 6379 | Redis 7 | ✅ Core |
| mcp-gateway | 8091 | Go | ✅ Core |
| discovery | 8090 | Python | High |
| flow-enforcer | 8092 | Go/Wasm | High |
| drift-engine | 8083, 50051 | Go/gRPC | High |
| drift-worker | — | Go | High |
| policy-manager | 8093 | Python | High |
| waf | 8101 | OpenResty | High |
| data-proxy | 8100 | Go | High |
| cost-ledger | 8099 | Go | Medium |
| identity-dns | 8053, 1053 | Go | Medium |
| billing-service | 5057 | Go | Medium |
| sequence-modeler | — | Go | Medium |
| vendor-wrapper | — | Go | Low |
| verifier | — | Go | Low |
| bot-ca | — | Go | Low |
| vault-broker | 8097 | Python | Low |
| bundle-cache | 8094 | Python | Low |
| network-analyzer | — | Go | Low |
| internal-api | — | Go | Low |
| mcp-server-postgresql | 8083 | Go | Low |
| opa | 8181, 8282 | OPA | Medium |
| vault | 8200 | HashiCorp Vault | Medium |
| dex | 5556, 5557 | Dex IdP | Low |
| prometheus | 9090 | Prometheus | Ops |
| grafana | 3000 | Grafana | Ops |
| jaeger | 16686, 14268 | Jaeger | Ops |
| drift-migrate | — | Migration runner | Init |

**RuntimeAI Platform (runtimeai repo — 16 services):**

| Service | Port | Type | Critical? |
|---------|------|------|-----------|
| runtimeai-landing | 3001 | React/Vite | ✅ Public |
| ~~landing-frontend~~ | ~~80~~ | ~~React/Vite~~ | ❌ DEPRECATED — use runtimeai-landing |
| landing-backend | 8082 | Go | ✅ Public |
| saas-admin-app | 7080 | React/Vite | ✅ Admin |
| ai-finops-service | 5055 | Go | High |
| aaic-service | 5056 | Go | High |
| esign-service | — | Go | High |
| esign-landing | — | React/Vite | High |
| auditor-dashboard | — | React/Vite | Medium |
| marketplace-service | — | Go | Medium |
| auth-service (rt) | — | Go | Medium |
| billing-service (rt) | — | Go | Medium |
| mcp-gateway (rt) | — | Go | Medium |
| mcp-server-okta | 8095 | Go | Low |
| postgres (rt) | 5433 | PostgreSQL 15 | ✅ Core |
| mailpit | 8025 | Email dev | Dev only |

### Deployment Architecture

```
                    ┌─────────────────────────┐
                    │   Cloud DNS (runtimeai.io)│
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   Cloud Load Balancer    │
                    │   + Managed TLS Certs    │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                   │
     ┌────────▼──────┐ ┌────────▼──────┐  ┌─────────▼─────┐
     │ www.runtimeai  │ │app.runtimeai  │  │api.runtimeai  │
     │   .io          │ │   .io         │  │   .io         │
     │ (Landing)      │ │ (Dashboard)   │  │ (Control Plane│
     └────────────────┘ └───────────────┘  │  + APIs)      │
                                           └───────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │      GKE Cluster         │
                    │  ┌─────────────────────┐ │
                    │  │ Namespace: runtimeai │ │
                    │  │ (All 50 services)    │ │
                    │  └─────────────────────┘ │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                                      │
     ┌────────▼──────┐                    ┌──────────▼────┐
     │  Cloud SQL     │                    │  Memorystore   │
     │  PostgreSQL 16 │                    │  Redis 7       │
     │  (Managed)     │                    │  (Managed)     │
     └────────────────┘                    └───────────────┘
```

**Subdomain Plan:**

| Subdomain | Routes To | Purpose |
|-----------|-----------|---------|
| `www.runtimeai.io` | runtimeai-landing | Public marketing site |
| `app.runtimeai.io` | dashboard (port 4000) | Enterprise dashboard |
| `api.runtimeai.io` | control-plane (port 8080) | API gateway |
| `admin.runtimeai.io` | saas-admin-app (port 7080) | SaaS admin console |
| `sign.runtimeai.io` | esign-landing | eSign portal |
| `audit.runtimeai.io` | auditor-dashboard | Auditor portal |

---

## 3. Tier 1: Minimum Viable Setup (~$150/mo)

> **For**: Solo founder, demo environments, early customers.
> Uses free-tier resources where possible, spot/preemptible VMs, and smallest managed DB instances.

### 3.1 Terraform — Minimum Infrastructure

Create `deployment/terraform/gcp/tier1-bootstrap/main.tf`:

```hcl
# =============================================================================
# RuntimeAI — GCP Tier 1 (Bootstrap)
# Estimated cost: ~$100-150/month after free credits
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Variables ──────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "db_password" {
  description = "PostgreSQL root password"
  type        = string
  sensitive   = true
}

# ── Networking ─────────────────────────────────────────────────────────────────

resource "google_compute_network" "runtimeai" {
  name                    = "runtimeai-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "runtimeai" {
  name          = "runtimeai-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.runtimeai.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

# ── GKE Cluster (Autopilot — pay-per-pod, no idle node costs) ──────────────

resource "google_container_cluster" "runtimeai" {
  name     = "runtimeai-cluster"
  location = var.region

  # Autopilot = no node management, pay only for pod resources
  enable_autopilot = true

  network    = google_compute_network.runtimeai.id
  subnetwork = google_compute_subnetwork.runtimeai.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Security: Private cluster (nodes have no public IPs)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Allow kubectl from your machine
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Security: Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "STABLE"
  }

  deletion_protection = false  # Set to true in production
}

# ── Cloud SQL PostgreSQL (Smallest instance) ───────────────────────────────

resource "google_sql_database_instance" "runtimeai" {
  name             = "runtimeai-db"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier              = "db-f1-micro"  # Smallest: shared vCPU, 0.6 GB RAM (~$8/mo)
    availability_type = "ZONAL"       # Single zone (cheapest)
    disk_size         = 10            # 10 GB SSD

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.runtimeai.id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
    }

    maintenance_window {
      day  = 7  # Sunday
      hour = 4
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }
  }

  deletion_protection = false  # Set to true in production
}

resource "google_sql_database" "authzion" {
  name     = "authzion"
  instance = google_sql_database_instance.runtimeai.name
}

resource "google_sql_user" "runtimeai" {
  name     = "runtimeai"
  instance = google_sql_database_instance.runtimeai.name
  password = var.db_password
}

# ── Memorystore Redis (Smallest) ───────────────────────────────────────────

resource "google_redis_instance" "runtimeai" {
  name           = "runtimeai-redis"
  tier           = "BASIC"           # No replication (cheapest)
  memory_size_gb = 1                 # 1 GB (~$35/mo)
  region         = var.region

  authorized_network = google_compute_network.runtimeai.id

  redis_version = "REDIS_7_0"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }
}

# ── Artifact Registry (Container images) ───────────────────────────────────

resource "google_artifact_registry_repository" "runtimeai" {
  location      = var.region
  repository_id = "runtimeai"
  format        = "DOCKER"
  description   = "RuntimeAI container images"
}

# ── Static IP for Ingress ──────────────────────────────────────────────────

resource "google_compute_global_address" "runtimeai_ingress" {
  name = "runtimeai-ingress-ip"
}

# ── Secret Manager ─────────────────────────────────────────────────────────

resource "google_secret_manager_secret" "db_url" {
  secret_id = "runtimeai-database-url"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_url" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = "postgresql://runtimeai:${var.db_password}@${google_sql_database_instance.runtimeai.private_ip_address}:5432/authzion?sslmode=require"
}

resource "google_secret_manager_secret" "redis_url" {
  secret_id = "runtimeai-redis-url"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_url" {
  secret      = google_secret_manager_secret.redis_url.id
  secret_data = "redis://${google_redis_instance.runtimeai.host}:${google_redis_instance.runtimeai.port}/0"
}

# ── Private Service Access (for Cloud SQL private IP) ──────────────────────

resource "google_compute_global_address" "private_ip_range" {
  name          = "runtimeai-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.runtimeai.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.runtimeai.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ── Outputs ────────────────────────────────────────────────────────────────

output "cluster_name" {
  value = google_container_cluster.runtimeai.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.runtimeai.endpoint
  sensitive = true
}

output "db_private_ip" {
  value = google_sql_database_instance.runtimeai.private_ip_address
}

output "redis_host" {
  value = google_redis_instance.runtimeai.host
}

output "registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/runtimeai"
}

output "ingress_ip" {
  value = google_compute_global_address.runtimeai_ingress.address
}
```

### 3.2 Deploy Tier 1 Infrastructure

```bash
cd deployment/terraform/gcp/tier1-bootstrap

# Create terraform.tfvars (DO NOT commit this file)
cat > terraform.tfvars <<EOF
project_id  = "runtimeai-prod"
region      = "us-central1"
db_password = "$(openssl rand -base64 24)"
EOF

# Initialize & apply
terraform init
terraform plan -out tfplan
terraform apply tfplan

# Connect kubectl to the cluster
gcloud container clusters get-credentials runtimeai-cluster \
  --region us-central1 --project runtimeai-prod
```

### 3.3 Tier 1 — What You Get

| Resource | Spec | Monthly Cost |
|----------|------|-------------|
| GKE Autopilot | Pay-per-pod (no idle nodes) | ~$75 for 50 pods |
| Cloud SQL PostgreSQL | db-f1-micro, 10GB SSD | ~$8 |
| Memorystore Redis | Basic, 1GB | ~$35 |
| Artifact Registry | Storage only | ~$1 |
| Static IP | 1 global | ~$3 |
| Cloud DNS | 1 zone | ~$0.50 |
| **Total** | | **~$120-150/mo** |

> **Tip**: GCP gives $300 free credit for 90 days. Your first 3 months are effectively free.

### 3.4 Tier 1 — Service Grouping Strategy

Not all 50 services are needed for a minimal deployment. Start with the **core services** and enable others as needed:

**Must-Have (Day 1):**
- control-plane, dashboard, auth-service
- postgres (managed Cloud SQL), redis (managed Memorystore)
- runtimeai-landing, landing-backend
- saas-admin-app

**Enable Week 2+:**
- mcp-gateway, discovery, policy-manager
- flow-enforcer, drift-engine, drift-worker
- ai-finops-service, aaic-service

**Enable When Needed:**
- esign-service, esign-landing, auditor-dashboard
- marketplace-service, billing-service
- waf, data-proxy, vault, vault-broker
- All observability (prometheus, grafana, jaeger)

---

## 4. Tier 2: Scale-Up Production Setup

> **For**: Multiple enterprise customers, SLA requirements, SOC 2 compliance.

### 4.1 Key Differences from Tier 1

| Aspect | Tier 1 (Bootstrap) | Tier 2 (Scale) |
|--------|-------------------|----------------|
| GKE | Autopilot (pay-per-pod) | Standard with 3-node pool |
| Cloud SQL | db-f1-micro (shared) | db-custom-2-7680 (dedicated) |
| Redis | Basic 1GB | Standard 5GB (HA) |
| Availability | Single zone | Regional (multi-zone) |
| Backups | Daily automated | Continuous PITR + cross-region |
| Nodes | Autopilot managed | 3x e2-standard-4 (16 vCPU, 48GB total) |
| Ingress | Basic HTTP LB | Cloud Armor + WAF |
| Monitoring | Basic Cloud Monitoring | Full Prometheus + Grafana + PagerDuty |
| **Cost** | **~$150/mo** | **~$600-900/mo** |

### 4.2 Terraform — Scale-Up Additions

Create `deployment/terraform/gcp/tier2-production/main.tf`:

```hcl
# =============================================================================
# RuntimeAI — GCP Tier 2 (Production Scale)
# Estimated cost: ~$600-900/month
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state for production
  backend "gcs" {
    bucket = "runtimeai-terraform-state"
    prefix = "prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "db_password" {
  type      = string
  sensitive = true
}

# ── Networking ─────────────────────────────────────────────────────────────────

resource "google_compute_network" "runtimeai" {
  name                    = "runtimeai-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "runtimeai" {
  name          = "runtimeai-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.runtimeai.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }

  # Enable VPC Flow Logs for security
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ── GKE Standard Cluster (Multi-zone) ──────────────────────────────────────

resource "google_container_cluster" "runtimeai" {
  name     = "runtimeai-cluster"
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.runtimeai.id
  subnetwork = google_compute_subnetwork.runtimeai.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable Network Policy enforcement
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Enable Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Enable Dataplane V2 for improved networking
  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = "STABLE"
  }

  # Enable audit logging
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  deletion_protection = true
}

# ── Node Pool: General workloads ───────────────────────────────────────────

resource "google_container_node_pool" "general" {
  name     = "general-pool"
  location = var.region
  cluster  = google_container_cluster.runtimeai.name

  initial_node_count = 1

  autoscaling {
    min_node_count = 2
    max_node_count = 6
  }

  node_config {
    machine_type = "e2-standard-4"  # 4 vCPU, 16 GB RAM
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    # Security: Use least-privilege service account
    service_account = google_service_account.gke_node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Security: Enable Shielded nodes
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      env  = "production"
      tier = "general"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ── Node Pool: Spot instances for non-critical workloads ───────────────────

resource "google_container_node_pool" "spot" {
  name     = "spot-pool"
  location = var.region
  cluster  = google_container_cluster.runtimeai.name

  initial_node_count = 0

  autoscaling {
    min_node_count = 0
    max_node_count = 4
  }

  node_config {
    machine_type = "e2-standard-2"  # 2 vCPU, 8 GB RAM
    spot         = true             # 60-91% cheaper

    service_account = google_service_account.gke_node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      env  = "production"
      tier = "spot"
    }

    taint {
      key    = "cloud.google.com/gke-spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
}

# ── GKE Node Service Account (Least Privilege) ────────────────────────────

resource "google_service_account" "gke_node" {
  account_id   = "runtimeai-gke-node"
  display_name = "RuntimeAI GKE Node SA"
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

# ── Cloud SQL PostgreSQL (Production) ──────────────────────────────────────

resource "google_sql_database_instance" "runtimeai" {
  name             = "runtimeai-db-prod"
  database_version = "POSTGRES_16"
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc]

  settings {
    tier              = "db-custom-2-7680"  # 2 vCPU, 7.5 GB RAM (~$95/mo)
    availability_type = "REGIONAL"          # Multi-zone HA
    disk_size         = 50
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.runtimeai.id
      require_ssl     = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 30
      }
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }

    database_flags {
      name  = "max_connections"
      value = "200"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }

  deletion_protection = true
}

resource "google_sql_database" "authzion" {
  name     = "authzion"
  instance = google_sql_database_instance.runtimeai.name
}

resource "google_sql_user" "runtimeai" {
  name     = "runtimeai"
  instance = google_sql_database_instance.runtimeai.name
  password = var.db_password
}

# ── Memorystore Redis (HA) ─────────────────────────────────────────────────

resource "google_redis_instance" "runtimeai" {
  name               = "runtimeai-redis"
  tier               = "STANDARD_HA"     # HA with automatic failover
  memory_size_gb     = 5
  region             = var.region
  authorized_network = google_compute_network.runtimeai.id
  redis_version      = "REDIS_7_0"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours = 4
      }
    }
  }
}

# ── Cloud Armor (WAF/DDoS) ────────────────────────────────────────────────

resource "google_compute_security_policy" "runtimeai" {
  name = "runtimeai-security-policy"

  # Default: allow
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  # Block known bad IPs
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "XSS protection"
  }

  rule {
    action   = "deny(403)"
    priority = 1001
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "SQL injection protection"
  }

  # Rate limiting
  rule {
    action   = "rate_based_ban"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 300
    }
    description = "Rate limiting: 100 req/min per IP"
  }
}

# ── Artifact Registry ──────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "runtimeai" {
  location      = var.region
  repository_id = "runtimeai"
  format        = "DOCKER"
  description   = "RuntimeAI container images"
}

# ── Static IP ──────────────────────────────────────────────────────────────

resource "google_compute_global_address" "runtimeai_ingress" {
  name = "runtimeai-ingress-ip"
}

# ── Secret Manager ─────────────────────────────────────────────────────────

resource "google_secret_manager_secret" "db_url" {
  secret_id = "runtimeai-database-url"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "db_url" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = "postgresql://runtimeai:${var.db_password}@${google_sql_database_instance.runtimeai.private_ip_address}:5432/authzion?sslmode=require"
}

resource "google_secret_manager_secret" "admin_secret" {
  secret_id = "runtimeai-admin-secret"
  replication { auto {} }
}

# ── Private Service Access ─────────────────────────────────────────────────

resource "google_compute_global_address" "private_ip_range" {
  name          = "runtimeai-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.runtimeai.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.runtimeai.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ── Outputs ────────────────────────────────────────────────────────────────

output "cluster_name" { value = google_container_cluster.runtimeai.name }
output "db_private_ip" { value = google_sql_database_instance.runtimeai.private_ip_address }
output "redis_host" { value = google_redis_instance.runtimeai.host }
output "registry_url" { value = "${var.region}-docker.pkg.dev/${var.project_id}/runtimeai" }
output "ingress_ip" { value = google_compute_global_address.runtimeai_ingress.address }
```

---

## 5. Container Registry & Image Management

### 5.1 Configure Docker for Artifact Registry

```bash
# Authenticate Docker with GCP
gcloud auth configure-docker us-central1-docker.pkg.dev

# Set registry URL
export REGISTRY="us-central1-docker.pkg.dev/runtimeai-prod/runtimeai"
```

### 5.2 Build & Push All Images

```bash
#!/bin/bash
# scripts/push_all_images.sh
set -euo pipefail

REGISTRY="${1:-us-central1-docker.pkg.dev/runtimeai-prod/runtimeai}"
TAG="${2:-latest}"
ENTERPRISE_DIR="${ENTERPRISE_DIR:-.}"
RUNTIMEAI_DIR="${RUNTIMEAI_DIR:-../runtimeai}"

echo "══════════════════════════════════════════════════"
echo "  Pushing RuntimeAI images to $REGISTRY"
echo "══════════════════════════════════════════════════"

# Enterprise services (build from docker-compose)
ENTERPRISE_SERVICES=(
  "control-plane" "dashboard" "auth-service" "mcp-gateway"
  "discovery" "flow-enforcer" "drift-engine" "drift-worker"
  "policy-manager" "waf" "data-proxy" "cost-ledger"
  "identity-dns" "billing-service"
  "sequence-modeler" "vendor-wrapper" "verifier" "bot-ca"
  "vault-broker" "bundle-cache" "network-analyzer" "internal-api"
  "mcp-server-postgresql"
)

for svc in "${ENTERPRISE_SERVICES[@]}"; do
  echo "Building & pushing: $svc"
  cd "$ENTERPRISE_DIR/deployment/docker-compose"
  docker compose build "$svc"
  docker tag "docker-compose-$svc:latest" "$REGISTRY/$svc:$TAG"
  docker push "$REGISTRY/$svc:$TAG"
done

# RuntimeAI services
RUNTIMEAI_SERVICES=(
  "frontend" "runtimeai-landing" "backend" "saas-admin-app"
  "ai-finops-service" "aaic-service" "esign-service"
  "esign-landing" "auditor-dashboard" "marketplace-service"
  "auth-service" "billing-service" "mcp-gateway" "mcp-server-okta"
)

for svc in "${RUNTIMEAI_SERVICES[@]}"; do
  echo "Building & pushing: $svc"
  cd "$RUNTIMEAI_DIR"
  docker compose build "$svc" 2>/dev/null || echo "  ⚠ $svc not in compose, skipping"
  docker tag "runtimeai-$svc:latest" "$REGISTRY/rt-$svc:$TAG" 2>/dev/null || true
  docker push "$REGISTRY/rt-$svc:$TAG" 2>/dev/null || true
done

echo "✅ All images pushed to $REGISTRY"
```

---

## 6. Kubernetes Deployment (Helm)

### 6.1 Create RuntimeAI Umbrella Helm Chart

The Helm chart deploys all services into a single `runtimeai` namespace.

```bash
# Install to cluster
helm install runtimeai ./deployment/helm/runtimeai-control-plane \
  --namespace runtimeai --create-namespace \
  --set image.repository=$REGISTRY/control-plane \
  --set dashboard.image.repository=$REGISTRY/dashboard \
  --set controlPlane.env.DATABASE_URL="$(gcloud secrets versions access latest --secret=runtimeai-database-url)" \
  --set controlPlane.env.REDIS_URL="$(gcloud secrets versions access latest --secret=runtimeai-redis-url)" \
  --set controlPlane.env.ADMIN_SECRET="$(openssl rand -hex 32)" \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=app.runtimeai.io
```

### 6.2 Install Ingress Controller

```bash
# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.loadBalancerIP=$(terraform output -raw ingress_ip)

# Install cert-manager for Let's Encrypt TLS
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true
```

### 6.3 Create Let's Encrypt ClusterIssuer

```yaml
# k8s/cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@runtimeai.io
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
```

```bash
kubectl apply -f k8s/cluster-issuer.yaml
```

---

## 7. CI/CD Pipeline (GitHub Actions → GKE)

### 7.1 GitHub Actions Workflow

Create `.github/workflows/deploy-gcp.yml` in the `runtimeai-enterprise` repo:

```yaml
# .github/workflows/deploy-gcp.yml
name: Deploy to GCP (GKE)

on:
  workflow_dispatch:  # Manual trigger only (cost containment)
  # push:            # Uncomment when ready for auto-deploy
  #   branches: [main]

env:
  PROJECT_ID: runtimeai-prod
  REGION: us-central1
  CLUSTER: runtimeai-cluster
  REGISTRY: us-central1-docker.pkg.dev/runtimeai-prod/runtimeai

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write  # For Workload Identity Federation

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v2
        with:
          project_id: ${{ env.PROJECT_ID }}

      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker ${{ env.REGION }}-docker.pkg.dev

      - name: Build & Push Images
        run: |
          TAG="${GITHUB_SHA::8}"
          SERVICES="control-plane dashboard auth-service mcp-gateway discovery policy-manager flow-enforcer drift-engine drift-worker waf data-proxy cost-ledger billing-service sequence-modeler vendor-wrapper verifier bot-ca vault-broker bundle-cache network-analyzer"
          for svc in $SERVICES; do
            echo "Building $svc..."
            cd deployment/docker-compose
            docker compose build $svc
            docker tag docker-compose-$svc:latest $REGISTRY/$svc:$TAG
            docker tag docker-compose-$svc:latest $REGISTRY/$svc:latest
            docker push $REGISTRY/$svc:$TAG
            docker push $REGISTRY/$svc:latest
            cd ../..
          done

      - name: Get GKE Credentials
        uses: google-github-actions/get-gke-credentials@v2
        with:
          cluster_name: ${{ env.CLUSTER }}
          location: ${{ env.REGION }}

      - name: Deploy via Helm
        run: |
          TAG="${GITHUB_SHA::8}"
          helm upgrade --install runtimeai ./deployment/helm/runtimeai-control-plane \
            --namespace runtimeai --create-namespace \
            --set image.tag=$TAG \
            --set dashboard.image.tag=$TAG \
            --wait --timeout 10m

      - name: Verify Deployment
        run: |
          kubectl rollout status deployment/runtimeai-control-plane -n runtimeai --timeout=300s
          kubectl rollout status deployment/runtimeai-dashboard -n runtimeai --timeout=300s
          echo "✅ Deployment successful"
```

### 7.2 Setup Workload Identity Federation (Keyless Auth)

> **Security**: No JSON key files — uses OIDC federation between GitHub and GCP.

```bash
# Create Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create Provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Create Service Account for CI/CD
gcloud iam service-accounts create runtimeai-cicd \
  --display-name="RuntimeAI CI/CD"

# Grant permissions
gcloud projects add-iam-policy-binding runtimeai-prod \
  --member="serviceAccount:runtimeai-cicd@runtimeai-prod.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding runtimeai-prod \
  --member="serviceAccount:runtimeai-cicd@runtimeai-prod.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Allow GitHub repo to impersonate SA
gcloud iam service-accounts add-iam-policy-binding \
  runtimeai-cicd@runtimeai-prod.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/runtimeai-dev/runtimeai-enterprise"
```

**GitHub Secrets to set:**
| Secret | Value |
|--------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | `runtimeai-cicd@runtimeai-prod.iam.gserviceaccount.com` |

---

## 8. DNS & TLS Setup (runtimeai.io)

### 8.1 Cloud DNS Zone

```bash
# Create DNS zone
gcloud dns managed-zones create runtimeai-io \
  --dns-name="runtimeai.io." \
  --description="RuntimeAI production DNS"

# Get nameservers (update your domain registrar with these)
gcloud dns managed-zones describe runtimeai-io --format="value(nameServers)"
```

### 8.2 DNS Records

```bash
INGRESS_IP=$(terraform output -raw ingress_ip)

# A records for all subdomains
for subdomain in www app api admin sign audit; do
  gcloud dns record-sets create "$subdomain.runtimeai.io." \
    --zone="runtimeai-io" \
    --type="A" \
    --ttl=300 \
    --rrdatas="$INGRESS_IP"
done

# Root domain
gcloud dns record-sets create "runtimeai.io." \
  --zone="runtimeai-io" \
  --type="A" \
  --ttl=300 \
  --rrdatas="$INGRESS_IP"
```

### 8.3 Ingress with TLS

```yaml
# k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: runtimeai-ingress
  namespace: runtimeai
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - www.runtimeai.io
        - app.runtimeai.io
        - api.runtimeai.io
        - admin.runtimeai.io
      secretName: runtimeai-tls
  rules:
    - host: www.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: runtimeai-landing
                port:
                  number: 80
    - host: app.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: runtimeai-dashboard
                port:
                  number: 4000
    - host: api.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: runtimeai-control-plane
                port:
                  number: 8080
    - host: admin.runtimeai.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: runtimeai-saas-admin
                port:
                  number: 7080
```

---

## 9. Security Hardening

### 9.1 GKE Cluster Security

| Control | Setting | Tier 1 | Tier 2 |
|---------|---------|--------|--------|
| Private cluster | Nodes have no public IPs | ✅ | ✅ |
| Workload Identity | No SA key files in pods | ✅ | ✅ |
| Shielded nodes | Secure boot + integrity monitoring | — | ✅ |
| Binary Authorization | Only signed images deploy | — | ✅ |
| Network policies | Namespace-level firewall rules | — | ✅ |
| Pod Security Standards | Restricted policy | ✅ | ✅ |
| Dataplane V2 | eBPF-based networking | — | ✅ |
| GKE Autopilot hardening | Google-managed node security | ✅ | — |

### 9.2 Network Policies

```yaml
# k8s/network-policies.yaml

# Default: deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: runtimeai
spec:
  podSelector: {}
  policyTypes:
    - Ingress

---
# Allow ingress controller → frontend services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-frontends
  namespace: runtimeai
spec:
  podSelector:
    matchLabels:
      tier: frontend
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
  policyTypes:
    - Ingress

---
# Allow control-plane → database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cp-to-db
  namespace: runtimeai
spec:
  podSelector:
    matchLabels:
      app: control-plane
  egress:
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8  # Cloud SQL private IP range
      ports:
        - port: 5432
          protocol: TCP
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8  # Redis private IP range
      ports:
        - port: 6379
          protocol: TCP
  policyTypes:
    - Egress
```

### 9.3 Secret Management

```bash
# Store all secrets in GCP Secret Manager (never in K8s secrets directly)
gcloud secrets create runtimeai-admin-secret --data-file=<(openssl rand -hex 32)
gcloud secrets create runtimeai-jwt-secret --data-file=<(openssl rand -hex 64)

# Use External Secrets Operator to sync GCP secrets → K8s
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace
```

```yaml
# k8s/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: runtimeai-secrets
  namespace: runtimeai
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store
    kind: ClusterSecretStore
  target:
    name: runtimeai-secrets
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: runtimeai-database-url
    - secretKey: REDIS_URL
      remoteRef:
        key: runtimeai-redis-url
    - secretKey: ADMIN_SECRET
      remoteRef:
        key: runtimeai-admin-secret
```

### 9.4 Container Security

```yaml
# Pod Security Standard — enforce in namespace
apiVersion: v1
kind: Namespace
metadata:
  name: runtimeai
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 9.5 Security Checklist

- [ ] All containers run as non-root (`runAsNonRoot: true`)
- [ ] Read-only root filesystem where possible
- [ ] No privileged containers
- [ ] Resource limits set on all pods (prevent noisy neighbors)
- [ ] Cloud SQL requires SSL connections
- [ ] Redis not exposed to internet (private network only)
- [ ] All secrets in GCP Secret Manager (not K8s ConfigMaps)
- [ ] Cloud Armor WAF rules active (Tier 2)
- [ ] VPC Flow Logs enabled
- [ ] Audit logging enabled on GKE
- [ ] Workload Identity (no SA keys)
- [ ] Image scanning enabled in Artifact Registry
- [ ] Binary Authorization enforced (Tier 2)
- [ ] Network policies restrict pod-to-pod traffic

### Frontend Environment Variables

Both the **Enterprise Dashboard** and **SaaS Admin App** use Vite `VITE_*` environment variables. These are baked into the JS bundle at build time.

| Variable | Dashboard | SaaS Admin | Description |
|----------|-----------|------------|-------------|
| `VITE_API_URL` | ✅ | ✅ | Control plane API base URL |
| `VITE_ADMIN_SECRET` | — | ✅ | Admin auth secret (from Secret Manager) |
| `VITE_MARKETPLACE_ADMIN_KEY` | — | ✅ | Marketplace admin key |
| `VITE_LANDING_API_KEY` | ✅ | — | Landing backend API key |
| `VITE_BILLING_API_URL` | ✅ | ✅ | Billing service URL |
| `VITE_MCP_GATEWAY_URL` | ✅ | ✅ | MCP Gateway URL |
| `VITE_ESIGN_URL` | ✅ | ✅ | eSign service URL |
| `VITE_GRAFANA_URL` | ✅ | — | Grafana dashboard (empty in prod to hide) |
| `VITE_PROMETHEUS_URL` | ✅ | — | Prometheus metrics (empty in prod to hide) |
| `VITE_JAEGER_URL` | ✅ | — | Jaeger tracing (empty in prod to hide) |

**Secret Injection at Build Time (GCP)**:
```bash
# Fetch secrets from GCP Secret Manager before Docker build
SAAS_ADMIN_SECRET=$(gcloud secrets versions access latest \
  --secret=runtimeai-saas-admin-secret)

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

## 10. Monitoring & Observability

### 10.1 Built-in Cloud Monitoring

GKE automatically sends metrics to Cloud Monitoring. No setup needed.

```bash
# View cluster metrics
gcloud monitoring dashboards create --config-from-file=k8s/monitoring/dashboard.json
```

### 10.2 Prometheus + Grafana (Optional, for detailed app metrics)

```bash
# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword="$(openssl rand -base64 16)" \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi
```

### 10.3 Alerting

```bash
# Create alert policy for high error rate
gcloud monitoring policies create \
  --display-name="RuntimeAI High Error Rate" \
  --condition-display-name="5xx rate > 1%" \
  --condition-filter='resource.type="k8s_container" AND metric.type="logging.googleapis.com/user/error_count"' \
  --notification-channels="projects/runtimeai-prod/notificationChannels/CHANNEL_ID"
```

---

## 11. Backup & Disaster Recovery

### 11.1 Database Backups

Cloud SQL automated backups are enabled in Terraform. Additionally:

```bash
# Manual backup before major changes
gcloud sql backups create --instance=runtimeai-db-prod --description="Pre-release backup"

# List backups
gcloud sql backups list --instance=runtimeai-db-prod

# Restore from backup
gcloud sql backups restore BACKUP_ID --restore-instance=runtimeai-db-prod
```

### 11.2 Cluster Backup (Velero)

```bash
# Install Velero for K8s resource backup
velero install \
  --provider gcp \
  --plugins velero/velero-plugin-for-gcp:v1.9.0 \
  --bucket runtimeai-backups \
  --secret-file ./credentials-velero

# Schedule daily backups
velero schedule create daily-backup --schedule="0 3 * * *" --ttl 720h0m0s
```

---

## 12. Operational Runbook

### 12.1 Deploy a New Version

```bash
# After merging to main, the CI/CD pipeline auto-deploys.
# For manual deployment:
TAG="v1.2.3"
helm upgrade runtimeai ./deployment/helm/runtimeai-control-plane \
  --namespace runtimeai \
  --set image.tag=$TAG \
  --set dashboard.image.tag=$TAG \
  --wait
```

### 12.2 Rollback

```bash
# View history
helm history runtimeai -n runtimeai

# Rollback to previous version
helm rollback runtimeai 1 -n runtimeai
```

### 12.3 Scale Services

```bash
# Scale a specific deployment
kubectl scale deployment runtimeai-control-plane --replicas=3 -n runtimeai

# Enable HPA
kubectl autoscale deployment runtimeai-control-plane \
  --min=2 --max=10 --cpu-percent=70 -n runtimeai
```

### 12.4 View Logs

```bash
# Pod logs
kubectl logs -f deployment/runtimeai-control-plane -n runtimeai

# Cloud Logging (centralized)
gcloud logging read "resource.type=k8s_container AND resource.labels.namespace_name=runtimeai" \
  --limit=50 --format=json
```

### 12.5 Database Operations

```bash
# Connect to Cloud SQL (via proxy for local access)
gcloud sql connect runtimeai-db-prod --user=runtimeai --database=authzion

# Run migrations
kubectl exec -it deployment/runtimeai-control-plane -n runtimeai -- /app/migrate up
```

---

## 13. Cost Breakdown

### Tier 1 — Bootstrap (~$120-150/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| GKE Autopilot | ~4 vCPU, 8GB used across pods | ~$75 |
| Cloud SQL | db-f1-micro, 10GB | ~$8 |
| Memorystore Redis | Basic 1GB | ~$35 |
| Artifact Registry | ~5GB storage | ~$1 |
| Static IP | 1 global | ~$3 |
| Cloud DNS | 1 zone | ~$0.50 |
| Egress | ~10GB | ~$1 |
| **Total** | | **~$125** |

### Tier 2 — Production (~$600-900/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| GKE Standard | 3x e2-standard-4 (general) + 2x e2-standard-2 (spot) | ~$300 |
| Cloud SQL | db-custom-2-7680, Regional HA, 50GB | ~$150 |
| Memorystore Redis | Standard HA 5GB | ~$175 |
| Cloud Armor | WAF rules | ~$10 |
| Artifact Registry | ~20GB storage | ~$3 |
| Cloud Monitoring | Custom metrics | ~$20 |
| Static IP + DNS | | ~$5 |
| Egress | ~100GB | ~$10 |
| **Total** | | **~$675** |

> **Cost savings tips:**
> - Use committed use discounts (1-year: 37% off, 3-year: 55% off)
> - Schedule non-critical workloads on Spot nodes (60-91% cheaper)
> - Downscale node pools during off-hours
> - Use GKE Autopilot for Tier 1 (only pay for running pods)

---

## 13. Data Plane Services (OPER_RT19-031)

> **Added**: March 2026 — Sidecar Injector, Flow Enforcer, Data Proxy, GitHub App, IdP Connectors

### 13.1 Sidecar Injector (MutatingAdmissionWebhook)

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Deploy sidecar injector
kubectl apply -f deployment/scripts/rt19/k8s/06-sidecar-injector.yaml

# Enable injection for a namespace
kubectl label namespace runtimeai runtimeai.io/inject-sidecar=true
```

### 13.2 Flow Enforcer (Envoy + WASM)

```bash
cd flow-enforcer/templates && ./generate_config.sh -f values-default.yaml -o ../envoy/envoy.yaml
./deployment/scripts/rt19/build-push-deploy.sh flow-enforcer

# GCP: store service token in Secret Manager
echo -n "$(openssl rand -base64 32)" | gcloud secrets create runtimeai-flow-enforcer-token --data-file=-
```

### 13.3 Data Proxy (DLP + PII Masking)

```bash
./deployment/scripts/rt19/build-push-deploy.sh data-proxy
kubectl apply -f services/data-proxy/k8s/sidecar-template.yaml
```

### 13.4 GitHub App (Organization Scanning)

```bash
# Store private key in GCP Secret Manager
gcloud secrets create runtimeai-github-app-key --data-file=/path/to/github-app.pem
echo -n "$(openssl rand -hex 32)" | gcloud secrets create runtimeai-github-webhook-secret --data-file=-

# Webhook URL: https://api.runtimeai.io/api/github/webhook
```

### 13.5 IdP Connectors (OAuth Discovery)

Supported: Okta, Azure AD, **Google Workspace**, AWS IAM, Oracle OCI, MCP Gateway.

```bash
# GCP: use Google Workspace Admin SDK natively
gcloud secrets create runtimeai-google-workspace-creds --data-file=/path/to/service-account.json

curl -X POST https://api.runtimeai.io/api/discovery/idp-connectors \
  -H "Content-Type: application/json" -H "Cookie: session=<session_id>" \
  -d '{
    "provider": "google",
    "display_name": "Production Google Workspace",
    "vault_secret_path": "runtimeai/idp/google",
    "config": {"domain": "company.com", "admin_email": "admin@company.com"},
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

const agent = await client.agents.register({
  name: 'contract-analyzer',
  type: 'langchain',
  owner: 'ml-team@company.com',
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
agents = client.agents.list()
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

### GCP Secret Manager — Retrieve Secrets for Seeding

```bash
# Retrieve API key from GCP Secret Manager
export RUNTIMEAI_API_KEY=$(gcloud secrets versions access latest \
  --secret=runtimeai-api-key)

# Retrieve admin secret
export ADMIN_SECRET=$(gcloud secrets versions access latest \
  --secret=runtimeai-admin-secret)
```

---

## RLS Verification

```bash
CP_POD=$(kubectl get pods -n runtimeai -l app=control-plane -o jsonpath='{.items[0].metadata.name}')
kubectl logs $CP_POD -n runtimeai | grep "RLS" | tail -5
# Expected: [RLS] ENABLED — 80 tenant_isolation policies
```

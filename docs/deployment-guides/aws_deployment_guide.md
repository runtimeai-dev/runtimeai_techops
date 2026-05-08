# RuntimeAI — AWS Deployment Guide

> **Complete step-by-step guide** to deploy the RuntimeAI platform on Amazon Web Services.
> From account creation to running production with CI/CD automation.
>
> **Last Updated**: March 14, 2026
>
> **Prerequisite**: Read [GCP Deployment Guide](./gcp_deployment_guide.md) first for the full service inventory and architecture overview. This guide covers AWS-specific infrastructure only.
>
> **Cross-Cloud Learnings**: See the [Azure Deployment Guide](./azure_deployment_guide.md#real-world-gotchas-from-rt19-deployment) for 13 real-world deployment gotchas.
> Critical fixes that apply to AWS/EKS: health probe path is `/health` (not `/healthz`), auth-service K8s svc must be named `auth-svc` (env collision), containers listen on port 80, set `OTEL_SDK_DISABLED=true`, admin env var is `RUNTIMEAI_ADMIN_SECRET`.
>
> **Self-Hosted Fallback**: If RDS or ElastiCache creation is restricted, self-host PostgreSQL 16 + Redis 7 in EKS. Use `PGDATA=/var/lib/postgresql/data/pgdata` for EBS-backed PVCs.

---

## Table of Contents

1. [Prerequisites & Account Setup](#1-prerequisites--account-setup)
2. [Architecture Mapping (GCP → AWS)](#2-architecture-mapping-gcp--aws)
3. [Tier 1: Minimum Viable Setup (~$150/mo)](#3-tier-1-minimum-viable-setup-150mo)
4. [Tier 2: Scale-Up Production Setup](#4-tier-2-scale-up-production-setup)
5. [Container Registry & Image Management](#5-container-registry--image-management)
6. [CI/CD Pipeline (GitHub Actions → EKS)](#6-cicd-pipeline-github-actions--eks)
7. [DNS & TLS Setup](#7-dns--tls-setup)
8. [Security Hardening](#8-security-hardening)
9. [Monitoring & Observability](#9-monitoring--observability)
10. [Backup & Disaster Recovery](#10-backup--disaster-recovery)
11. [Cost Breakdown](#11-cost-breakdown)

---

## 1. Prerequisites & Account Setup

### 1.1 Create AWS Account for RuntimeAI

```bash
# Step 1: Go to https://aws.amazon.com and click "Create an AWS Account"
# Step 2: Use your business email (e.g., admin@runtimeai.io)
# Step 3: AWS Free Tier gives 12 months of limited free resources

# Install AWS CLI
brew install awscli

# Configure credentials
aws configure
# AWS Access Key ID: [from IAM console]
# AWS Secret Access Key: [from IAM console]
# Default region: us-east-1
# Output format: json

# Install eksctl (EKS cluster management)
brew install eksctl

# Verify
aws --version
eksctl version
kubectl version --client
helm version
terraform version
```

### 1.2 Create IAM Admin User (Never use root account)

```bash
# Create admin group & user via AWS Console:
# 1. IAM → Groups → Create "RuntimeAI-Admins" → Attach "AdministratorAccess"
# 2. IAM → Users → Create "runtimeai-admin" → Add to group
# 3. Create access keys for CLI usage
# 4. Enable MFA on both root and admin accounts
```

---

## 2. Architecture Mapping (GCP → AWS)

| GCP Service | AWS Equivalent | Notes |
|-------------|---------------|-------|
| GKE (Autopilot) | EKS + Fargate | Pay-per-pod (Tier 1) |
| GKE (Standard) | EKS + Managed Node Groups | Fixed nodes (Tier 2) |
| Cloud SQL PostgreSQL | RDS PostgreSQL | Managed DB |
| Memorystore Redis | ElastiCache Redis | Managed Redis |
| Artifact Registry | ECR | Container registry |
| Cloud DNS | Route 53 | DNS management |
| Cloud Armor | AWS WAF + Shield | WAF/DDoS |
| Secret Manager | Secrets Manager | Secret storage |
| Cloud Monitoring | CloudWatch | Metrics/logs |
| Workload Identity | IRSA (IAM Roles for SA) | Pod-level IAM |
| Cloud Load Balancer | ALB (Application LB) | L7 load balancing |
| Cloud Armor WAF | AWS WAF v2 | Web app firewall |

---

## 3. Tier 1: Minimum Viable Setup (~$150/mo)

### 3.1 Terraform — Bootstrap Infrastructure

Create `deployment/terraform/aws/tier1-bootstrap/main.tf`:

```hcl
# =============================================================================
# RuntimeAI — AWS Tier 1 (Bootstrap)
# Estimated cost: ~$120-150/month with free tier
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── Variables ──────────────────────────────────────────────────────────────────

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "cluster_name" {
  type    = string
  default = "runtimeai-cluster"
}

# ── VPC ────────────────────────────────────────────────────────────────────────

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "runtimeai-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true  # Cost saving: single NAT for Tier 1
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# ── EKS Cluster (Fargate — serverless, pay-per-pod) ───────────────────────

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Fargate profiles (serverless — no node management)
  fargate_profiles = {
    runtimeai = {
      name = "runtimeai"
      selectors = [
        { namespace = "runtimeai" },
        { namespace = "kube-system" }
      ]
    }
  }

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  cluster_addons = {
    coredns    = { most_recent = true }
    vpc-cni    = { most_recent = true }
    kube-proxy = { most_recent = true }
  }
}

# ── RDS PostgreSQL (Smallest instance) ─────────────────────────────────────

resource "aws_db_subnet_group" "runtimeai" {
  name       = "runtimeai-db-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name_prefix = "runtimeai-rds-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.cluster_security_group_id]
  }
}

resource "aws_db_instance" "runtimeai" {
  identifier     = "runtimeai-db"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t4g.micro"  # 2 vCPU, 1GB RAM (~$13/mo)

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "authzion"
  username = "runtimeai"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.runtimeai.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:00-Sun:05:00"

  skip_final_snapshot = true  # Set to false for production

  publicly_accessible = false

  performance_insights_enabled = true  # Free for db.t4g.micro
}

# ── ElastiCache Redis (Smallest) ──────────────────────────────────────────

resource "aws_security_group" "redis" {
  name_prefix = "runtimeai-redis-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.cluster_security_group_id]
  }
}

resource "aws_elasticache_subnet_group" "runtimeai" {
  name       = "runtimeai-redis-subnet"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_replication_group" "runtimeai" {
  replication_group_id = "runtimeai-redis"
  description          = "RuntimeAI Redis"

  node_type            = "cache.t4g.micro"  # 0.5GB (~$10/mo)
  num_cache_clusters   = 1                  # Single node for Tier 1
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.runtimeai.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  automatic_failover_enabled = false  # Single node
}

# ── ECR (Container Registry) ──────────────────────────────────────────────

resource "aws_ecr_repository" "services" {
  for_each = toset([
    "control-plane", "dashboard", "auth-service", "mcp-gateway",
    "discovery", "flow-enforcer", "drift-engine", "drift-worker",
    "policy-manager", "waf", "data-proxy", "cost-ledger",
    "billing-service", "runtimeai-landing", "landing-backend",
    "saas-admin", "finops", "aaic", "esign-service", "esign-landing"
  ])

  name                 = "runtimeai/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true  # Security: auto-scan images
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Lifecycle policy: keep only last 10 images
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ── Secrets Manager ───────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "db_url" {
  name = "runtimeai/database-url"
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://runtimeai:${var.db_password}@${aws_db_instance.runtimeai.endpoint}/authzion?sslmode=require"
}

# ── Outputs ────────────────────────────────────────────────────────────────

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "db_endpoint" { value = aws_db_instance.runtimeai.endpoint }
output "redis_endpoint" { value = aws_elasticache_replication_group.runtimeai.primary_endpoint_address }
output "ecr_registry" { value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com" }

data "aws_caller_identity" "current" {}
```

### 3.2 Deploy Tier 1

```bash
cd deployment/terraform/aws/tier1-bootstrap

cat > terraform.tfvars <<EOF
region      = "us-east-1"
db_password = "$(openssl rand -base64 24)"
EOF

terraform init
terraform plan -out tfplan
terraform apply tfplan

# Connect kubectl
aws eks update-kubeconfig --name runtimeai-cluster --region us-east-1
```

### 3.3 Deploy Additional Services (eSign, Auditor, Marketplace, FinOps)

Built from the `runtimeai` repo. See `deployment/scripts/rt19/build-push-deploy.sh` for automation.

```bash
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${REGISTRY}

# EKS uses amd64 (x86) nodes by default — use Graviton for ARM
PLATFORM="linux/amd64"  # Change to linux/arm64 for Graviton instances

for svc in esign-landing esign-service aaic-service auditor-dashboard marketplace-service ai-finops-service; do
  aws ecr create-repository --repository-name ${svc} 2>/dev/null || true
  docker build --platform ${PLATFORM} -t ${REGISTRY}/${svc}:latest runtimeai/${svc}/
  docker push ${REGISTRY}/${svc}:latest
done

kubectl apply -f deployment/scripts/rt19/k8s/03-services.yaml
kubectl apply -f deployment/scripts/rt19/k8s/04-ingress-tls.yaml
```

> [!WARNING]
> **Key gotchas from live deployment**:
> - Dashboard `targetPort: 8080` (not 80) — Dockerfile `USER nginx` can't bind privileged ports
> - Override dashboard env vars: `FINOPS_UPSTREAM`, `AAIC_UPSTREAM`, `MARKETPLACE_UPSTREAM`
> - Graviton (ARM) instances: build with `--platform linux/arm64`

---

## 4. Tier 2: Scale-Up Production Setup

### Key Differences

| Aspect | Tier 1 | Tier 2 |
|--------|--------|--------|
| EKS | Fargate (serverless) | Managed Node Groups (3x m6i.large) |
| RDS | db.t4g.micro (single AZ) | db.r6g.large (Multi-AZ) |
| ElastiCache | cache.t4g.micro (1 node) | cache.r6g.large (2-node HA) |
| NAT Gateway | Single | Per-AZ (HA) |
| WAF | None | AWS WAF v2 |
| **Cost** | **~$150/mo** | **~$700-900/mo** |

### 4.1 Tier 2 Terraform Additions

```hcl
# Add to Tier 2 main.tf — Key differences only

# Managed Node Groups instead of Fargate
eks_managed_node_groups = {
  general = {
    instance_types = ["m6i.large"]  # 2 vCPU, 8GB RAM
    min_size       = 2
    max_size       = 6
    desired_size   = 3
    disk_size      = 50

    labels = { tier = "general" }
  }

  spot = {
    instance_types = ["m6i.large", "m5.large", "m5a.large"]
    capacity_type  = "SPOT"  # 60-90% cheaper
    min_size       = 0
    max_size       = 4
    desired_size   = 1

    labels = { tier = "spot" }
    taints = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
  }
}

# RDS Multi-AZ
resource "aws_db_instance" "runtimeai_prod" {
  instance_class      = "db.r6g.large"   # 2 vCPU, 16GB RAM
  multi_az            = true
  storage_encrypted   = true
  deletion_protection = true
  # ... (same as tier 1 with upgraded specs)
}

# ElastiCache HA
resource "aws_elasticache_replication_group" "runtimeai_prod" {
  num_cache_clusters         = 2  # Primary + replica
  node_type                  = "cache.r6g.large"
  automatic_failover_enabled = true
}

# AWS WAF v2
resource "aws_wafv2_web_acl" "runtimeai" {
  name  = "runtimeai-waf"
  scope = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "rate-limit"
    priority = 1
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
    }
  }

  rule {
    name     = "aws-managed-rules"
    priority = 2
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRules"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "RuntimeAI-WAF"
  }
}
```

---

## 5. Container Registry & Image Management

```bash
# Authenticate Docker with ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com

# Build & push (same pattern as GCP, different registry URL)
REGISTRY="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com/runtimeai"
docker tag control-plane:latest $REGISTRY/control-plane:latest
docker push $REGISTRY/control-plane:latest
```

---

## 6. CI/CD Pipeline (GitHub Actions → EKS)

```yaml
# .github/workflows/deploy-aws.yml
name: Deploy to AWS (EKS)

on:
  workflow_dispatch:  # Manual trigger only (cost containment)
  # push:            # Uncomment when ready for auto-deploy
  #   branches: [main]

env:
  AWS_REGION: us-east-1
  CLUSTER: runtimeai-cluster

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build & Push Images
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}/runtimeai
        run: |
          TAG="${GITHUB_SHA::8}"
          SERVICES="control-plane dashboard auth-service mcp-gateway"
          for svc in $SERVICES; do
            docker compose -f deployment/docker-compose/docker-compose.yml build $svc
            docker tag docker-compose-$svc:latest $REGISTRY/$svc:$TAG
            docker push $REGISTRY/$svc:$TAG
          done

      - name: Deploy to EKS
        run: |
          aws eks update-kubeconfig --name $CLUSTER --region $AWS_REGION
          TAG="${GITHUB_SHA::8}"
          helm upgrade --install runtimeai ./deployment/helm/runtimeai-control-plane \
            --namespace runtimeai --set image.tag=$TAG --wait
```

### OIDC Setup (Keyless Auth — No Access Keys)

```bash
# Create OIDC provider for GitHub
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create role for GitHub Actions
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:runtimeai-dev/*:ref:refs/heads/main"
      }
    }
  }]
}
EOF

aws iam create-role --role-name RuntimeAI-GitHubActions \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy --role-name RuntimeAI-GitHubActions \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-role-policy --role-name RuntimeAI-GitHubActions \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

---

## 7. DNS & TLS Setup

```bash
# Create Route 53 hosted zone
aws route53 create-hosted-zone --name runtimeai.io --caller-reference $(date +%s)

# Get nameservers → update at domain registrar
aws route53 get-hosted-zone --id /hostedzone/ZONE_ID --query 'DelegationSet.NameServers'

# TLS: Use AWS Certificate Manager (free for ALB-attached certs)
aws acm request-certificate \
  --domain-name "*.runtimeai.io" \
  --subject-alternative-names "runtimeai.io" \
  --validation-method DNS

# Install AWS Load Balancer Controller (for ALB ingress)
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=runtimeai-cluster
```

---

## 8. Security Hardening

### AWS-Specific Security Controls

| Control | Setting | Tier 1 | Tier 2 |
|---------|---------|--------|--------|
| VPC private subnets | Nodes in private subnets | ✅ | ✅ |
| IRSA | Pod-level IAM (no node-wide permissions) | ✅ | ✅ |
| ECR image scanning | Auto-scan on push | ✅ | ✅ |
| RDS encryption | AES-256 at rest + TLS in transit | ✅ | ✅ |
| ElastiCache encryption | At-rest + in-transit | ✅ | ✅ |
| AWS WAF v2 | OWASP rules + rate limiting | — | ✅ |
| GuardDuty | Threat detection | — | ✅ |
| CloudTrail | API audit logging | ✅ | ✅ |
| Security Hub | Centralized security findings | — | ✅ |
| KMS customer-managed keys | Encrypt all data stores | — | ✅ |

### Enable GuardDuty & CloudTrail (Tier 2)

```bash
# Enable GuardDuty (threat detection)
aws guardduty create-detector --enable

# Enable CloudTrail (API audit log)
aws cloudtrail create-trail \
  --name runtimeai-audit \
  --s3-bucket-name runtimeai-cloudtrail-logs \
  --is-multi-region-trail \
  --enable-log-file-validation

aws cloudtrail start-logging --name runtimeai-audit
```

### Security Checklist (AWS)

- [ ] Root account has MFA enabled
- [ ] No root account access keys exist
- [ ] IAM users have MFA
- [ ] EKS API server in private/restricted mode (Tier 2)
- [ ] IRSA configured for all service accounts
- [ ] All S3 buckets have versioning and encryption
- [ ] RDS publicly accessible = false
- [ ] Security groups follow least-privilege
- [ ] VPC Flow Logs enabled
- [ ] CloudTrail logging to S3 with log validation
- [ ] GuardDuty active (Tier 2)
- [ ] ECR image scanning on push
- [ ] Secrets in AWS Secrets Manager (not environment variables)

### Frontend Environment Variables

Both the **Enterprise Dashboard** and **SaaS Admin App** use Vite `VITE_*` environment variables. These are baked into the JS bundle at build time.

| Variable | Dashboard | SaaS Admin | Description |
|----------|-----------|------------|-------------|
| `VITE_API_URL` | ✅ | ✅ | Control plane API base URL |
| `VITE_ADMIN_SECRET` | — | ✅ | Admin auth secret (from Secrets Manager) |
| `VITE_MARKETPLACE_ADMIN_KEY` | — | ✅ | Marketplace admin key |
| `VITE_LANDING_API_KEY` | ✅ | — | Landing backend API key |
| `VITE_BILLING_API_URL` | ✅ | ✅ | Billing service URL |
| `VITE_MCP_GATEWAY_URL` | ✅ | ✅ | MCP Gateway URL |
| `VITE_ESIGN_URL` | ✅ | ✅ | eSign service URL |
| `VITE_GRAFANA_URL` | ✅ | — | Grafana dashboard (empty in prod to hide) |
| `VITE_PROMETHEUS_URL` | ✅ | — | Prometheus metrics (empty in prod to hide) |
| `VITE_JAEGER_URL` | ✅ | — | Jaeger tracing (empty in prod to hide) |

**Secret Injection at Build Time (AWS)**:
```bash
# Fetch secrets from AWS Secrets Manager before Docker build
SAAS_ADMIN_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id runtimeai/saas-admin-secret \
  --query SecretString --output text)

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

> **Full guide**: [rt19_monitoring_guide.md](./rt19_monitoring_guide.md)

### Option A: RuntimeAI Monitoring Stack (Recommended — ~$1/mo)

```bash
# Deploy Prometheus + Grafana + Blackbox Exporter + kube-state-metrics
kubectl apply -f deployment/scripts/rt19/k8s/05-monitoring.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s

# Install node-exporter (for Node CPU & Memory panels)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring

# Install metrics-server (EKS doesn't include it by default)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Access Grafana (pre-built 10-panel dashboard)
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# http://localhost:3000 — admin / RuntimeAI2026!
```

### Option B: CloudWatch Container Insights

```bash
# CloudWatch Container Insights (EKS)
aws eks create-addon --cluster-name runtimeai-cluster \
  --addon-name amazon-cloudwatch-observability
```

### EKS-Specific Notes

| Item | Detail |
|------|--------|
| **PVC permissions** | EBS CSI driver needs `fsGroup` in securityContext (same as AKS) |
| **metrics-server** | NOT pre-installed on EKS — must install manually |
| **EBS CSI driver** | Required for PVCs: `aws eks create-addon --addon-name aws-ebs-csi-driver` |
| **Cost** | Self-hosted: ~$1/mo (PVCs). CloudWatch: ~$10-30/mo |

### Health Check Script

```bash
./deployment/scripts/rt19/health-monitor.sh        # One-shot
./deployment/scripts/rt19/health-monitor.sh --watch # Continuous
```

---

## 10. Backup & Disaster Recovery

```bash
# RDS automated backups configured in Terraform (7-day retention)

# Manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier runtimeai-db \
  --db-snapshot-identifier pre-release-$(date +%Y%m%d)

# EKS backup with Velero
velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket runtimeai-backups --backup-location-config region=us-east-1
```

---

## 11. Cost Breakdown

### Tier 1 (~$120-150/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| EKS Control Plane | Fixed | $73 |
| EKS Fargate | ~4 vCPU, 8GB across pods | ~$30 |
| RDS PostgreSQL | db.t4g.micro, 20GB | ~$13 |
| ElastiCache Redis | cache.t4g.micro | ~$10 |
| NAT Gateway | Single + data | ~$35 |
| ECR | ~5GB storage | ~$1 |
| Route 53 | 1 hosted zone | ~$0.50 |
| **Total** | | **~$165** |

> **Note**: AWS is slightly more expensive than GCP for Tier 1 due to the EKS control plane fee ($73/mo) and NAT Gateway costs.

### Tier 2 (~$700-900/mo)

| Resource | Spec | Cost/mo |
|----------|------|---------|
| EKS + 3x m6i.large | 6 vCPU, 24GB + spot pool | ~$300 |
| RDS Multi-AZ | db.r6g.large, 50GB | ~$200 |
| ElastiCache HA | cache.r6g.large, 2 nodes | ~$150 |
| NAT Gateways | Per-AZ (2) | ~$70 |
| AWS WAF | Rules + requests | ~$15 |
| ALB | + data processing | ~$25 |
| **Total** | | **~$760** |

> **Cost savings**: Use Savings Plans (1-year: ~30% off) or Reserved Instances. Use Spot for non-critical workloads.

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

# Verify
kubectl get mutatingwebhookconfigurations | grep runtimeai
```

### 12.2 Flow Enforcer (Envoy + WASM)

```bash
# Generate config from template
cd flow-enforcer/templates && ./generate_config.sh -f values-default.yaml -o ../envoy/envoy.yaml

# Build and push image
./deployment/scripts/rt19/build-push-deploy.sh flow-enforcer

# AWS: store service token in Secrets Manager
aws secretsmanager create-secret --name runtimeai/flow-enforcer/service-token \
  --secret-string "$(openssl rand -base64 32)" --region us-east-1
```

### 12.3 Data Proxy (DLP + PII Masking)

```bash
# Build and push
./deployment/scripts/rt19/build-push-deploy.sh data-proxy

# Deploy standalone (if not using sidecar injection)
kubectl apply -f services/data-proxy/k8s/sidecar-template.yaml

# Verify health
kubectl exec -it <data-proxy-pod> -- wget -q -O- http://localhost:9090/healthz
```

### 12.4 GitHub App (Organization Scanning)

```bash
# 1. Register at https://github.com/settings/apps/new (use manifest: discovery/github-app/app-manifest.json)

# 2. Store private key in AWS Secrets Manager
aws secretsmanager create-secret --name runtimeai/github-app/private-key \
  --secret-string file:///path/to/github-app.pem --region us-east-1

# 3. Store webhook secret
aws secretsmanager create-secret --name runtimeai/github-app/webhook-secret \
  --secret-string "$(openssl rand -hex 32)" --region us-east-1

# 4. Webhook URL: https://api.runtimeai.io/api/github/webhook
```

### 12.5 IdP Connectors (OAuth Discovery)

Supported: Okta, Azure AD, Google Workspace, **AWS IAM Identity Center**, Oracle OCI, MCP Gateway.

```bash
# AWS: use IAM Identity Center natively
aws secretsmanager create-secret --name runtimeai/idp/aws-sso \
  --secret-string '{"region":"us-east-1","instance_arn":"arn:aws:sso:::instance/ssoins-xxx"}' \
  --region us-east-1

# Create connector via API
curl -X POST https://api.runtimeai.io/api/discovery/idp-connectors \
  -H "Content-Type: application/json" -H "Cookie: session=<session_id>" \
  -d '{
    "provider": "aws",
    "display_name": "Production AWS IAM Identity Center",
    "vault_secret_path": "runtimeai/idp/aws-sso",
    "config": {"region": "us-east-1"},
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

All 24 services are published to GitHub Container Registry:

```bash
# Pull images from GHCR (no ECR required)
docker pull ghcr.io/runtimeai-dev/control-plane:latest
docker pull ghcr.io/runtimeai-dev/dashboard:latest
docker pull ghcr.io/runtimeai-dev/auth-service:latest
docker pull ghcr.io/runtimeai-dev/mcp-gateway:latest
```

---

## API-Based Seeding (No Direct SQL)

> **Critical**: All seed operations use API endpoints exclusively. No `docker exec psql`.

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
| `/api/governance/conditional-access` | POST | Create conditional access |
| `/api/discovery/import` | POST | Import scanner findings |

### AWS Secrets Manager — Retrieve Secrets for Seeding

```bash
# Retrieve API key from AWS Secrets Manager
export RUNTIMEAI_API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id runtimeai/api-key \
  --query SecretString --output text)

# Retrieve admin secret
export ADMIN_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id runtimeai/admin-secret \
  --query SecretString --output text)
```

---

## RLS Verification

After deployment, verify Row-Level Security is active:

```bash
CP_POD=$(kubectl get pods -n runtimeai -l app=control-plane -o jsonpath='{.items[0].metadata.name}')
kubectl logs $CP_POD -n runtimeai | grep "RLS" | tail -5
# Expected: [RLS] ENABLED — 80 tenant_isolation policies
```

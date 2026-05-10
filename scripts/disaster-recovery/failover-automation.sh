#!/bin/bash
# Automated Failover from rt19 (staging) to rt01/rt02 (production)
# Triggers: Primary cluster down, RTO/RPO breach, manual request
# Coordination: DNS failover, traffic reroute, health validation

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

# Configuration
PRIMARY_CLUSTER="rt19"
FAILOVER_CLUSTER="rt01"
DRY_RUN=${1:-"--dry-run"}
HEALTH_CHECKS_RETRIES=5
HEALTH_CHECK_INTERVAL=10

log_info "Failover Automation — $PRIMARY_CLUSTER → $FAILOVER_CLUSTER"
echo ""

# Step 1: Check primary cluster health
log_info "Step 1: Checking primary cluster ($PRIMARY_CLUSTER) health..."
kubectl cluster-info --context "$PRIMARY_CLUSTER" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  log_warning "Primary cluster is still healthy — manual failover required"
  exit 1
fi
log_success "Primary cluster confirmed unavailable"
echo ""

# Step 2: Validate failover target
log_info "Step 2: Validating failover target ($FAILOVER_CLUSTER)..."
kubectl cluster-info --context "$FAILOVER_CLUSTER" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  log_error "Failover target is unreachable!"
  exit 1
fi
log_success "Failover target ($FAILOVER_CLUSTER) is healthy"
echo ""

# Step 3: Restore data from latest backup
log_info "Step 3: Restoring latest backup to $FAILOVER_CLUSTER..."
if [ "$DRY_RUN" != "--dry-run" ]; then
  kubectl config use-context "$FAILOVER_CLUSTER"
  
  # Get latest PostgreSQL backup
  LATEST_BACKUP=$(az storage blob list \
    --account-name runtimeaicr \
    --container-name backups \
    --auth-mode login \
    --query "[-1].name" -o tsv)
  
  log_info "  Downloading backup: $LATEST_BACKUP..."
  az storage blob download \
    --account-name runtimeaicr \
    --container-name backups \
    --name "$LATEST_BACKUP" \
    --file "/tmp/backup.sql.gz" \
    --auth-mode login
  
  # Restore to PostgreSQL
  POSTGRES_HOST=$(kubectl get secret postgres-credentials -n rt01 -o jsonpath='{.data.host}' | base64 -d)
  POSTGRES_USER=$(kubectl get secret postgres-credentials -n rt01 -o jsonpath='{.data.user}' | base64 -d)
  POSTGRES_PASSWORD=$(kubectl get secret postgres-credentials -n rt01 -o jsonpath='{.data.password}' | base64 -d)
  
  log_info "  Restoring PostgreSQL..."
  zcat "/tmp/backup.sql.gz" | pg_restore -h "$POSTGRES_HOST" -U "$POSTGRES_USER" \
    --password="$POSTGRES_PASSWORD" -d rt01
  
  log_success "Data restoration complete"
  rm "/tmp/backup.sql.gz"
else
  log_info "DRY-RUN: Would restore latest backup to $FAILOVER_CLUSTER"
fi
echo ""

# Step 4: DNS failover
log_info "Step 4: Performing DNS failover..."
if [ "$DRY_RUN" != "--dry-run" ]; then
  # Update Azure Traffic Manager to route to rt01
  az network traffic-manager endpoint update \
    --resource-group runtimeai-rg \
    --profile-name runtimeai-tm \
    --type azureEndpoints \
    --name rt19-endpoint \
    --endpoint-status Disabled
  
  az network traffic-manager endpoint update \
    --resource-group runtimeai-rg \
    --profile-name runtimeai-tm \
    --type azureEndpoints \
    --name rt01-endpoint \
    --endpoint-status Enabled
  
  log_success "DNS updated: traffic routing to $FAILOVER_CLUSTER"
else
  log_info "DRY-RUN: Would update DNS traffic manager"
fi
echo ""

# Step 5: Health checks
log_info "Step 5: Validating failover health..."
kubectl config use-context "$FAILOVER_CLUSTER"

HEALTH_CHECK_PASS=0
HEALTH_CHECK_FAIL=0

for i in $(seq 1 $HEALTH_CHECKS_RETRIES); do
  log_info "  Health check attempt $i/$HEALTH_CHECKS_RETRIES..."
  
  # Check core services
  for service in control-plane cost-ledger drift-engine waf mcp-gateway; do
    if kubectl get deployment "$service" -n rt01 > /dev/null 2>&1; then
      STATUS=$(kubectl get deployment "$service" -n rt01 -o jsonpath='{.status.conditions[0].status}')
      if [ "$STATUS" = "True" ]; then
        HEALTH_CHECK_PASS=$((HEALTH_CHECK_PASS + 1))
      else
        HEALTH_CHECK_FAIL=$((HEALTH_CHECK_FAIL + 1))
      fi
    fi
  done
  
  if [ $HEALTH_CHECK_FAIL -eq 0 ]; then
    log_success "All services healthy"
    break
  fi
  
  sleep $HEALTH_CHECK_INTERVAL
done

if [ $HEALTH_CHECK_FAIL -gt 0 ]; then
  log_error "Some services failed health checks ($HEALTH_CHECK_FAIL failures)"
  exit 1
fi

log_success "Failover validation completed successfully"
echo ""

log_success "Failover to $FAILOVER_CLUSTER completed successfully"
log_warning "Manual verification recommended: curl https://app.runtimeai.io/health"

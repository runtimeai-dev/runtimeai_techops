#!/bin/bash
# RTO/RPO Validation (target: RTO 1h, RPO 15min) — TOPS-055

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

# Targets
TARGET_RTO_MINUTES=60
TARGET_RPO_MINUTES=15

log_info "Starting RTO/RPO validation..."

# 1. Measure RPO (last backup timestamp)
LAST_BACKUP=$(aws rds describe-db-snapshots \
  --query 'DBSnapshots[0].SnapshotCreateTime' \
  --output text)
BACKUP_AGE_MINUTES=$(( ($(date +%s) - $(date -d "$LAST_BACKUP" +%s)) / 60 ))

log_info "Last backup: $BACKUP_AGE_MINUTES minutes ago"
if [ "$BACKUP_AGE_MINUTES" -le "$TARGET_RPO_MINUTES" ]; then
  log_success "RPO OK: $BACKUP_AGE_MINUTES min (target: $TARGET_RPO_MINUTES min)"
else
  log_error "RPO FAIL: $BACKUP_AGE_MINUTES min exceeds target of $TARGET_RPO_MINUTES min"
  exit 1
fi

# 2. Measure RTO (failover time simulation)
log_info "Simulating failover RTO..."
START_TIME=$(date +%s)

# Create test restore instance
RESTORE_ID="rto-test-$(date +%s)"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$RESTORE_ID" \
  --db-snapshot-identifier "$(aws rds describe-db-snapshots --query 'DBSnapshots[0].DBSnapshotIdentifier' --output text)" \
  --no-cli-pager

# Wait for restore (this is RTO)
while [ "$(aws rds describe-db-instances --db-instance-identifier "$RESTORE_ID" --query 'DBInstances[0].DBInstanceStatus' --output text)" != "available" ]; do
  sleep 10
done

RTO_MINUTES=$(( ($(date +%s) - $START_TIME) / 60 ))
log_info "Simulated failover time: $RTO_MINUTES minutes"

if [ "$RTO_MINUTES" -le "$TARGET_RTO_MINUTES" ]; then
  log_success "RTO OK: $RTO_MINUTES min (target: $TARGET_RTO_MINUTES min)"
else
  log_error "RTO FAIL: $RTO_MINUTES min exceeds target of $TARGET_RTO_MINUTES min"
fi

# Cleanup
aws rds delete-db-instance --db-instance-identifier "$RESTORE_ID" --skip-final-snapshot

log_success "RTO/RPO validation complete"

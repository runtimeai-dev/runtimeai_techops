#!/bin/bash
# Database Restore Testing (weekly restore to test environment) — TOPS-047

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

log_info "Testing database restore to staging environment..."

# 1. Get latest backup
LATEST_BACKUP=$(aws rds describe-db-snapshots \
  --db-instance-identifier rt19-db \
  --query 'DBSnapshots[0].DBSnapshotIdentifier' \
  --output text)

log_info "Latest backup: $LATEST_BACKUP"

# 2. Create restore instance
RESTORE_ID="rt19-test-restore-$(date +%s)"
log_info "Creating restore instance: $RESTORE_ID"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$RESTORE_ID" \
  --db-snapshot-identifier "$LATEST_BACKUP" \
  --db-instance-class db.standard_d2s_v3 \
  --publicly-accessible false

# 3. Wait for restore to complete
log_info "Waiting for restore... (this takes ~15-30 minutes)"
aws rds wait db-instance-available --db-instance-identifier "$RESTORE_ID"
log_success "Restore instance ready"

# 4. Run test queries
log_info "Running integrity checks..."
ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$RESTORE_ID" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Test table counts
psql -h "$ENDPOINT" -U postgres -d rt19 -c "SELECT COUNT(*) FROM information_schema.tables;" > /tmp/restore-test.log
psql -h "$ENDPOINT" -U postgres -d rt19 -c "SELECT COUNT(*) FROM tenants;" >> /tmp/restore-test.log
psql -h "$ENDPOINT" -U postgres -d rt19 -c "SELECT COUNT(*) FROM users;" >> /tmp/restore-test.log

log_success "Restore validation complete (see /tmp/restore-test.log)"

# 5. Cleanup restore instance
log_info "Cleaning up restore instance..."
aws rds delete-db-instance \
  --db-instance-identifier "$RESTORE_ID" \
  --skip-final-snapshot

log_success "Restore testing complete"

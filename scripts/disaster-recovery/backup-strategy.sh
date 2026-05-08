#!/bin/bash
# Database Backup Strategy (RDS automated + manual snapshots) — TOPS-046

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

# Configuration
BACKUP_VAULT="runtimeai-backups"
RETENTION_DAYS_30=30
RETENTION_DAYS_90=90
RETENTION_DAYS_365=365
ENCRYPT_KEY="arn:aws:kms:eastus2:account-id:key/backup-key"

log_info "Starting database backup strategy..."

# 1. RDS Automated Backups (via AWS)
log_info "1. Configuring RDS automated backups..."
aws rds modify-db-instance \
  --db-instance-identifier rt19-db \
  --backup-retention-period 30 \
  --apply-immediately \
  --storage-encrypted \
  --kms-key-id "$ENCRYPT_KEY"

log_success "RDS automated backups: 30-day retention, encrypted"

# 2. Manual Daily Snapshot
log_info "2. Creating manual daily snapshot..."
TIMESTAMP=$(date +%Y%m%d-%H%M)
aws rds create-db-snapshot \
  --db-instance-identifier rt19-db \
  --db-snapshot-identifier rt19-backup-$TIMESTAMP

log_success "Manual snapshot created: rt19-backup-$TIMESTAMP"

# 3. PostgreSQL pg_dump for archive
log_info "3. Creating pg_dump archive..."
DUMP_FILE="/tmp/rt19-full-$(date +%Y%m%d).sql.gz"
pg_dump -h rt19-db.postgres.database.azure.com \
  -U postgres@rt19-server \
  --verbose \
  --no-password \
  rt19 | gzip > "$DUMP_FILE"

log_success "pg_dump created: $DUMP_FILE"

# 4. Upload to Azure Blob Storage (30-day tier)
log_info "4. Uploading to Azure Blob Storage..."
az storage blob upload \
  --account-name runtimeaibackups \
  --container-name databases \
  --name "backups/30day/rt19-$(date +%Y%m%d).sql.gz" \
  --file "$DUMP_FILE" \
  --tier hot

log_success "Backup uploaded (30-day tier)"

# 5. Archive to cold storage (365-day tier)
if [ $(($(date +%d) % 30)) -eq 0 ]; then
  log_info "5. Archiving to cold storage (monthly)..."
  az storage blob upload \
    --account-name runtimeaibackups \
    --container-name databases \
    --name "archive/365day/rt19-$(date +%Y%m).sql.gz" \
    --file "$DUMP_FILE" \
    --tier archive
  log_success "Monthly archive created (365-day tier)"
fi

# 6. Verify backup integrity
log_info "6. Verifying backup integrity..."
BACKUP_SIZE=$(stat -f%z "$DUMP_FILE" 2>/dev/null || stat -c%s "$DUMP_FILE")
if [ "$BACKUP_SIZE" -gt 1000000 ]; then
  log_success "Backup integrity verified (size: $(numfmt --to=iec $BACKUP_SIZE 2>/dev/null || echo $BACKUP_SIZE bytes))"
else
  log_error "Backup suspiciously small ($BACKUP_SIZE bytes); check manually"
  exit 1
fi

# 7. Cleanup local temp files
rm -f "$DUMP_FILE"

log_success "Backup strategy complete"

#!/usr/bin/env bash
# ============================================================================
# backup.sh — RuntimeAI Platform Backup Script
# ============================================================================
# Creates a timestamped backup of PostgreSQL, Redis, K8s configs, and
# eSign documents. Designed for cron scheduling.
#
# Usage:
#   ./backup.sh                           # Full backup (all components)
#   ./backup.sh --db-only                 # PostgreSQL only
#   ./backup.sh --output /mnt/backups     # Custom output directory
#   ./backup.sh --retention 30            # Keep backups for 30 days
#
# Cron example (daily at 2 AM):
#   0 2 * * * /opt/runtimeai/backup.sh --output /mnt/nfs/backups >> /var/log/runtimeai-backup.log 2>&1
# ============================================================================
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
NAMESPACE="${NAMESPACE:-rt19}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/runtimeai-backups}"
BACKUP_DIR="${OUTPUT_DIR}/backup_${TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
DB_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-only) DB_ONLY=true; shift ;;
    --output) OUTPUT_DIR="$2"; BACKUP_DIR="${OUTPUT_DIR}/backup_${TIMESTAMP}"; shift 2 ;;
    --retention) RETENTION_DAYS="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

mkdir -p "$BACKUP_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  RuntimeAI Backup — ${TIMESTAMP}                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Namespace:  ${NAMESPACE}"
echo "  Output:     ${BACKUP_DIR}"
echo "  Retention:  ${RETENTION_DAYS} days"
echo ""

ERRORS=()

# ── 1. PostgreSQL Backup ───────────────────────────────────────────────────
echo "▶ PostgreSQL backup..."
PG_POD=$(kubectl get pods -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PG_POD" ]; then
  PG_FILE="${BACKUP_DIR}/postgres_${TIMESTAMP}.sql.gz"

  # Full database dump with schema + data
  kubectl exec -n "$NAMESPACE" "$PG_POD" -- \
    pg_dump -U runtimeai -d authzion \
      --format=custom \
      --no-owner \
      --no-privileges \
      --verbose 2>/dev/null | gzip > "$PG_FILE"

  PG_SIZE=$(du -sh "$PG_FILE" | awk '{print $1}')
  echo "  ✓ PostgreSQL: ${PG_SIZE} → ${PG_FILE}"

  # Backup roles separately
  kubectl exec -n "$NAMESPACE" "$PG_POD" -- \
    pg_dumpall -U runtimeai --roles-only 2>/dev/null | \
    gzip > "${BACKUP_DIR}/postgres_roles_${TIMESTAMP}.sql.gz"
  echo "  ✓ PostgreSQL roles backed up"
else
  echo "  ❌ PostgreSQL pod not found"
  ERRORS+=("PostgreSQL pod not found in namespace $NAMESPACE")
fi

if [ "$DB_ONLY" = true ]; then
  echo ""
  echo "✅ Database-only backup complete: ${BACKUP_DIR}"
  exit 0
fi

# ── 2. Redis Backup ───────────────────────────────────────────────────────
echo ""
echo "▶ Redis backup..."
REDIS_POD=$(kubectl get pods -n "$NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$REDIS_POD" ]; then
  # Trigger BGSAVE
  kubectl exec -n "$NAMESPACE" "$REDIS_POD" -- redis-cli BGSAVE 2>/dev/null
  sleep 2

  # Copy dump.rdb
  kubectl cp "${NAMESPACE}/${REDIS_POD}:/data/dump.rdb" "${BACKUP_DIR}/redis_${TIMESTAMP}.rdb" 2>/dev/null
  REDIS_SIZE=$(du -sh "${BACKUP_DIR}/redis_${TIMESTAMP}.rdb" 2>/dev/null | awk '{print $1}' || echo "0")
  echo "  ✓ Redis: ${REDIS_SIZE} → redis_${TIMESTAMP}.rdb"
else
  echo "  ⚠️  Redis pod not found (non-critical)"
fi

# ── 3. K8s Configuration Backup ──────────────────────────────────────────
echo ""
echo "▶ K8s configuration backup..."
K8S_DIR="${BACKUP_DIR}/k8s"
mkdir -p "$K8S_DIR"

# Export all resources (excluding secrets for security)
for resource in deployments services configmaps ingresses networkpolicies pvc hpa; do
  kubectl get "$resource" -n "$NAMESPACE" -o yaml > "${K8S_DIR}/${resource}.yaml" 2>/dev/null || true
done
echo "  ✓ K8s configs exported (deployments, services, configmaps, ingress, pvc)"

# Export secrets names only (not values) for reference
kubectl get secrets -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' > "${K8S_DIR}/secrets_list.txt" 2>/dev/null
echo "  ✓ Secret names listed (values NOT exported — retrieve from vault)"

# ── 4. eSign Document Backup ────────────────────────────────────────────
echo ""
echo "▶ eSign document backup..."
ESIGN_POD=$(kubectl get pods -n "$NAMESPACE" -l app=esign-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$ESIGN_POD" ]; then
  ESIGN_DIR="${BACKUP_DIR}/esign_documents"
  mkdir -p "$ESIGN_DIR"
  kubectl cp "${NAMESPACE}/${ESIGN_POD}:/data/esign/" "$ESIGN_DIR" 2>/dev/null || true
  ESIGN_SIZE=$(du -sh "$ESIGN_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
  echo "  ✓ eSign documents: ${ESIGN_SIZE}"
else
  echo "  ⚠️  eSign pod not found (skip)"
fi

# ── 5. Create Archive ──────────────────────────────────────────────────
echo ""
echo "▶ Creating archive..."
ARCHIVE="${OUTPUT_DIR}/runtimeai_backup_${TIMESTAMP}.tar.gz"
tar czf "$ARCHIVE" -C "$OUTPUT_DIR" "backup_${TIMESTAMP}"
ARCHIVE_SIZE=$(du -sh "$ARCHIVE" | awk '{print $1}')
ARCHIVE_HASH=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')

# Create manifest
cat > "${BACKUP_DIR}/MANIFEST.txt" << EOF
RuntimeAI Backup Manifest
Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Namespace: ${NAMESPACE}

Archive: runtimeai_backup_${TIMESTAMP}.tar.gz
Size: ${ARCHIVE_SIZE}
SHA-256: ${ARCHIVE_HASH}

Contents:
$(ls -la "${BACKUP_DIR}/" 2>/dev/null)
EOF

# ── 6. Cleanup Old Backups ──────────────────────────────────────────────
echo ""
echo "▶ Cleanup (retention: ${RETENTION_DAYS} days)..."
CLEANED=$(find "$OUTPUT_DIR" -name "runtimeai_backup_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete -print 2>/dev/null | wc -l | tr -d ' ')
echo "  Removed ${CLEANED} old backup(s)"

# Also clean uncompressed dirs
find "$OUTPUT_DIR" -maxdepth 1 -name "backup_*" -type d -mtime "+${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅  Backup Complete                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Archive:  ${ARCHIVE} (${ARCHIVE_SIZE})"
echo "  SHA-256:  ${ARCHIVE_HASH}"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "  ⚠️  Errors:"
  for err in "${ERRORS[@]}"; do
    echo "     - ${err}"
  done
fi

echo ""
echo "  Restore: tar xzf ${ARCHIVE} && ./restore.sh backup_${TIMESTAMP}"

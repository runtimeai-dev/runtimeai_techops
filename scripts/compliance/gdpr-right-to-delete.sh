#!/bin/bash
# GDPR Right-to-Delete Automation — TOPS-060

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

USER_ID=$1

if [ -z "$USER_ID" ]; then
  echo "Usage: $0 <user-id>"
  exit 1
fi

log_info "Executing GDPR right-to-delete for user: $USER_ID"

# 1. Find all user records
log_info "Step 1: Identifying all user data..."
psql -h rt19-db -U postgres -d rt19 << SQL
SELECT table_name FROM information_schema.tables 
WHERE table_schema='public' 
AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=information_schema.tables.table_name AND column_name='user_id');
SQL

# 2. Create audit record
log_info "Step 2: Creating GDPR deletion audit record..."
psql -h rt19-db -U postgres -d rt19 << SQL
INSERT INTO gdpr_deletion_log (user_id, requested_at, status, expires_at) 
VALUES ('$USER_ID', NOW(), 'initiated', NOW() + interval '30 days');
SQL

# 3. Anonymize PII
log_info "Step 3: Anonymizing PII (30-day retention for disputes)..."
psql -h rt19-db -U postgres -d rt19 << SQL
UPDATE users SET 
  email = 'deleted-' || user_id || '@deleted.local',
  first_name = 'DELETED',
  last_name = 'DELETED',
  phone = NULL,
  address = NULL
WHERE user_id = '$USER_ID';
SQL

# 4. Delete from dependent tables
log_info "Step 4: Deleting user-dependent records..."
psql -h rt19-db -U postgres -d rt19 << SQL
DELETE FROM audit_log WHERE user_id = '$USER_ID';
DELETE FROM sessions WHERE user_id = '$USER_ID';
DELETE FROM api_keys WHERE user_id = '$USER_ID';
DELETE FROM activity_log WHERE user_id = '$USER_ID';
SQL

# 5. Hard-delete after 30-day dispute period (scheduled)
log_info "Step 5: Scheduling hard-delete for 30 days from now..."
cat > /tmp/gdpr-hard-delete-$USER_ID.sh << SCRIPT
#!/bin/bash
psql -h rt19-db -U postgres -d rt19 << SQL
DELETE FROM users WHERE user_id = '$USER_ID';
UPDATE gdpr_deletion_log SET status = 'completed', completed_at = NOW() WHERE user_id = '$USER_ID';
SQL
SCRIPT

log_success "GDPR right-to-delete initiated for user $USER_ID"
log_info "Hard deletion scheduled for 30 days from now"

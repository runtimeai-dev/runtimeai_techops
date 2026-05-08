#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# wipe_and_reseed_rt19.sh — Full database wipe and fresh reseed
#
# This script:
#   1. Truncates ALL data in the rt19 database (preserves schema)
#   2. Recovers any soft-deleted Azure Key Vault secrets
#   3. Seeds felt-sense-ai and runtimeai-test tenants
#   4. Sets known passwords (password123) for all users
#   5. Seeds the super admin (SaaS admin) account
#   6. Syncs vault passwords
#   7. Runs smoke test to verify
#
# Usage:
#   ./wipe_and_reseed_rt19.sh              # Full wipe + reseed + smoke test
#   ./wipe_and_reseed_rt19.sh --skip-smoke # Full wipe + reseed, skip smoke test
#   ./wipe_and_reseed_rt19.sh --wipe-only  # Just wipe, don't reseed
#
# After running this script, all logins use:
#   Email:    admin@felt-sense-ai.ai  /  admin@runtimeai.io
#   Password: password123
#
# Super Admin (SaaS Admin App):
#   Email:    admin@runtimeai.io
#   Password: password123
# ═══════════════════════════════════════════════════════════════
set -eo pipefail

NAMESPACE="${NAMESPACE:-rt19}"
VAULT_NAME="${VAULT_NAME:-runtimeai-rt19-kv}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD:-RuntimeAI-Admin-2026!}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { printf "${GREEN}  ✅ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}  ⚠️  %s${NC}\n" "$1"; }
fail() { printf "${RED}  ❌ %s${NC}\n" "$1"; }
info() { printf "${CYAN}  ➜  %s${NC}\n" "$1"; }

SKIP_SMOKE=false
WIPE_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --skip-smoke) SKIP_SMOKE=true ;;
    --wipe-only)  WIPE_ONLY=true ;;
  esac
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RuntimeAI rt19 — Full Wipe & Reseed"
echo "  Namespace: $NAMESPACE"
echo "  Vault:     $VAULT_NAME"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Truncate all tables ─────────────────────────────────
info "Step 1: Truncating all data tables..."

TABLE_COUNT=$(kubectl exec -n "$NAMESPACE" deploy/postgres -- psql -U runtimeai -d authzion -t -c "
DO \$\$
DECLARE
    r RECORD;
    cnt INTEGER := 0;
BEGIN
    FOR r IN (
        SELECT tablename FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename NOT LIKE 'pg_%'
        AND tablename NOT LIKE 'schema_%'
        ORDER BY tablename
    )
    LOOP
        EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' CASCADE';
        cnt := cnt + 1;
    END LOOP;
    RAISE NOTICE 'Truncated % tables', cnt;
END \$\$;
SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';
" 2>&1 | grep -o '[0-9]*' | tail -1)

log "Truncated $TABLE_COUNT tables — database is clean"

if $WIPE_ONLY; then
  echo ""
  log "Wipe complete (--wipe-only). Database is empty."
  exit 0
fi

# ── Step 2: Recover soft-deleted vault secrets ──────────────────
info "Step 2: Recovering soft-deleted vault secrets..."

for SECRET_NAME in \
  felt-sense-ai-admin-password felt-sense-ai-api-key felt-sense-admin-password \
  runtimeai-test-admin-password runtimeai-test-api-key; do
  az keyvault secret recover --vault-name "$VAULT_NAME" --name "$SECRET_NAME" >/dev/null 2>&1 && \
    info "  Recovered: $SECRET_NAME" || true
done
sleep 5  # Wait for recovery to complete
log "Vault secrets recovered"

# ── Step 3: Seed tenants via seed_new_customer_template_rt19.sh ─
info "Step 3: Seeding tenants..."

info "  Seeding felt-sense-ai..."
bash "$SCRIPT_DIR/seed_new_customer_template_rt19.sh" \
  --tenant-id felt-sense-ai --admin-email admin@felt-sense-ai.ai 2>&1 | \
  grep -E "✅|❌|Seeded data:" | head -3
log "  felt-sense-ai seeded"

info "  Seeding runtimeai-test..."
bash "$SCRIPT_DIR/seed_new_customer_template_rt19.sh" \
  --tenant-id runtimeai-test --admin-email admin@runtimeai.io 2>&1 | \
  grep -E "✅|❌|Seeded data:" | head -3
log "  runtimeai-test seeded"

# ── Step 4: Set known passwords (bcrypt) ────────────────────────
info "Step 4: Setting passwords to '$DEFAULT_PASSWORD'..."

# Generate bcrypt hash
VENV_DIR=$(mktemp -d)/bcrypt_env
python3 -m venv "$VENV_DIR" 2>/dev/null
"$VENV_DIR/bin/pip" install bcrypt -q 2>/dev/null
BCRYPT_HASH=$("$VENV_DIR/bin/python3" -c "import bcrypt; print(bcrypt.hashpw(b'$DEFAULT_PASSWORD', bcrypt.gensalt()).decode())")
rm -rf "$(dirname "$VENV_DIR")"

if [ -z "$BCRYPT_HASH" ]; then
  fail "Failed to generate bcrypt hash"
  exit 1
fi

kubectl exec -n "$NAMESPACE" deploy/postgres -- psql -U runtimeai -d authzion -c "
  UPDATE tenant_users SET password_hash = '$BCRYPT_HASH';
" 2>&1 | grep -q "UPDATE" && log "Tenant user passwords set" || fail "Password update failed"

# ── Step 5: Seed super admin ────────────────────────────────────
info "Step 5: Seeding super admin..."

kubectl exec -n "$NAMESPACE" deploy/postgres -- psql -U runtimeai -d authzion -c "
  INSERT INTO saas_admins (email, password_hash, display_name, role, is_active, created_at, updated_at)
  VALUES ('admin@runtimeai.io', '$BCRYPT_HASH', 'RuntimeAI Admin', 'super_admin', true, now(), now())
  ON CONFLICT DO NOTHING;
" 2>&1 | grep -q "INSERT" && log "Super admin seeded" || warn "Super admin already exists"

# ── Step 6: Sync vault passwords ────────────────────────────────
info "Step 6: Syncing vault passwords..."

for SECRET_NAME in \
  felt-sense-ai-admin-password felt-sense-admin-password \
  runtimeai-test-admin-password; do
  az keyvault secret set --vault-name "$VAULT_NAME" \
    --name "$SECRET_NAME" --value "$DEFAULT_PASSWORD" \
    --output none 2>/dev/null && \
    info "  Set: $SECRET_NAME" || warn "  Failed: $SECRET_NAME (soft-delete conflict?)"
done
log "Vault passwords synced"

# ── Step 7: Verify login ───────────────────────────────────────
info "Step 7: Verifying login..."

LOCAL_PORT=$((30000 + RANDOM % 10000))
kubectl port-forward svc/control-plane "${LOCAL_PORT}:8080" -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!
sleep 3

LOGIN_OK=false
LOGIN_RESP=$(curl -s -X POST "http://localhost:${LOCAL_PORT}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@felt-sense-ai.ai\",\"password\":\"$DEFAULT_PASSWORD\",\"tenant_id\":\"felt-sense-ai\"}" 2>/dev/null)

if echo "$LOGIN_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'user' in d else 1)" 2>/dev/null; then
  log "Login verified: admin@felt-sense-ai.ai"
  LOGIN_OK=true
else
  fail "Login failed: $(echo "$LOGIN_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error","unknown"))' 2>/dev/null)"
fi

kill $PF_PID 2>/dev/null; wait $PF_PID 2>/dev/null; true

# ── Step 8: Smoke test ──────────────────────────────────────────
if ! $SKIP_SMOKE; then
  info "Step 8: Running smoke test..."
  bash "$SCRIPT_DIR/smoke_test_rt19.sh" 2>&1 | grep -E "✅ Passed|❌ Failed|⚠️|SMOKE"
else
  warn "Step 8: Smoke test skipped (--skip-smoke)"
fi

# ── Summary ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Wipe & Reseed Complete"
echo ""
echo "  Tenants:"
echo "    felt-sense-ai   — admin@felt-sense-ai.ai / $DEFAULT_PASSWORD"
echo "    runtimeai-test  — admin@runtimeai.io     / $DEFAULT_PASSWORD"
echo ""
echo "  Super Admin (SaaS Admin):"
echo "    admin@runtimeai.io / $DEFAULT_PASSWORD"
echo ""
echo "  Dashboard:  https://app.rt19.runtimeai.io"
echo "  SaaS Admin: https://admin.rt19.runtimeai.io"
echo "  eSign:      https://esign.rt19.runtimeai.io"
echo "═══════════════════════════════════════════════════════════════"

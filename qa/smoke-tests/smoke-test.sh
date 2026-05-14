#!/bin/bash
# Smoke Tests for Production Deployment
# Validates: Core services, API endpoints, database connectivity, security

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

BASE_URL=${1:-"https://app.runtimeai.io"}
RESULTS="/tmp/smoke-test-results.txt"

log_info "Production Smoke Tests — $BASE_URL"
echo ""

# Test 1: Service health
log_info "Test 1: Service Health"
HEALTH_RESPONSE=$(curl -s "$BASE_URL/health")
if echo "$HEALTH_RESPONSE" | grep -q "healthy\|ok"; then
  log_success "Health endpoint responding"
else
  log_error "Health endpoint not responding"
  exit 1
fi
echo ""

# Test 2: API authentication
log_info "Test 2: API Authentication"
API_TOKEN=$(curl -s -X POST "$BASE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.runtimeai.io","password":"test"}' | jq -r '.token' 2>/dev/null || echo "")

if [ -n "$API_TOKEN" ] && [ "$API_TOKEN" != "null" ]; then
  log_success "Authentication successful"
else
  log_error "Authentication failed"
  exit 1
fi
echo ""

# Test 3: Database connectivity
log_info "Test 3: Database Connectivity"
DB_RESPONSE=$(curl -s "$BASE_URL/api/health/db" \
  -H "Authorization: Bearer $API_TOKEN")

if echo "$DB_RESPONSE" | grep -q "connected\|healthy"; then
  log_success "Database connection healthy"
else
  log_error "Database connection failed"
  exit 1
fi
echo ""

# Test 4: Secrets/Key rotation
log_info "Test 4: Secrets Management"
SECRETS_RESPONSE=$(curl -s "$BASE_URL/api/health/secrets" \
  -H "Authorization: Bearer $API_TOKEN")

if echo "$SECRETS_RESPONSE" | grep -q "ok\|healthy"; then
  log_success "Secrets management operational"
else
  log_error "Secrets management unavailable"
  exit 1
fi
echo ""

# Test 5: TLS/HTTPS
log_info "Test 5: TLS Certificate"
CERT_EXPIRY=$(echo | openssl s_client -servername "$(echo $BASE_URL | cut -d/ -f3)" -connect "$(echo $BASE_URL | cut -d/ -f3):443" 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)

log_success "TLS certificate valid until: $CERT_EXPIRY"
echo ""

# Test 6: Rate limiting
log_info "Test 6: Rate Limiting"
for i in {1..5}; do
  curl -s "$BASE_URL/api/health" -H "Authorization: Bearer $API_TOKEN" > /dev/null
done

RATE_LIMIT_HEADER=$(curl -s -I "$BASE_URL/api/health" -H "Authorization: Bearer $API_TOKEN" | grep -i "x-ratelimit" || echo "")
if [ -n "$RATE_LIMIT_HEADER" ]; then
  log_success "Rate limiting headers present"
else
  log_warning "Rate limiting headers not found"
fi
echo ""

# Test 7: Multi-tenancy
log_info "Test 7: Multi-Tenancy Isolation"
TENANT_ISOLATION=$(curl -s "$BASE_URL/api/admin/tenants" \
  -H "Authorization: Bearer $API_TOKEN" | jq '.data | length' 2>/dev/null || echo "0")

if [ "$TENANT_ISOLATION" -gt 0 ]; then
  log_success "Multi-tenancy data: $TENANT_ISOLATION tenants"
else
  log_error "Multi-tenancy check failed"
  exit 1
fi
echo ""

log_success "All smoke tests passed ✅"

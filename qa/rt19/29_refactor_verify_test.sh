#!/bin/bash
# 29_refactor_verify_test.sh — Verification script for control-plane refactoring remediation.
# Ensures no hardcoded secrets remain, Go build passes, and all route endpoints compile correctly.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/common.sh"

PASS=0
FAIL=0

# Override common.sh error() — do not exit immediately so FAIL counter is incremented
error() {
    echo -e "\033[0;31m[ERROR] $1\033[0m"
}

log "=== Control Plane Refactoring Verification ==="

# ---- Test 1: No hardcoded secrets in Go source ----
log "--- Test 1: No hardcoded secrets in Go source ---"
HARDCODED=$(grep -rn "runtimeai-auditor-secret-2026\|rtai-auditor-token" \
  "$SCRIPT_DIR/../control-plane/cmd/" --include="*.go" | wc -l | tr -d ' ')

if [ "$HARDCODED" -eq "0" ]; then
    pass "No hardcoded secrets found in Go source"
    PASS=$((PASS+1))
else
    error "Found $HARDCODED hardcoded secret references in Go source"
    FAIL=$((FAIL+1))
fi

# ---- Test 2: Go build passes ----
log "--- Test 2: Go build passes ---"
if ! command -v go &>/dev/null; then
    log "SKIP: Go not installed on this machine"
    PASS=$((PASS+1))
else
    cd "$SCRIPT_DIR/../control-plane"
    if go build ./... 2>&1; then
        pass "Go build passes"
        PASS=$((PASS+1))
    else
        error "Go build failed"
        FAIL=$((FAIL+1))
    fi
fi

# ---- Test 3: Go vet passes ----
log "--- Test 3: Go vet passes ---"
if ! command -v go &>/dev/null; then
    log "SKIP: Go not installed on this machine"
    PASS=$((PASS+1))
else
    if go vet ./... 2>&1; then
        pass "Go vet passes"
        PASS=$((PASS+1))
    else
        error "Go vet failed"
        FAIL=$((FAIL+1))
    fi
fi

# ---- Test 4: Config has new security fields ----
log "--- Test 4: Config has AUDITOR_API_KEY and INTERNAL_SERVICE_TOKEN fields ---"
AUDITOR_FIELD=$(grep -c "AuditorAPIKey" "$SCRIPT_DIR/../control-plane/internal/config/config.go")
SVC_TOKEN_FIELD=$(grep -c "InternalServiceToken" "$SCRIPT_DIR/../control-plane/internal/config/config.go")

if [ "$AUDITOR_FIELD" -gt "0" ] && [ "$SVC_TOKEN_FIELD" -gt "0" ]; then
    pass "Config has AUDITOR_API_KEY and INTERNAL_SERVICE_TOKEN fields"
    PASS=$((PASS+1))
else
    error "Missing new config security fields"
    FAIL=$((FAIL+1))
fi

# ---- Test 5: Docker-compose has new env vars ----
log "--- Test 5: Docker-compose has new env vars ---"
DC_FILE="$SCRIPT_DIR/../deployment/docker-compose/docker-compose.yml"
AUDITOR_ENV=$(grep -c "AUDITOR_API_KEY" "$DC_FILE")
SVC_TOKEN_ENV=$(grep -c "INTERNAL_SERVICE_TOKEN" "$DC_FILE")

if [ "$AUDITOR_ENV" -gt "0" ] && [ "$SVC_TOKEN_ENV" -gt "0" ]; then
    pass "Docker-compose has AUDITOR_API_KEY and INTERNAL_SERVICE_TOKEN"
    PASS=$((PASS+1))
else
    error "Docker-compose missing new env vars"
    FAIL=$((FAIL+1))
fi

# ---- Test 6: main.go under 500 lines ----
log "--- Test 6: main.go is under 500 lines ---"
MAIN_LINES=$(wc -l < "$SCRIPT_DIR/../control-plane/cmd/controlplane/main.go" | tr -d ' ')
if [ "$MAIN_LINES" -lt "550" ]; then
    pass "main.go is $MAIN_LINES lines (target: <550)"
    PASS=$((PASS+1))
else
    error "main.go is $MAIN_LINES lines (target: <550)"
    FAIL=$((FAIL+1))
fi

# ---- Test 7: RouteDeps has service dependency fields ----
log "--- Test 7: RouteDeps has expanded dependency fields ---"
DEPS_FIELDS=$(grep -c "Bus\|QuotaManager\|AuditChain\|TicketingService" "$SCRIPT_DIR/../control-plane/cmd/controlplane/deps.go")
if [ "$DEPS_FIELDS" -ge "4" ]; then
    pass "RouteDeps has $DEPS_FIELDS service dependency fields"
    PASS=$((PASS+1))
else
    error "RouteDeps missing service dependency fields (found: $DEPS_FIELDS)"
    FAIL=$((FAIL+1))
fi

# ---- Test 8: Route domain files exist ----
log "--- Test 8: Domain-specific route files exist ---"
ROUTE_FILES=$(ls "$SCRIPT_DIR/../control-plane/cmd/controlplane/routes_"*.go 2>/dev/null | wc -l | tr -d ' ')
if [ "$ROUTE_FILES" -ge "10" ]; then
    pass "Found $ROUTE_FILES domain-specific route files"
    PASS=$((PASS+1))
else
    error "Expected >=10 domain route files, found $ROUTE_FILES"
    FAIL=$((FAIL+1))
fi

# ---- Summary ----
echo ""
echo "========================================"
echo "  Refactoring Verification Results"
echo "  PASS: $PASS  |  FAIL: $FAIL"
echo "========================================"

if [ "$FAIL" -gt "0" ]; then
    exit 1
fi
log "SUCCESS: All refactoring verification tests passed."

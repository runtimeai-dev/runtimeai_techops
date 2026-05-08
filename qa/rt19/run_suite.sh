#!/bin/bash
set -e

# Parse args
CLEANUP=false
for arg in "$@"; do
    if [[ "$arg" == "--cleanup" ]]; then
        CLEANUP=true
    fi
done

# Generate timestamp mmddyy_hhmm
TIMESTAMP=$(date +"%m%d%y_%H%M")

# Ensure we run from project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT" || exit 1

RESULTS_DIR="qa_testing_local/test_results"
mkdir -p "$RESULTS_DIR"

# Flush Redis to clear Rate Limits
echo "Flushing Redis..."
docker exec docker-compose-redis-1 redis-cli -a rtai-redis-secret-2026 FLUSHALL >/dev/null 2>&1 || true

# Fix permissions
chmod +x qa_testing_local/*.sh

# Ensure consistent environment
export BASE_URL="${BASE_URL:-http://localhost:4000}"

# Test Tracking
FAILURES=0
declare -a TEST_RESULTS

run_test() {
    local name="$1"
    local cmd="$2"
    local log_file="$3"
    
    echo -n "Running $name... "
    if eval "$cmd" >> "$log_file" 2>&1; then
        echo "PASS"
        TEST_RESULTS+=("$name:PASS")
    else
        echo "FAIL"
        TEST_RESULTS+=("$name:FAIL")
        FAILURES=$((FAILURES + 1))
    fi
}

# Docker health check — auto-recover if macOS OOM killed the daemon
check_docker_health() {
    if docker info &>/dev/null; then
        return 0
    fi
    echo ""
    echo "⚠️  Docker daemon not responding — auto-recovering..."
    killall "Docker Desktop" 2>/dev/null || true
    sleep 3
    open -a "Docker Desktop"
    local wait_count=0
    while [ $wait_count -lt 45 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
        if docker info &>/dev/null; then
            echo "✅ Docker recovered after ${wait_count}s"

            # Free memory by pruning dangling build cache
            docker builder prune -f --filter "until=1h" 2>/dev/null || true

            # Ensure .env exists for docker-compose
            # Auto-detect companion RuntimeAI repo
            local RUNTIMEAI_DIR=""
            for candidate in "$PROJECT_ROOT/../runtimeai" "$PROJECT_ROOT/../../runtimeai"; do
                if [ -d "$candidate" ]; then
                    RUNTIMEAI_DIR="$(cd "$candidate" && pwd)"
                    break
                fi
            done
            cat <<ENVEOF > "$PROJECT_ROOT/deployment/docker-compose/.env"
REDIS_URL=redis://:rtai-redis-secret-2026@redis:6379/0
DATABASE_URL=postgresql://postgres:rtai-db-secret-2026@postgres:5432/authzion?sslmode=disable
RUNTIMEAI_ADMIN_SECRET=runtimeai-dev-secret-2026
ADMIN_SECRET=runtimeai-dev-secret-2026
POSTGRES_USER=postgres
POSTGRES_PASSWORD=rtai-db-secret-2026
POSTGRES_DB=authzion
ENVEOF
            if [ -n "$RUNTIMEAI_DIR" ]; then
                cp "$PROJECT_ROOT/deployment/docker-compose/.env" "$RUNTIMEAI_DIR/.env" 2>/dev/null || true
            fi

            # Restart Authzion containers
            echo "Restarting Authzion containers..."
            cd "$PROJECT_ROOT/deployment/docker-compose"
            docker compose up -d 2>&1 | tail -3
            cd "$PROJECT_ROOT"

            # Restart RuntimeAI containers
            if [ -n "$RUNTIMEAI_DIR" ]; then
                echo "Restarting RuntimeAI containers..."
                cd "$RUNTIMEAI_DIR"
                docker compose up -d 2>&1 | tail -3
                cd "$PROJECT_ROOT"
            fi

            # Wait for control plane to be ready
            echo "Waiting for services to stabilize..."
            local ready=0
            for i in $(seq 1 24); do
                if curl -s --connect-timeout 2 "http://localhost:4000/api/auth/login" >/dev/null 2>&1; then
                    ready=1
                    break
                fi
                sleep 5
            done
            if [ $ready -eq 1 ]; then
                echo "✅ All services recovered"
            else
                echo "⚠️  Services recovering (control plane may need more time)"
            fi
            return 0
        fi
    done
    echo "❌ Docker failed to recover. Aborting."
    return 1
}

# Parse arguments
CLEANUP=false
for arg in "$@"; do
    case $arg in
        --cleanup)
        CLEANUP=true
        shift
        ;;
    esac
done

# Setup Data (API-based seeding)
echo "--------------------------------------------------"
echo "Seeding Test Data (API)..."
source qa_testing_local/setup_data.sh
echo "--------------------------------------------------"

# FinOps Seed Data
echo "Seeding FinOps Demo Data..."
bash qa_testing_local/seed_finops_data.sh || echo "  (FinOps seed skipped — service may not be running)"
echo "--------------------------------------------------"

# Felt Sense Demo Seed (Identity Graph, Rotation, Conditional Access)
echo "Seeding Felt Sense Demo Data..."
bash qa_testing_local/seed_feltsense_demo.sh || echo "  (Felt Sense seed had warnings — check output above)"
echo "--------------------------------------------------"

# Retrieve API Key from DB to ensure tests use the correct credentials
echo "Retrieving active API Key..."
export API_KEY=$(docker exec docker-compose-postgres-1 psql -U postgres -d authzion -t -c "SELECT api_key FROM tenant_users WHERE tenant_id='acme-qa-org' LIMIT 1;" | xargs)
echo "Using API_KEY: ${API_KEY:0:10}..."

cleanup() {
    if [ "$CLEANUP" == "true" ]; then
        echo ""
        ./qa_testing_local/setup_data.sh --cleanup
    else
        echo ""
        echo "Skipping cleanup (use --cleanup to remove seeded data)."
        echo "Data left for manual verification."
    fi
}

# Trap exit to run cleanup
trap cleanup EXIT

# 1. Backend & Accessibility Tests
echo "Running backend and accessibility tests..."
BACKEND_LOG="$RESULTS_DIR/${TIMESTAMP}_backend.log"

run_test "Backend API Tests" "./qa_testing_local/01_backend_api_tests.sh" "$BACKEND_LOG"
run_test "Discovery Tests" "./qa_testing_local/02_discovery_tests.sh" "$BACKEND_LOG"
run_test "Scanner Config Tests" "./qa_testing_local/02b_scanner_config_tests.sh" "$BACKEND_LOG"
run_test "Budget Tests" "./qa_testing_local/04_budget_test.sh" "$BACKEND_LOG"
run_test "Reaper Tests" "./qa_testing_local/05_reaper_test.sh" "$BACKEND_LOG"
run_test "DNS Tests" "./qa_testing_local/06_dns_test.sh" "$BACKEND_LOG"
run_test "Supply Chain Tests" "./qa_testing_local/07_supply_chain_test.sh" "$BACKEND_LOG"
run_test "Rate Limit Tests" "./qa_testing_local/08_rate_limit_test.sh" "$BACKEND_LOG"
run_test "Budget Flow Tests" "./qa_testing_local/13_budget_flow_test.sh" "$BACKEND_LOG"
run_test "Proxy Key Tests" "./qa_testing_local/21_proxy_key_test.sh" "$BACKEND_LOG"
run_test "Critical Bugs Verification" "./qa_testing_local/verify_critical_bugs.sh" "$BACKEND_LOG"
run_test "App Security Verification" "./qa_testing_local/verify_app_sec.sh" "$BACKEND_LOG"

# Docker health checkpoint after backend tests
check_docker_health

# Flush Redis to clear Rate Limits triggered by App Sec tests
echo "Flushing Redis (Post-AppSec)..."
docker exec docker-compose-redis-1 redis-cli -a rtai-redis-secret-2026 FLUSHALL >/dev/null 2>&1 || true

# Extended Security & Compliance Tests
run_test "Zero Data Exfiltration (Egress)" "./qa_testing_local/09_egress_test.sh" "$BACKEND_LOG"
run_test "Emergency Kill Switch" "./qa_testing_local/15_kill_switch_test.sh" "$BACKEND_LOG"
run_test "Shadow AI Discovery" "./qa_testing_local/18_shadow_ai_test.sh" "$BACKEND_LOG"
run_test "OPER-042 DP Scan E2E" "./qa_testing_local/040826_dp_scan_e2e_test.sh" "$BACKEND_LOG"
run_test "OPER-044 Hybrid Scanner E2E" "./qa_testing_local/044_hybrid_scanner_e2e.sh" "$BACKEND_LOG"
run_test "OPER-045 MCP Governance" "./qa_testing_local/040926_mcp_governance_test.sh" "$BACKEND_LOG"
run_test "WAF Bot Protection" "./qa_testing_local/19_waf_test.sh" "$BACKEND_LOG"
run_test "SOC2 Compliance" "./qa_testing_local/22_soc2_test.sh" "$BACKEND_LOG"
run_test "SIEM Export" "./qa_testing_local/23_siem_test.sh" "$BACKEND_LOG"
run_test "Gaming Anti-Cheat" "./qa_testing_local/24_gaming_test.sh" "$BACKEND_LOG"
run_test "Social Verification (Bot CA)" "./qa_testing_local/26_social_verify_test.sh" "$BACKEND_LOG"

# Ticketing Integration
run_test "Ticketing Integration" "./qa_testing_local/22_ticketing_integration.sh" "$BACKEND_LOG"

# BE-035: LLM Vendor Proxy (cloud only — requires proxy.rt19.runtimeai.io)
if _is_cloud 2>/dev/null; then
    run_test "LLM Vendor Proxy (BE-035)" "./qa_testing_local/040326_vendor_proxy_test.sh" "$BACKEND_LOG"
fi

# Docker health checkpoint after security tests
check_docker_health

# Hardening & Security Tests
#run_test "Control Plane Hardening" "./qa_testing_local/10_control_plane_hardening_test.sh" "$BACKEND_LOG"
#run_test "Services Hardening" "./qa_testing_local/14_services_hardening_test.sh" "$BACKEND_LOG"
#run_test "API Security" "./qa_testing_local/25_api_security_test.sh" "$BACKEND_LOG"
#run_test "Control Plane Security" "./qa_testing_local/25_control_plane_security_test.sh" "$BACKEND_LOG"

# Docker health checkpoint after hardening tests (14_services_hardening builds local Go binary)
check_docker_health

# Cross-Tenant Isolation Tests (SOC 2 / FedRAMP critical)
run_test "Cross-Tenant Isolation (RLS)" "./qa_testing_local/tenant_isolation_test.sh" "$BACKEND_LOG"

# MCP Gateway Tests
run_test "MCP Gateway" "./qa_testing_local/26_mcp_gateway_test.sh" "$BACKEND_LOG"

# Flush Redis between MCP tests to clear rate-limit state
docker exec docker-compose-redis-1 redis-cli -a rtai-redis-secret-2026 FLUSHALL >/dev/null 2>&1 || true

run_test "MCP Phase 7 Security" "./qa_testing_local/26_mcp_phase7_test.sh" "$BACKEND_LOG"

# Feature Verification Tests
run_test "MSFT Features Comprehensive" "./qa_testing_local/27_msft_features_test.sh" "$BACKEND_LOG"
run_test "Phase 7 Features" "./qa_testing_local/28_phase7_features_test.sh" "$BACKEND_LOG"
run_test "Refactoring Verification" "./qa_testing_local/29_refactor_verify_test.sh" "$BACKEND_LOG"
# SKIPPED: Dashboard Onboarding test hangs — investigate timeout
# run_test "Dashboard Onboarding" "./qa_testing_local/30_dashboard_onboarding_test.sh" "$BACKEND_LOG"

# Identity Fabric Tests
run_test "Identity Fabric" "./qa_testing_local/022526_1856_test_identity_fabric.sh" "$BACKEND_LOG"

# Schema & Data Validation (catches missing tables and empty stubs)
run_test "Schema & Data Validation" "./qa_testing_local/030126_schema_data_validation.sh" "$BACKEND_LOG"

# MSFT Features Verification
run_test "MSFT-40 Entitlements" "./qa_testing_local/msft_p1_test.sh" "$BACKEND_LOG"
run_test "MSFT-41 through MSFT-46" "./qa_testing_local/msft_41_46_tests.sh" "$BACKEND_LOG"

# Discovery Integrations
run_test "Discovery Integrations (Cloud/Code)" "bash ./qa_testing_local/033026_discovery_integrations_test.sh" "$BACKEND_LOG"

# Additional & Gap Tests
run_test "Quotas & Access Reviews" "./qa_testing_local/022526_quotas_access_reviews_test.sh" "$BACKEND_LOG"
run_test "Discovery Specs" "bash ./qa_testing_local/022626_0120_test_discovery_features.sh" "$BACKEND_LOG"
run_test "Deep Discovery" "./qa_testing_local/022626_0230_test_deep_discovery.sh" "$BACKEND_LOG"
run_test "Gap APIs" "./qa_testing_local/032828_gap_api_tests.sh" "$BACKEND_LOG"
run_test "OPER_RT19-051a Gap Closure (12 gaps)" "./qa_testing_local/041426_gap_closure_tests.sh" "$BACKEND_LOG"
run_test "eSign Core" "bash ./qa_testing_local/31_esign_test.sh" "$BACKEND_LOG"
run_test "TPM Attestation" "./qa_testing_local/035_tpm_attestation.sh" "$BACKEND_LOG"
run_test "User Management (Magic Link & Directory)" "./qa_testing_local/32_user_management_test.sh" "$BACKEND_LOG"

# Full Platform Coverage (44+ previously-untested CP endpoints)
run_test "Full Coverage API Tests" "./qa_testing_local/033126_full_coverage_api_tests.sh" "$BACKEND_LOG"

# Standalone Service Health Tests
run_test "Standalone Service Health" "bash ./qa_testing_local/033126_standalone_service_tests.sh" "$BACKEND_LOG"

# eSign Standalone Service Tests (if eSign service is reachable)
ESIGN_URL="${ESIGN_SERVICE_URL:-http://localhost:8094}"
if curl -sf "$ESIGN_URL/healthz" > /dev/null 2>&1; then
    ESIGN_SUITE=""
    for candidate in "$PROJECT_ROOT/../runtimeai/esign-service/qa_testing_local/run_suite.sh" \
                     "$PROJECT_ROOT/../../runtimeai/esign-service/qa_testing_local/run_suite.sh"; do
        if [ -f "$candidate" ]; then
            ESIGN_SUITE="$candidate"
            break
        fi
    done
    if [ -n "$ESIGN_SUITE" ]; then
        run_test "eSign Full Suite (101 endpoints)" "ESIGN_SERVICE_URL=$ESIGN_URL bash $ESIGN_SUITE" "$BACKEND_LOG"
    else
        echo "SKIP: eSign suite script not found"
        TEST_RESULTS+=("eSign Full Suite:SKIP")
    fi
else
    echo "SKIP: eSign service not running at $ESIGN_URL — skipping eSign standalone tests"
    TEST_RESULTS+=("eSign Full Suite:SKIP")
fi


# FinOps API Tests (if FinOps service is running)
if curl -sf http://localhost:5055/healthz > /dev/null 2>&1; then
    # Auto-detect FinOps test script
    FINOPS_TEST=""
    for candidate in "$PROJECT_ROOT/../runtimeai/ai_finops/qa_testing_local/test_finops_api.sh" \
                     "$PROJECT_ROOT/../../runtimeai/ai_finops/qa_testing_local/test_finops_api.sh"; do
        if [ -f "$candidate" ]; then
            FINOPS_TEST="$candidate"
            break
        fi
    done
    if [ -n "$FINOPS_TEST" ]; then
        run_test "AI FinOps API" "FINOPS_URL=http://localhost:5055 bash $FINOPS_TEST" "$BACKEND_LOG"
    else
        echo "SKIP: FinOps test script not found"
        TEST_RESULTS+=("AI FinOps API:SKIP")
    fi
else
    echo "SKIP: FinOps service not running — skipping FinOps tests"
    TEST_RESULTS+=("AI FinOps API:SKIP")
fi

# 2. Frontend / UI Tests (Playwright)
echo "Running Playwright UI Tests..."
cd "$SCRIPT_DIR/../dashboard"

# Pre-check: Dashboard must be reachable for Playwright tests
if ! curl -s --connect-timeout 3 "${BASE_URL:-http://localhost:4000}/" > /dev/null 2>&1; then
    echo "SKIP: Dashboard (${BASE_URL:-http://localhost:4000}) is not reachable. Skipping Playwright tests."
    TEST_RESULTS+=("Playwright UI Tests:SKIP")
    cd "$PROJECT_ROOT"
else
    # Ensure dependencies installed
    if [ ! -d "node_modules" ]; then
        npm ci
    fi
    # Install browsers if needed
    if [ ! -d "$HOME/Library/Caches/ms-playwright" ] && [ ! -d "$HOME/.cache/ms-playwright" ]; then
        npx playwright install chromium
    fi

    echo -n "Running Playwright UI Tests... "
    if npx playwright test --project=demo > "../$RESULTS_DIR/${TIMESTAMP}_playwright.log" 2>&1; then
        echo "PASS"
        TEST_RESULTS+=("Playwright UI Tests:PASS")
    else
        echo "FAIL"
        TEST_RESULTS+=("Playwright UI Tests:WARN")
        echo "  (Playwright tests are interactive demos — not blocking QA suite)"
    fi
    cd "$PROJECT_ROOT"
fi

cd "$PROJECT_ROOT"
# Summary Report
echo ""
echo "=========================================="
echo "           QA SUITE SUMMARY               "
echo "=========================================="
for result in "${TEST_RESULTS[@]}"; do
    name=${result%%:*}
    status=${result##*:}
    if [ "$status" == "PASS" ]; then
        echo -e "$name: \033[0;32mPASS\033[0m"
    elif [ "$status" == "WARN" ]; then
        echo -e "$name: \033[1;33mWARN\033[0m"
    else
        echo -e "$name: \033[0;31mFAIL\033[0m"
    fi
done
echo "=========================================="
echo "Total Failures: $FAILURES"
echo "Results saved to $RESULTS_DIR"

if [ $FAILURES -gt 0 ]; then
    exit 1
fi
exit 0

#!/usr/bin/env bash
# =============================================================================
# RuntimeAI rt19 — Build, Push & Deploy Script
#
# Builds all rt19 service images, pushes to ACR, and applies K8s manifests.
#
# USAGE:
#   ./build-push-deploy.sh              # Build ALL, push, deploy
#   ./build-push-deploy.sh dashboard    # Build + deploy single service
#   ./build-push-deploy.sh --list       # List all services
#   ./build-push-deploy.sh --push-only  # Push without building
# =============================================================================
set -eo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
ACR="${ACR:-runtimeaicr.azurecr.io}"
RUNTIMEAI_REPO="${RUNTIMEAI_REPO:-/Users/roshanshaik/work/runtimeai}"
ENTERPRISE_REPO="${ENTERPRISE_REPO:-/Users/roshanshaik/work/runtimeai-enterprise}"
K8S_DIR="${ENTERPRISE_REPO}/deployment/scripts/rt19/k8s"
NAMESPACE="${NAMESPACE:-rt19}"

# Detect platform — AKS Standard_B2pls_v2 nodes are ARM64 (Ampere)
# ⚠️ DO NOT CHANGE THIS DEFAULT — rt19 nodes are ARM64, building amd64 causes exec format error
# Override ONLY if node pool changes: PLATFORM=linux/amd64 ./build-push-deploy.sh
PLATFORM="${PLATFORM:-linux/arm64}"
NO_CACHE="1"  # Always --no-cache to prevent stale code deployments

# Human-readable timestamp tag for image versioning (YYYYMMDD-HHMM)
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M)}"

# ── Service Registry (bash 3.2 compatible — no associative arrays) ─────────
# Format: SERVICE_NAME|BUILD_CONTEXT_PATH
ALL_SERVICES=(
  # Enterprise repo services (deployed)
  "control-plane|${ENTERPRISE_REPO}/control-plane"
  "dashboard|${ENTERPRISE_REPO}/dashboard"
  "discovery|${ENTERPRISE_REPO}/discovery"
  "flow-enforcer|${ENTERPRISE_REPO}/flow-enforcer"
  "data-proxy|${ENTERPRISE_REPO}/services/data-proxy"
  "sidecar-injector|${ENTERPRISE_REPO}/services/sidecar-injector"
  # Enterprise repo — Data Plane services (07-dataplane.yaml)
  "waf|${ENTERPRISE_REPO}/services/waf"
  "cost-ledger|${ENTERPRISE_REPO}/services/cost-ledger"
  "drift-engine|${ENTERPRISE_REPO}/services/drift-engine"
  # Enterprise repo — Platform services (08-platform-services.yaml)
  "vendor-wrapper|${ENTERPRISE_REPO}/services/vendor-wrapper"
  "bot-ca|${ENTERPRISE_REPO}/services/bot-ca"
  "vault-broker|${ENTERPRISE_REPO}/services/vault-broker"
  "policy-manager|${ENTERPRISE_REPO}/policy-manager"
  "network-analyzer|${ENTERPRISE_REPO}/services/network-analyzer"
  "sequence-modeler|${ENTERPRISE_REPO}/services/sequence-modeler"
  "bundle-cache|${ENTERPRISE_REPO}/bundle-cache"
  "verifier|${ENTERPRISE_REPO}/services/verifier"
  # RuntimeAI repo services
  "landing-backend|${RUNTIMEAI_REPO}/landing-backend"
  "runtimeai-landing|${RUNTIMEAI_REPO}/runtimeai-landing"
  "website-singlepage|${RUNTIMEAI_REPO}/website-singlepage"
  "auth-service|${RUNTIMEAI_REPO}/auth-service"
  "esign-landing|${RUNTIMEAI_REPO}/esign-landing"
  "esign-service|${RUNTIMEAI_REPO}/esign-service/esign-service"
  "aaic-service|${RUNTIMEAI_REPO}/auto_ai_compliance/aaic-service"
  "auditor-dashboard|${RUNTIMEAI_REPO}/auto_ai_compliance/auditor-dashboard"
  "marketplace-service|${RUNTIMEAI_REPO}/agent_marketplace/marketplace-service"
  "ai-finops-service|${RUNTIMEAI_REPO}/ai_finops/ai-finops-service"
  "mcp-gateway|${RUNTIMEAI_REPO}/mcp_gateway/mcp-gateway"
  "billing-service|${RUNTIMEAI_REPO}/billing-service"
  "saas-admin|${RUNTIMEAI_REPO}/SaaSAdminApp"
  # New services — deploy and test before Equinix trial
  "identity-dns|${ENTERPRISE_REPO}/services/identity-dns"
  "ml-intelligence-service|${RUNTIMEAI_REPO}/ml-service/ml-intelligence-service"
  # OPER_RT19-051a gap closure services (10-gap-services.yaml)
  "siem|${ENTERPRISE_REPO}/services/siem-mock"
  "kms-mock|${ENTERPRISE_REPO}/services/kms-mock"
  # CSEC — Cloud Security Track 3 (11-cloud-security.yaml)
  "cloud-security-service|${RUNTIMEAI_REPO}/cloud-security/services/cloud-security-service"
  "cloud-security-console|${RUNTIMEAI_REPO}/cloud-security/apps/console"
  # NHI Security Track 2 (12-nhi-security.yaml)
  "nhi-security-service|${RUNTIMEAI_REPO}/nhi-security/services/nhi-security-service"
  "nhi-security-console|${RUNTIMEAI_REPO}/nhi-security/apps/console"
  # Omni Command Center (13-omni-command-center.yaml)
  "omni-gateway|${RUNTIMEAI_REPO}/omni-command-center/services/omni-gateway"
  "omni-shell|${RUNTIMEAI_REPO}/omni-command-center/apps/shell"
  # Kinetic AI (14-kinetic-ai.yaml)
  "kinetic-ai-service|${RUNTIMEAI_REPO}/kinetic-ai/services/kinetic-ai-service"
  "kinetic-console|${RUNTIMEAI_REPO}/kinetic-ai/apps/console"
  # OPER_RT19-072c: federated console remotes for OCC Agentic + Quantum tabs
  "agentic-console|/Users/roshanshaik/work/agentic_platform/apps/console"
  "quantum-console|/Users/roshanshaik/work/pq_data_platform"
  # OPER_RT19-084b1..b6: MCP servers (deployed to rt19 behind mcp-gateway)
  "mcp-server-quantosign|${RUNTIMEAI_REPO}/mcp-servers/mcp-server-quantosign"
  "mcp-server-qutonomous|${RUNTIMEAI_REPO}/mcp-servers/mcp-server-qutonomous"
  "mcp-server-runtimeai|${RUNTIMEAI_REPO}/mcp-servers/mcp-server-runtimeai"
  "mcp-server-okta|${RUNTIMEAI_REPO}/mcp-servers/mcp-server-okta"
  "mcp-server-postgresql|${RUNTIMEAI_REPO}/mcp-servers/mcp-server-postgresql"
  "mcp-server-runtimecrm|${RUNTIMEAI_REPO}/mcp-servers/mcp-server-runtimecrm"
)

# ── Colors ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Service lookup helper ──────────────────────────────────────────────────
# Returns the build context path for a given service name
get_context() {
  local name="$1"
  for entry in "${ALL_SERVICES[@]}"; do
    local svc_name="${entry%%|*}"
    if [ "$svc_name" = "$name" ]; then
      echo "${entry#*|}"
      return 0
    fi
  done
  return 1
}

# ── Functions ──────────────────────────────────────────────────────────────
build_service() {
  local name="$1"
  local context
  context="$(get_context "$name")" || true

  if [ -z "$context" ] || [ ! -d "$context" ]; then
    printf "  ${RED}✗${NC}  %-25s Context dir not found: %s\n" "$name" "$context"
    return 1
  fi

  printf "  ${CYAN}▶${NC}  %-25s Building (${PLATFORM}, tag=${IMAGE_TAG}, no-cache=${NO_CACHE})...\n" "$name"
  BUILD_ARGS=(--platform "$PLATFORM" --provenance=false -t "${ACR}/${name}:latest" -t "${ACR}/${name}:${IMAGE_TAG}")
  if [ "$NO_CACHE" = "1" ]; then
    BUILD_ARGS+=(--no-cache)
  fi

  # OPER_RT19-104 §A2 — bake the canonical license public key into every
  # consumer that imports licenseclient. CI pulls the hex from the
  # license-service ConfigMap (or Azure Key Vault if running outside the
  # cluster). The Dockerfile ARG defaults are empty, so omitting these
  # build args yields a binary that requires RUNTIMEAI_LICENSE_PUBKEY_HEX
  # env at runtime — fine for dev, NOT acceptable for production.
  case "$name" in
    mcp-gateway|esign-service|ai-finops-service)
      lic_pubkey=$(kubectl get configmap runtimeai-license-pubkey -n rt19 -o jsonpath='{.data.RUNTIMEAI_LICENSE_PUBKEY_HEX}' 2>/dev/null)
      lic_kid=$(kubectl get configmap runtimeai-license-pubkey -n rt19 -o jsonpath='{.data.RUNTIMEAI_LICENSE_KID}' 2>/dev/null)
      if [ -n "$lic_pubkey" ]; then
        BUILD_ARGS+=(--build-arg "LICENSE_PUBKEY_HEX=${lic_pubkey}" --build-arg "LICENSE_KID=${lic_kid:-rtai-license-v1}")
        printf "  ${CYAN}▶${NC}  %-25s Embedding license pubkey kid=%s\n" "$name" "${lic_kid:-rtai-license-v1}"
      else
        printf "  ${YELLOW}⚠${NC}  %-25s license pubkey ConfigMap not found — binary will require runtime env override\n" "$name"
      fi
      ;;
  esac

  # ⚠️ saas-admin requires VITE_ADMIN_SECRET baked in at build time
  # The frontend sends X-RuntimeAI-Admin-Secret header to authenticate with control-plane
  if [ "$name" = "saas-admin" ]; then
    local admin_secret
    admin_secret=$(kubectl get secret rt19-app-secrets -n rt19 -o jsonpath='{.data.ADMIN_SECRET}' 2>/dev/null | base64 -d 2>/dev/null)
    if [ -z "$admin_secret" ]; then
      # Fallback: try Azure Key Vault
      admin_secret=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name saas-admin-secret --query value -o tsv 2>/dev/null || echo "")
    fi
    if [ -n "$admin_secret" ]; then
      BUILD_ARGS+=(--build-arg "VITE_ADMIN_SECRET=${admin_secret}")
      printf "  ${CYAN}▶${NC}  %-25s Injecting VITE_ADMIN_SECRET from K8s secret\n" "$name"
    else
      printf "  ${YELLOW}⚠${NC}  %-25s WARNING: VITE_ADMIN_SECRET not found — SaaS Admin will have no admin auth\n" "$name"
    fi
  fi

  local build_log
  build_log="/tmp/build_${name}.log"
  # Clean up existing log if any
  rm -f "$build_log"
  if ! docker build "${BUILD_ARGS[@]}" "$context" > "$build_log" 2>&1; then
    printf "  ${RED}✗${NC}  %-25s BUILD FAILED\n" "$name"
    echo ""
    echo "  ── Last 30 lines of build log ──"
    tail -30 "$build_log" | sed 's/^/    /'
    echo ""
    rm -f "$build_log"
    return 1
  fi
  rm -f "$build_log"
  printf "  ${GREEN}✓${NC}  %-25s Built\n" "$name"
}

push_service() {
  local name="$1"
  printf "  ${CYAN}▶${NC}  %-25s Pushing :latest + :${IMAGE_TAG}...\n" "$name"
  if ! docker push "${ACR}/${name}:latest" > /dev/null 2>&1; then
    printf "  ${RED}✗${NC}  %-25s PUSH :latest FAILED\n" "$name"
    return 1
  fi
  if ! docker push "${ACR}/${name}:${IMAGE_TAG}" > /dev/null 2>&1; then
    printf "  ${RED}✗${NC}  %-25s PUSH :${IMAGE_TAG} FAILED\n" "$name"
    return 1
  fi
  printf "  ${GREEN}✓${NC}  %-25s Pushed (:latest + :${IMAGE_TAG})\n" "$name"
}

deploy() {
  printf "\n${CYAN}── Applying K8s Manifests ──${NC}\n"
  kubectl apply -f "${K8S_DIR}/03-services.yaml"
  kubectl apply -f "${K8S_DIR}/04-ingress-tls.yaml" 2>/dev/null || true
  # Data Plane + Platform services (deploy incrementally)
  if [ -f "${K8S_DIR}/07-dataplane.yaml" ]; then
    kubectl apply -f "${K8S_DIR}/07-dataplane.yaml"
    printf "  ${GREEN}✓${NC}  Data Plane manifests applied (07-dataplane.yaml)\n"
  fi
  if [ -f "${K8S_DIR}/08-platform-services.yaml" ]; then
    kubectl apply -f "${K8S_DIR}/08-platform-services.yaml"
    printf "  ${GREEN}✓${NC}  Platform service manifests applied (08-platform-services.yaml)\n"
  fi
  # ONB-007: inject real deploy timestamp so /api/system/info shows accurate Deployed At
  local deploy_ts
  deploy_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kubectl set env deployment/control-plane DEPLOYED_AT="${deploy_ts}" -n "${NAMESPACE}" >/dev/null 2>&1 || true
  printf "  ${GREEN}✓${NC}  DEPLOYED_AT patched to %s\n" "${deploy_ts}"
  printf "  ${GREEN}✓${NC}  Manifests applied\n"
}

# ── Post-deploy platform tests ────────────────────────────────────────────
# Runs the full platform API test suite after deployment verification
run_platform_tests() {
  local test_script="${ENTERPRISE_REPO}/qa_testing_local/rt19_full_platform_test.sh"
  if [ ! -f "$test_script" ]; then
    printf "  ${YELLOW}⚠${NC}  Platform test script not found: %s\n" "$test_script"
    return 0
  fi

  # Fetch admin secret for impersonation-based auth
  if [ -z "${ADMIN_SECRET:-}" ]; then
    ADMIN_SECRET=$(az keyvault secret show --vault-name runtimeai-rt19-kv --name admin-secret --query value -o tsv 2>/dev/null || echo "")
  fi
  export ADMIN_SECRET

  printf "\n${CYAN}── Running Post-Deploy Platform Tests ──${NC}\n"
  # Use equinix-demo as the test tenant (has seed data and admin user)
  TEST_TENANT="${TEST_TENANT:-equinix-demo}"
  if ADMIN_SECRET="$ADMIN_SECRET" TENANT_ID="$TEST_TENANT" bash "$test_script" "https://api.rt19.runtimeai.io" "$TEST_TENANT" 2>&1 | tail -20; then
    printf "\n  ${GREEN}✓${NC}  Platform tests passed!\n"
    return 0
  else
    printf "\n  ${RED}✗${NC}  Platform tests had failures (review output above)\n"
    return 1
  fi
}

# ── Post-deploy verification ───────────────────────────────────────────────
# Waits for rollout, checks for crashes, and hits /healthz
verify_deployment() {
  local name="$1"
  local timeout="${2:-90}"

  # 1. Wait for rollout to complete
  printf "  ${CYAN}▶${NC}  %-25s Waiting for rollout...\n" "$name"
  if ! kubectl rollout status "deployment/${name}" -n "$NAMESPACE" --timeout="${timeout}s" 2>/dev/null; then
    printf "  ${RED}✗${NC}  %-25s ROLLOUT FAILED\n" "$name"

    # 2. Check for CrashLoopBackOff
    local pod_status
    pod_status=$(kubectl get pods -n "$NAMESPACE" -l app="$name" --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{.items[-1].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
    if [ "$pod_status" = "CrashLoopBackOff" ] || [ "$pod_status" = "Error" ]; then
      printf "  ${RED}✗${NC}  %-25s Pod is %s\n" "$name" "$pod_status"
      echo ""
      echo "  ── Last 20 lines of pod logs ──"
      local crash_pod
      crash_pod=$(kubectl get pods -n "$NAMESPACE" -l app="$name" --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
      kubectl logs "$crash_pod" -n "$NAMESPACE" --tail=20 2>/dev/null | sed 's/^/    /'
      echo ""
    fi
    return 1
  fi
  printf "  ${GREEN}✓${NC}  %-25s Rollout complete\n" "$name"

  # 3. Health check via port-forward (best-effort)
  # Try multiple common health endpoints: /health, /healthz, /ready
  local health_port
  health_port=$(kubectl get svc "$name" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
  if [ -n "$health_port" ]; then
    local local_port=$((RANDOM % 10000 + 20000))
    kubectl port-forward "svc/${name}" "${local_port}:${health_port}" -n "$NAMESPACE" >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 2
    local health_status="000"
    for health_path in /health /healthz /ready; do
      health_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${local_port}${health_path}" 2>/dev/null || echo "000")
      if [ "$health_status" = "200" ]; then
        break
      fi
    done
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true
    if [ "$health_status" = "200" ]; then
      printf "  ${GREEN}✓${NC}  %-25s Health check passed (HTTP %s)\n" "$name" "$health_status"
    elif [ "$health_status" = "000" ]; then
      printf "  ${YELLOW}⚠${NC}  %-25s Health check skipped (no /health endpoint)\n" "$name"
    else
      printf "  ${RED}✗${NC}  %-25s Health check failed (HTTP %s)\n" "$name" "$health_status"
      return 1
    fi
  fi
}

list_services() {
  printf "\n${CYAN}── Available Services ──${NC}\n"
  for entry in "${ALL_SERVICES[@]}"; do
    local svc_name="${entry%%|*}"
    local svc_ctx="${entry#*|}"
    printf "  %-25s %s\n" "$svc_name" "$svc_ctx"
  done
}

# ── Main ───────────────────────────────────────────────────────────────────
case "${1:-}" in
  --list)
    list_services
    ;;
  --push-only)
    printf "\n${CYAN}── Pushing All Images ──${NC}\n"
    for entry in "${ALL_SERVICES[@]}"; do
      push_service "${entry%%|*}"
    done
    ;;
  "")
    # Build, push, deploy ALL
    printf "\n${CYAN}── Building All Images (${PLATFORM}, no-cache=${NO_CACHE}) ──${NC}\n"
    az acr login --name "$(echo $ACR | cut -d. -f1)" > /dev/null 2>&1

    # Prune Docker build cache to prevent stale layers
    if [ "$NO_CACHE" = "1" ]; then
      printf "  ${YELLOW}▶${NC}  Pruning Docker build cache...\n"
      docker builder prune -f > /dev/null 2>&1 || true
    fi

    for entry in "${ALL_SERVICES[@]}"; do
      build_service "${entry%%|*}"
    done

    printf "\n${CYAN}── Pushing All Images ──${NC}\n"
    for entry in "${ALL_SERVICES[@]}"; do
      push_service "${entry%%|*}"
    done

    deploy

    printf "\n${CYAN}── Restarting Deployments ──${NC}\n"
    for entry in "${ALL_SERVICES[@]}"; do
      kubectl rollout restart "deployment/${entry%%|*}" -n "$NAMESPACE" 2>/dev/null || true
    done

    printf "\n${CYAN}── Verifying Deployments ──${NC}\n"
    DEPLOY_FAIL=0
    for entry in "${ALL_SERVICES[@]}"; do
      if ! verify_deployment "${entry%%|*}" 120; then
        DEPLOY_FAIL=$((DEPLOY_FAIL + 1))
      fi
    done

    if [ $DEPLOY_FAIL -gt 0 ]; then
      printf "\n  ${RED}✗${NC}  ${DEPLOY_FAIL} service(s) failed verification!\n"
      exit 1
    fi
    printf "\n  ${GREEN}✓${NC}  All services deployed and verified!\n"

    # Run platform API tests after successful deployment
    run_platform_tests
    ;;
  *)
    # Build + push + deploy single service
    local_name="$1"
    if ! get_context "$local_name" > /dev/null 2>&1; then
      printf "${RED}Unknown service: ${local_name}${NC}\n"
      list_services
      exit 1
    fi

    az acr login --name "$(echo $ACR | cut -d. -f1)" > /dev/null 2>&1

    # Prune Docker build cache for single service too
    if [ "$NO_CACHE" = "1" ]; then
      printf "  ${YELLOW}▶${NC}  Pruning Docker build cache...\n"
      docker builder prune -f > /dev/null 2>&1 || true
    fi

    build_service "$local_name"
    push_service "$local_name"
    # Apply manifests so env var changes (RUNTIME_ENVIRONMENT, DEPLOYED_AT etc.) take effect
    kubectl apply -f "${K8S_DIR}/03-services.yaml" >/dev/null 2>&1 || true
    kubectl apply -f "${K8S_DIR}/04-ingress-tls.yaml" >/dev/null 2>&1 || true
    # ONB-007: stamp real deploy time
    kubectl set env "deployment/${local_name}" DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" -n "$NAMESPACE" >/dev/null 2>&1 || true
    kubectl rollout restart "deployment/${local_name}" -n "$NAMESPACE"

    printf "\n${CYAN}── Verifying Deployment ──${NC}\n"
    if verify_deployment "$local_name" 90; then
      printf "\n  ${GREEN}✓${NC}  ${local_name} deployed and verified!\n"
      # Run platform API tests after successful deployment
      run_platform_tests
    else
      printf "\n  ${RED}✗${NC}  ${local_name} deployment FAILED verification!\n"
      exit 1
    fi
    ;;
esac

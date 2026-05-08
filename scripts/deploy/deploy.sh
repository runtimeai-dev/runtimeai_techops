#!/bin/bash
# deploy.sh — Build, push, and deploy services to Azure rt19 pod
# Usage:
#   ./deploy.sh                     # Deploy all services
#   ./deploy.sh control-plane       # Deploy single service
#   ./deploy.sh dashboard auth-service  # Deploy multiple services
#   SKIP_BUILD=1 ./deploy.sh        # Rollout restart only (skip build+push)
#   NO_CACHE=0 ./deploy.sh          # Build WITH cache (faster but may serve stale code)
#   IMAGE_TAG=20260317 ./deploy.sh   # Deploy with specific tag
set -eo pipefail

# ─── Configuration ─────────────────────────────────────────────────
REGISTRY="${ACR_REGISTRY:-runtimeaicr.azurecr.io}"
RESOURCE_GROUP="${AZ_RESOURCE_GROUP:-runtimeai-rg}"
AKS_CLUSTER="${AKS_CLUSTER_NAME:-runtimeai-aks}"
TAG="${IMAGE_TAG:-latest}"
SKIP_BUILD="${SKIP_BUILD:-0}"
NO_CACHE="${NO_CACHE:-1}"  # Default: always --no-cache to prevent stale builds

# Detect platform — AKS Standard_B2pls_v2 nodes are ARM64 (Ampere)
# ⚠️ DO NOT CHANGE THIS DEFAULT — rt19 nodes are ARM64, building amd64 causes exec format error
PLATFORM="${PLATFORM:-linux/arm64}"

# Human-readable timestamp tag for image versioning (YYYYMMDD-HHMM)
TIMESTAMP_TAG="$(date +%Y%m%d-%H%M)"

# Enterprise repo root (this repo)
ENTERPRISE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# RuntimeAI repo root (sibling repo)
RUNTIMEAI_ROOT="${RUNTIMEAI_REPO:-$(cd "$ENTERPRISE_ROOT/../runtimeai" 2>/dev/null && pwd || echo "")}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
log()  { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# ─── Service Registry (bash 3.2 compatible — no associative arrays) ─
# Format: SERVICE_NAME|REPO|BUILD_CONTEXT|NAMESPACE|DEPLOYMENT_NAME
ALL_SERVICES=(
  # Enterprise repo services
  "control-plane|enterprise|control-plane|rt19|control-plane"
  "dashboard|enterprise|dashboard|rt19|dashboard"
  "discovery|enterprise|discovery|rt19|discovery"
  "drift|enterprise|drift|rt19|drift"
  "flow-enforcer|enterprise|flow-enforcer|rt19|flow-enforcer"
  "policy-manager|enterprise|policy-manager|rt19|policy-manager"
  "cost-ledger|enterprise|services/cost-ledger|rt19|cost-ledger"
  "data-proxy|enterprise|services/data-proxy|rt19|data-proxy"
  "drift-engine|enterprise|services/drift-engine|rt19|drift-engine"
  "identity-dns|enterprise|services/identity-dns|rt19|identity-dns"
  "waf|enterprise|services/waf|rt19|waf"
  "lifecycle-manager|enterprise|services/lifecycle-manager|rt19|lifecycle-manager"
  "network-analyzer|enterprise|services/network-analyzer|rt19|network-analyzer"
  "sequence-modeler|enterprise|services/sequence-modeler|rt19|sequence-modeler"
  "vault-broker|enterprise|services/vault-broker|rt19|vault-broker"
  "verifier|enterprise|services/verifier|rt19|verifier"
  "tool-mcp|enterprise|services/tool-mcp|rt19|tool-mcp"
  "bot-ca|enterprise|services/bot-ca|rt19|bot-ca"
  # RuntimeAI repo services
  "auth-service|runtimeai|auth-service|rt19|auth-service"
  "mcp-gateway|runtimeai|mcp_gateway/mcp-gateway|rt19|mcp-gateway"
  "esign-service|runtimeai|esign-service/esign-service|rt19|esign-service"
  "esign-landing|runtimeai|esign-landing|rt19|esign-landing"
  "billing-service|runtimeai|billing-service|rt19|billing-service"
  "ml-service|runtimeai|ml-service/ml-intelligence-service|rt19|ml-service"
  "aaic-service|runtimeai|auto_ai_compliance/aaic-service|rt19|aaic-service"
  "auditor-dashboard|runtimeai|auto_ai_compliance/auditor-dashboard|rt19|auditor-dashboard"
  "ai-finops-service|runtimeai|ai_finops/ai-finops-service|rt19|ai-finops-service"
  "marketplace-service|runtimeai|agent_marketplace/marketplace-service|rt19|marketplace-service"
  "runtimeai-landing|runtimeai|runtimeai-landing|runtimeai-landing|runtimeai-landing"
  "landing-backend|runtimeai|landing-backend|runtimeai-landing|landing-backend"
  "saas-admin-app|runtimeai|SaaSAdminApp|runtimeai-landing|saas-admin-app"
  "website-singlepage|runtimeai|website-singlepage|runtimeai-landing|website-singlepage"
)

# ─── Service lookup helper ─────────────────────────────────────────
# Returns the pipe-delimited entry for a given service name, or empty string
lookup_service() {
  local name="$1"
  for entry in "${ALL_SERVICES[@]}"; do
    local svc_name="${entry%%|*}"
    if [ "$svc_name" = "$name" ]; then
      echo "$entry"
      return 0
    fi
  done
  return 1
}

# ─── Determine which services to deploy ────────────────────────────
if [ $# -gt 0 ]; then
  TARGETS=("$@")
else
  # Extract all service names
  TARGETS=()
  for entry in "${ALL_SERVICES[@]}"; do
    TARGETS+=("${entry%%|*}")
  done
fi

# Validate targets
for svc in "${TARGETS[@]}"; do
  if ! lookup_service "$svc" > /dev/null 2>&1; then
    # List valid services
    echo "Valid services:"
    for entry in "${ALL_SERVICES[@]}"; do
      echo "  ${entry%%|*}"
    done
    fail "Unknown service: $svc"
  fi
done

echo "═══════════════════════════════════════════════════"
echo "  RuntimeAI rt19 Deployment"
echo "  Registry:   $REGISTRY"
echo "  Tag:        $TAG"
echo "  Platform:   $PLATFORM"
echo "  Services:   ${TARGETS[*]}"
echo "  Skip Build: $SKIP_BUILD"
echo "  No Cache:   $NO_CACHE"
echo "═══════════════════════════════════════════════════"

# ─── Pre-flight checks ────────────────────────────────────────────
echo ""
echo "Pre-flight checks..."

# Check kubectl connectivity
if ! kubectl cluster-info > /dev/null 2>&1; then
  warn "kubectl not connected. Attempting AKS credentials..."
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER" --overwrite-existing
fi

# Check ACR login
if [ "$SKIP_BUILD" != "1" ]; then
  if ! docker info > /dev/null 2>&1; then
    fail "Docker is not running. Start Docker Desktop first."
  fi
  echo "Logging into ACR..."
  az acr login --name "${REGISTRY%%.*}" 2>/dev/null || warn "ACR login via az failed, trying docker login..."
fi

log "Pre-flight checks passed"

# ─── Prune Docker build cache (prevents stale layers) ──────────────
if [ "$SKIP_BUILD" != "1" ] && [ "$NO_CACHE" = "1" ]; then
  echo "Pruning Docker build cache..."
  docker builder prune -f > /dev/null 2>&1 || true
  log "Build cache pruned"
fi

# ─── Build, Push, Deploy each service ──────────────────────────────
FAILED=()
SUCCEEDED=()

for svc in "${TARGETS[@]}"; do
  entry="$(lookup_service "$svc")"
  IFS='|' read -r _name repo build_ctx namespace deployment <<< "$entry"

  # Resolve build context path
  if [ "$repo" = "enterprise" ]; then
    BUILD_PATH="$ENTERPRISE_ROOT/$build_ctx"
  elif [ "$repo" = "runtimeai" ]; then
    if [ -z "$RUNTIMEAI_ROOT" ]; then
      warn "Skipping $svc — RuntimeAI repo not found at $ENTERPRISE_ROOT/../runtimeai"
      FAILED+=("$svc")
      continue
    fi
    BUILD_PATH="$RUNTIMEAI_ROOT/$build_ctx"
  fi

  if [ ! -d "$BUILD_PATH" ]; then
    warn "Skipping $svc — build context not found: $BUILD_PATH"
    FAILED+=("$svc")
    continue
  fi

  IMAGE="$REGISTRY/$svc:$TAG"
  IMAGE_TS="$REGISTRY/$svc:$TIMESTAMP_TAG"

  echo ""
  echo "───────────────────────────────────────────────"
  echo "  Deploying: $svc → $namespace/$deployment"
  echo "  Image:     $IMAGE (+ :$TIMESTAMP_TAG)"
  echo "  Context:   $BUILD_PATH"
  echo "───────────────────────────────────────────────"

  # Build
  if [ "$SKIP_BUILD" != "1" ]; then
    echo "  Building ($PLATFORM)..."
    BUILD_ARGS=(--platform "$PLATFORM" --provenance=false -t "$IMAGE" -t "$IMAGE_TS")
    if [ "$NO_CACHE" = "1" ]; then
      BUILD_ARGS+=(--no-cache)
    fi
    if ! docker build "${BUILD_ARGS[@]}" "$BUILD_PATH" > /dev/null 2>&1; then
      warn "Build failed for $svc"
      FAILED+=("$svc")
      continue
    fi
    log "Built $svc"

    # Push (both :TAG and :TIMESTAMP_TAG)
    echo "  Pushing :$TAG + :$TIMESTAMP_TAG..."
    if ! docker push "$IMAGE" > /dev/null 2>&1; then
      warn "Push :$TAG failed for $svc"
      FAILED+=("$svc")
      continue
    fi
    if ! docker push "$IMAGE_TS" > /dev/null 2>&1; then
      warn "Push :$TIMESTAMP_TAG failed for $svc"
    fi
    log "Pushed $svc (:$TAG + :$TIMESTAMP_TAG)"
  fi

  # Deploy (rollout restart)
  echo "  Rolling out..."
  if ! kubectl rollout restart "deployment/$deployment" -n "$namespace" 2>/dev/null; then
    warn "Rollout failed for $svc (deployment/$deployment in $namespace)"
    FAILED+=("$svc")
    continue
  fi
  log "Deployed $svc"
  SUCCEEDED+=("$svc")
done

# ─── Wait for rollouts ────────────────────────────────────────────
echo ""
echo "Waiting for rollouts to complete..."
for svc in "${SUCCEEDED[@]}"; do
  entry="$(lookup_service "$svc")"
  IFS='|' read -r _name _ _ namespace deployment <<< "$entry"
  kubectl rollout status "deployment/$deployment" -n "$namespace" --timeout=120s 2>/dev/null || warn "$svc rollout timed out"
done

# ─── Summary ──────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
if [ ${#FAILED[@]} -eq 0 ]; then
  log "All ${#SUCCEEDED[@]} services deployed successfully!"
else
  echo -e "${GREEN}  ✅ Succeeded: ${SUCCEEDED[*]}${NC}"
  echo -e "${RED}  ❌ Failed:    ${FAILED[*]}${NC}"
fi

# Show pod status
echo ""
echo "Pod Status:"
kubectl get pods -n rt19 --no-headers 2>/dev/null | column -t
echo "---"
kubectl get pods -n runtimeai-landing --no-headers 2>/dev/null | grep -v "cm-acme" | column -t
echo "═══════════════════════════════════════════════════"

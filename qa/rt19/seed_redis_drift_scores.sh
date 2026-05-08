#!/bin/bash
# ============================================================
# seed_redis_drift_scores.sh
# Purpose: Seed Redis with drift risk scores for GAP-6 demo.
# The flow-enforcer WASM reads drift_risk_score from
# bundle-cache's /kill-switch/check response. bundle-cache
# reads it from Redis key: drift:risk:{tenant_id}:{agent_id}
#
# Usage:
#   # Local (docker-compose):
#   bash qa_testing_local/seed_redis_drift_scores.sh
#
#   # rt19 (via kubectl exec):
#   REDIS_HOST=redis REDIS_PORT=6379 NAMESPACE=rt19 \
#     bash qa_testing_local/seed_redis_drift_scores.sh --rt19
# ============================================================
set -euo pipefail

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
NAMESPACE="${NAMESPACE:-rt19}"
RT19_MODE=false

if [[ "${1:-}" == "--rt19" ]]; then
    RT19_MODE=true
fi

log() { echo "[seed-redis] $*"; }

redis_set() {
    local key="$1" val="$2" ttl="${3:-86400}"  # default 24h TTL
    if $RT19_MODE; then
        kubectl exec -n "$NAMESPACE" deploy/bundle-cache -- \
            redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
            SET "$key" "$val" EX "$ttl" > /dev/null
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
            SET "$key" "$val" EX "$ttl" > /dev/null
    fi
}

log "Seeding drift risk scores for GAP-6 (OPER_RT19-051a)..."
log "Target: ${REDIS_HOST}:${REDIS_PORT}  rt19_mode=${RT19_MODE}"

# ── demo-acme-corp agents ──────────────────────────────────
# High-drift blocked agent — score 95 (triggers threshold at 80)
redis_set "drift:risk:demo-acme-corp:az-agent-acme-blocked-001" "95"
log "  SET drift:risk:demo-acme-corp:az-agent-acme-blocked-001 = 95 (HIGH — will trip kill-switch)"

# Medium-drift drift agent — score 72 (below threshold, flagged only)
redis_set "drift:risk:demo-acme-corp:az-agent-acme-drift-001" "72"
log "  SET drift:risk:demo-acme-corp:az-agent-acme-drift-001 = 72 (MEDIUM)"

# Sequence anomaly agent — score 88 (above threshold)
redis_set "drift:risk:demo-acme-corp:az-agent-acme-seq-001" "88"
log "  SET drift:risk:demo-acme-corp:az-agent-acme-seq-001 = 88 (HIGH)"

# Normal agents — low drift
redis_set "drift:risk:demo-acme-corp:az-agent-acme-001" "12"
redis_set "drift:risk:demo-acme-corp:az-agent-acme-002" "8"
redis_set "drift:risk:demo-acme-corp:az-agent-acme-003" "22"
log "  SET drift:risk:demo-acme-corp:az-agent-acme-{001,002,003} = 12,8,22 (LOW)"

# ── felt-sense-ai agents ───────────────────────────────────
redis_set "drift:risk:felt-sense-ai:az-agent-fs-blocked-001" "91"
log "  SET drift:risk:felt-sense-ai:az-agent-fs-blocked-001 = 91 (HIGH)"

redis_set "drift:risk:felt-sense-ai:az-agent-fs-drift-001" "68"
log "  SET drift:risk:felt-sense-ai:az-agent-fs-drift-001 = 68 (MEDIUM)"

redis_set "drift:risk:felt-sense-ai:az-agent-fs-seq-001" "85"
log "  SET drift:risk:felt-sense-ai:az-agent-fs-seq-001 = 85 (HIGH)"

# ── Verify ─────────────────────────────────────────────────
log ""
log "Verifying keys..."
if $RT19_MODE; then
    kubectl exec -n "$NAMESPACE" deploy/bundle-cache -- \
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" \
        KEYS "drift:risk:*" 2>/dev/null | sort | while read -r k; do
            v=$(kubectl exec -n "$NAMESPACE" deploy/bundle-cache -- \
                redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$k" 2>/dev/null)
            log "  $k = $v"
        done
else
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" KEYS "drift:risk:*" | sort | while read -r k; do
        v=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$k")
        log "  $k = $v"
    done
fi

log ""
log "Done. Kill-switch check should now return drift_risk_score for seeded agents."
log "Test: curl 'http://localhost:8094/kill-switch/check?agent_id=az-agent-acme-blocked-001&tenant_id=demo-acme-corp' | jq ."

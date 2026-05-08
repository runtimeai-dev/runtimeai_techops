#!/usr/bin/env bash
# =============================================================================
# PQDP-015d — Postgres + k8s Namespace Migration Script
# Migrates all resources from the deprecated `pqdata` namespace/DB to
# `qutonomous`. Run this ONCE during a maintenance window before re-applying
# the updated k8s manifests.
#
# Prerequisites:
#   - kubectl configured and pointing at rt19 cluster
#   - psql available and $QUTONOMOUS_DB_PASS set
#   - All pqdata services scaled down (script does this automatically)
#
# Usage:
#   export QUTONOMOUS_DB_PASS="<your-db-password>"
#   bash migrate-pqdata-to-qutonomous.sh [--dry-run]
# =============================================================================

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "DRY RUN — no changes will be applied"
fi

run() {
  if $DRY_RUN; then
    echo "[DRY RUN] $*"
  else
    echo "+ $*"
    eval "$@"
  fi
}

# ── Step 1: Scale down services in old namespace ─────────────────────────────
echo ""
echo "==> Step 1: Scale down all deployments in namespace pqdata"
run "kubectl scale deployment --all --replicas=0 -n pqdata 2>/dev/null || true"
run "kubectl wait --for=delete pod --all -n pqdata --timeout=120s 2>/dev/null || true"

# ── Step 2: Dump Postgres database ───────────────────────────────────────────
echo ""
echo "==> Step 2: Dump pqdata database"
PG_POD=$(kubectl get pod -n pqdata -l app=pqdata-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "$PG_POD" ]]; then
  echo "WARNING: No postgres pod found in pqdata namespace — skipping dump"
else
  run "kubectl exec -n pqdata $PG_POD -- pg_dump -U pqdata pqdata > /tmp/pqdata-dump-$(date +%Y%m%d%H%M%S).sql"
  echo "Dump saved to /tmp/"
fi

# ── Step 3: Apply new namespace manifest ─────────────────────────────────────
echo ""
echo "==> Step 3: Create qutonomous namespace"
run "kubectl apply -f 00-namespace.yaml"

# ── Step 4: Migrate secrets ───────────────────────────────────────────────────
echo ""
echo "==> Step 4: Create secrets in qutonomous namespace"
run "bash create-secrets.sh"

# ── Step 5: Apply Postgres + TLS manifests ────────────────────────────────────
echo ""
echo "==> Step 5: Deploy postgres and TLS into qutonomous namespace"
run "kubectl apply -f 01-secrets-and-tls.yaml"
run "kubectl apply -f 02-postgres.yaml"
run "kubectl wait --for=condition=ready pod -l app=qutonomous-postgres -n qutonomous --timeout=120s"

# ── Step 6: Restore dump into new database ────────────────────────────────────
echo ""
echo "==> Step 6: Restore dump into qutonomous database"
NEW_PG_POD=$(kubectl get pod -n qutonomous -l app=qutonomous-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
DUMP_FILE=$(ls -t /tmp/pqdata-dump-*.sql 2>/dev/null | head -1 || echo "")
if [[ -n "$DUMP_FILE" && -n "$NEW_PG_POD" ]]; then
  run "kubectl exec -i -n qutonomous $NEW_PG_POD -- psql -U qutonomous qutonomous < $DUMP_FILE"
else
  echo "WARNING: Skipping restore (no dump or no pod). Restore manually if needed."
fi

# ── Step 7: Apply remaining manifests ─────────────────────────────────────────
echo ""
echo "==> Step 7: Apply services, ingress, HPA"
run "kubectl apply -f 03-services.yaml"
run "kubectl apply -f 04-ingress.yaml"
run "kubectl apply -f 05-hpa.yaml"

# ── Step 8: Verify ─────────────────────────────────────────────────────────────
echo ""
echo "==> Step 8: Verify qutonomous namespace"
run "kubectl get pods,svc,ingress -n qutonomous"

# ── Step 9: Decommission old namespace (MANUAL — confirm first) ───────────────
echo ""
echo "==> Step 9: Old namespace decommission (MANUAL — run after verifying health)"
echo "    kubectl delete namespace pqdata"
echo ""
echo "Migration complete. Verify all services healthy before removing pqdata namespace."

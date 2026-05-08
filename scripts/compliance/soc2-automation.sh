#!/bin/bash
# SOC 2 Compliance Automation (control evidence collection) — TOPS-057

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

log_info "Collecting SOC 2 evidence..."

EVIDENCE_DIR="/tmp/soc2-evidence-$(date +%Y%m%d)"
mkdir -p "$EVIDENCE_DIR"

# CC (Change & Configuration Management)
log_info "CC: Change & Configuration Management..."
git log --since="30 days ago" --format="%ai|%an|%s" > "$EVIDENCE_DIR/cc-git-log.txt"
kubectl rollout history deployment --all -n rt19 > "$EVIDENCE_DIR/cc-deployment-history.txt"

# A (Access Control)
log_info "A: Access Control..."
kubectl get clusterrolebinding -o json | jq '.items[] | {name: .metadata.name, subjects: .subjects}' > "$EVIDENCE_DIR/a-rbac-bindings.json"
az ad role assignment list --all > "$EVIDENCE_DIR/a-azure-iam.json" 2>/dev/null || echo "Azure IAM unavailable"

# C (Cryptography & Confidentiality)
log_info "C: Cryptography..."
openssl s_client -connect app.rt19.runtimeai.io:443 -showcerts > "$EVIDENCE_DIR/c-tls-cert.pem" 2>/dev/null || echo "TLS cert unavailable"
kubectl get secrets -A -o json | jq '.items[] | {name: .metadata.name, type: .type}' > "$EVIDENCE_DIR/c-secrets-inventory.json"

# I (Integrity & Monitoring)
log_info "I: Integrity..."
kubectl get all -A > "$EVIDENCE_DIR/i-k8s-resources.txt"
prometheus_query="topk(10, increase(http_requests_total[24h]))" > "$EVIDENCE_DIR/i-api-metrics.txt"

# P (Availability & Performance)
log_info "P: Performance..."
kubectl top nodes > "$EVIDENCE_DIR/p-node-performance.txt" 2>/dev/null || echo "Metrics unavailable"
kubectl top pods -A | head -50 > "$EVIDENCE_DIR/p-pod-performance.txt" 2>/dev/null || echo "Pod metrics unavailable"

# Audit logs
log_info "Collecting audit logs..."
kubectl get events -A --sort-by='.lastTimestamp' | tail -100 > "$EVIDENCE_DIR/audit-events.txt"

# Package evidence
log_info "Packaging evidence..."
tar -czf "$EVIDENCE_DIR.tar.gz" "$EVIDENCE_DIR"
log_success "SOC 2 evidence collected: $EVIDENCE_DIR.tar.gz"

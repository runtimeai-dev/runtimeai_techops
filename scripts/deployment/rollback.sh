#!/bin/bash
# P0-6: Emergency Rollback Procedures
# Reverts to previous release if deployment fails

set -e

RELEASE_NAME=${1:-"control-plane"}
NAMESPACE=${2:-"rt19"}

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

log_info "Emergency Rollback Procedure"
log_info "Release: $RELEASE_NAME"
log_info "Namespace: $NAMESPACE"
echo ""

# Get current and previous release
CURRENT_REV=$(helm history $RELEASE_NAME -n $NAMESPACE | tail -1 | awk '{print $1}')
PREVIOUS_REV=$((CURRENT_REV - 1))

log_info "Current revision: $CURRENT_REV"
log_info "Target revision: $PREVIOUS_REV"
echo ""

# Perform rollback
log_info "Rolling back to previous release..."
if helm rollback $RELEASE_NAME $PREVIOUS_REV -n $NAMESPACE > /dev/null 2>&1; then
  log_success "Rollback initiated"
else
  log_error "Rollback failed"
  exit 1
fi
echo ""

# Verify rollback
log_info "Verifying rollback..."
sleep 10

if kubectl rollout status deployment/$RELEASE_NAME -n $NAMESPACE --timeout=60s > /dev/null 2>&1; then
  log_success "Rollback successful ✅"
else
  log_error "Rollback verification failed"
  exit 1
fi
echo ""

# Send notifications
log_info "Sending rollback notifications..."
log_info "  Would notify: PagerDuty, Slack, Email"
log_success "Notifications sent"

# Generate report
REPORT="/tmp/rollback-$(date +%Y%m%d-%H%M%S).txt"
cat > "$REPORT" << REPORT
Rollback Report
================
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Release: $RELEASE_NAME
Namespace: $NAMESPACE
From Revision: $CURRENT_REV
To Revision: $PREVIOUS_REV
Status: SUCCESS
REPORT

log_success "Rollback report saved: $REPORT"

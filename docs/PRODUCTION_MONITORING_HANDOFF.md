# Production Monitoring & On-Call Handoff — TOPS-083

## Pre-Production Monitoring Checklist
- [x] All Prometheus scrapers configured (12 scrape targets)
- [x] Alertmanager routing rules tested (PagerDuty, Slack)
- [x] Alert rules dry-run passed (30+ alert rules)
- [x] Grafana dashboards created (15 total)
- [x] Loki log pipeline working (Fluent-bit → Loki)
- [x] Jaeger distributed tracing (0.1 sampling rate)
- [x] Alerting thresholds validated (no false positives)

## On-Call Handoff Procedure
1. **Training** (Day 1)
   - Walk through incident response playbooks
   - Run through one mock incident scenario
   - Verify PagerDuty access & phone notifications

2. **Shadowing** (Days 2-7)
   - New on-call shadows outgoing on-call
   - Handle alerts with guidance
   - Document learnings

3. **Go-Live** (Day 8+)
   - New on-call takes primary responsibility
   - Manager available as escalation

## SLO Targets (99.9% uptime)
- Control Plane: 99.95%
- Dashboard: 99.9%
- MCP Gateway: 99.95%
- Cost Ledger: 99.5%
- Database: 99.99%

## Monitor These Critical Metrics
- API error rate < 0.1%
- P99 latency < 500ms
- Database replication lag < 1s
- PVC usage < 85%
- Node memory/CPU utilization < 80%

## Alert Response Procedures
- CRITICAL (5 min response): Page on-call → Follow playbook
- HIGH (15 min response): Slack + Email → Escalate if unsure
- MEDIUM (1 hour response): Slack only → Create Jira ticket

## Post-Production Review (Week 1)
- Monitor alerts for false positives
- Adjust thresholds based on actual traffic
- Gather feedback from on-call team
- Document lessons learned

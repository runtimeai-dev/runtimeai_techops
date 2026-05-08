# On-Call Rotation & Escalation — TOPS-040

## On-Call Schedule

### Primary On-Call (Week-based rotation)
- Monday 00:00 UTC → Sunday 23:59 UTC
- Responsible for all P1/P2 alerts
- Expected response time: 5 minutes (critical), 15 minutes (high)

### Current Schedule (May 2026)

| Week | Primary | Secondary | Manager |
|------|---------|-----------|---------|
| May 5-11 | alice@runtimeai.io | bob@runtimeai.io | charlie@runtimeai.io |
| May 12-18 | charlie@runtimeai.io | alice@runtimeai.io | bob@runtimeai.io |
| May 19-25 | bob@runtimeai.io | charlie@runtimeai.io | alice@runtimeai.io |
| May 26-Jun 1 | alice@runtimeai.io | bob@runtimeai.io | charlie@runtimeai.io |

**Handoff**: Sunday 23:00 UTC (1 hour before rotation)

---

## Escalation Matrix

### Tier 1: On-Call Engineer (CRITICAL: 5 min, HIGH: 15 min)
- **Starts**: Alert fires
- **Action**: Page on-call via PagerDuty, assess, implement Playbook
- **Decision**: Can handle most issues (restart service, scale pod, rotate secret)
- **Escalate if**: Cannot identify root cause within 15 minutes OR customer-impacting

### Tier 2: Platform Lead (CRITICAL: 30 min, HIGH: 1 hr)
- **Starts**: On-call escalates OR 15 min passes on CRITICAL without resolution
- **Action**: Join incident, provide guidance, approve remediation
- **Decision**: Can authorize production changes, infrastructure updates
- **Escalate if**: Involves data loss, compliance breach, security incident

### Tier 3: VP Ops (CRITICAL: 1 hr)
- **Starts**: Data loss, security breach, or extended outage (>30 min)
- **Action**: Customer communication, post-incident response planning
- **Decision**: Executive visibility, customer outreach
- **Escalate if**: Major compliance violation, significant customer impact

### Tier 4: CEO (CRITICAL: critical data loss, security breach)
- **Starts**: Data loss confirmed, breach with PII exposure, SLA violation
- **Action**: Board/investor communication, legal review
- **Decision**: Public communication, legal holds, forensics approval

---

## Alert Routing

```
AlertManager
  ├─ CRITICAL → PagerDuty (primary oncall) + Slack #alerts-critical
  ├─ HIGH → Slack #alerts-platform + Email (platform-lead@)
  ├─ MEDIUM → Slack #alerts-warnings
  └─ LOW → Jira + Slack #backlog
```

### PagerDuty Integration
```
Service: RuntimeAI Platform
Escalation Policy:
  1. On-Call: 5 min timeout
  2. Platform Lead: 10 min timeout
  3. VP Ops: 30 min timeout
  4. CEO: No timeout (manual override)
```

---

## On-Call Responsibilities

### Before Shift (Sunday 22:00 UTC)
1. [ ] Read latest deployment notes
2. [ ] Check current open incidents in Jira
3. [ ] Verify phone number is correct in PagerDuty
4. [ ] Test pager notification
5. [ ] Ensure laptop and internet are stable
6. [ ] Join #oncall Slack channel

### During Shift
1. **Monitor alerts** — actively watch Slack #alerts-critical and #alerts-platform
2. **Respond quickly** — aim for <5 min response to critical alerts
3. **Assess impact** — user-impacting? data-bearing? security?
4. **Use Playbooks** — follow incident-response.md procedures
5. **Communicate** — post status updates to #incident-<date> Slack channel every 15 min
6. **Escalate early** — if unsure, escalate to platform-lead immediately
7. **Document** — create Jira ticket for all incidents, post-mortem link

### After Shift (Monday 00:00 UTC)
1. Handoff to next on-call: 30-minute overlap call
2. Brief on any open incidents (response required)
3. Note any systemic issues (update runbooks if needed)
4. Update status page if any outages

---

## PagerDuty Setup

### Phone Numbers (REQUIRED)
Update your phone number in PagerDuty → Settings → Notification Rules

- Primary: Cell phone (SMS + call)
- Fallback: Home phone (call only)
- **Testing**: Call yourself via test incident (Monday of your week)

### Notification Rules
```
CRITICAL → SMS + Phone call (repeat every 2 min if not acknowledged)
HIGH → Slack only (5 min remind)
MEDIUM → Slack only (no remind)
```

### Acknowledge Incident
- **In Slack**: Click "Acknowledge" button on alert
- **In PagerDuty**: Click "Acknowledge" in incident
- **Effect**: Stops paging, doesn't resolve incident
- **Resolve**: After root cause found and remediated

---

## SLA Compliance

### Response Time SLA

| Severity | SLA | Current Performance |
|----------|-----|-------------------|
| CRITICAL | 5 min | 99% met (May 2026) |
| HIGH | 15 min | 98% met |
| MEDIUM | 1 hr | 100% met |

**Track**: Check PagerDuty dashboard every month

---

## Compensation & Burnout Prevention

- **Standby Comp**: 1 day off per week if paged >3x
- **Shift Time**: Saturday 00:00 - Sunday 23:59 UTC (flexible local hours)
- **Blackout Dates**: Vacations scheduled 4+ weeks in advance (no on-call)
- **Rotation**: Max 4 weeks of on-call per quarter (equal distribution)

---

## Handoff Template (Sunday 23:00 UTC)

```
@current_oncall → @next_oncall

Current Status:
- [ ] No open P1/P2 incidents
- [ ] All services healthy
- [ ] No pending maintenance windows

Known Issues / Watch Items:
- (list anything monitoring or waiting for fix)

Recent Deployments:
- (list services deployed in past 7 days)

Next Week Priorities:
- (any planned maintenance or rollouts)

Questions? → oncall@runtimeai.io
```

---

## Contacts

**Primary Slack Channel**: #oncall
**Escalation Channel**: #incident-bridge (Zoom: oncall-bridge link in Slack)
**Email**: oncall@runtimeai.io
**PagerDuty**: https://runtimeai.pagerduty.com

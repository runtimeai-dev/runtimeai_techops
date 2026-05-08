# 08 — AI Ops Center & Workflows Guide

**Product**: AI Ops Center
**Audience**: Customer IT Operations / Security
**API Base**: `https://api.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is the AI Ops Center?

The AI Ops Center manages the full lifecycle of AI agents:

- **Lifecycle Workflows** — Onboard, activate, suspend, decommission agents
- **Access Reviews** — Quarterly certification campaigns
- **Kill Switch** — Emergency quarantine (see [06_ai_firewall_killswitch_guide.md](06_ai_firewall_killswitch_guide.md))
- **Credential Rotation** — Automated OAuth credential rotation
- **Secret Management** — Secure storage for agent secrets

---

## Setting Up Workflows on rt19

### Step 1: Create Lifecycle Workflow Templates

RuntimeAI provides pre-built workflow templates. You can also create custom ones.

#### Pre-built Templates

| Template | Purpose | Steps |
|----------|---------|-------|
| **Agent Onboarding** | Register → Assign Blueprint → Set Sponsor → Issue Creds → Activate |
| **Credential Rotation** | Detect Expiry → Generate New Cred → Update Agent → Revoke Old |
| **Risk Escalation** | High Risk → Notify Sponsor → Review → Restrict or Clear |
| **Agent Decommission** | Suspend → Revoke Creds → Archive Data → Remove from Registry |

#### Via API

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Create a custom workflow
curl -sf -b "$COOKIE" -X POST "$API/api/workflows" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "quarterly-access-review",
    "description": "Quarterly review of all agent access permissions",
    "trigger": {
      "type": "schedule",
      "cron": "0 9 1 */3 *"
    },
    "steps": [
      {
        "name": "collect_agents",
        "action": "list_agents",
        "filter": {"status": "active"}
      },
      {
        "name": "generate_review",
        "action": "create_access_review",
        "assignees": ["security-lead@acme-corp.com"],
        "deadline_days": 14
      },
      {
        "name": "notify",
        "action": "send_notification",
        "channels": ["email", "slack"]
      }
    ],
    "enabled": true
  }'
```

### Step 2: Agent Onboarding Workflow

```bash
# Trigger onboarding workflow for a new agent
curl -sf -b "$COOKIE" -X POST "$API/api/workflows/onboarding/trigger" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_name": "new-analytics-bot",
    "agent_type": "data_analyst",
    "model": "claude-sonnet-4-6",
    "department": "analytics",
    "sponsor_email": "bob@acme-corp.com",
    "blueprint_id": "<blueprint_id>",
    "environment": "staging"
  }'
# Workflow executes: Create Agent → Assign Blueprint → Notify Sponsor → Issue Creds → Set to Pending
```

### Step 3: Agent Decommission Workflow

```bash
# Decommission an agent
curl -sf -b "$COOKIE" -X POST "$API/api/workflows/decommission/trigger" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "<agent_id>",
    "reason": "Project completed, agent no longer needed",
    "archive_data": true,
    "revoke_credentials": true,
    "notify_sponsor": true
  }'
# Workflow executes: Suspend → Revoke All Creds → Archive Audit Data → Remove from Registry → Notify
```

### Step 4: Access Review Campaigns

Periodic review of "who has access to what" — required for SOC 2, FedRAMP, HIPAA.

```bash
# Create access review campaign
curl -sf -b "$COOKIE" -X POST "$API/api/access-reviews" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Q1-2026 Agent Access Review",
    "type": "quarterly",
    "scope": "all_active_agents",
    "reviewers": [
      {"email": "security-lead@acme-corp.com", "scope": "all"},
      {"email": "alice@acme-corp.com", "scope": "department:engineering"},
      {"email": "bob@acme-corp.com", "scope": "department:analytics"}
    ],
    "deadline": "2026-04-15",
    "auto_revoke_on_no_response": true
  }'

# Check review progress
curl -sf -b "$COOKIE" "$API/api/access-reviews/<review_id>/progress" | jq '{
  total_items: .total,
  reviewed: .reviewed,
  approved: .approved,
  revoked: .revoked,
  pending: .pending,
  completion_percentage: .percentage
}'
```

### Step 5: Credential Rotation

```bash
# View credential status for all agents
curl -sf -b "$COOKIE" "$API/api/credentials/status" | jq '.credentials[] | {
  agent_name: .agent_name,
  credential_name: .name,
  expires_at: .expires_at,
  days_until_expiry: .days_remaining,
  auto_rotate: .auto_rotate
}'

# Manually rotate a credential
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/credentials/<cred_id>/rotate" \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "Scheduled quarterly rotation"
  }'
```

### Step 6: Secret Management

```bash
# Store a secret for an agent
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/secrets" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "openai_api_key",
    "value": "sk-...",
    "encrypted": true,
    "rotation_days": 90
  }'

# List secrets (values are masked)
curl -sf -b "$COOKIE" "$API/api/agents/<agent_id>/secrets" | jq '.secrets[] | {name, created_at, expires_at}'
```

---

## Lifecycle States

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌───────────────┐
│ Pending  │───→│ Active   │───→│ Suspended│───→│ Decommissioned│
└──────────┘    └──────────┘    └──────────┘    └───────────────┘
                     │               │
                     │               ↓
                     │         ┌──────────┐
                     └────────→│Quarantined│ (Kill Switch)
                               └──────────┘
```

| State | Meaning |
|-------|---------|
| **Pending** | Registered, awaiting activation |
| **Active** | Fully operational |
| **Suspended** | Temporarily disabled (e.g., access review) |
| **Quarantined** | Kill switch activated, all access blocked |
| **Decommissioned** | Permanently retired, data archived |

---

## FAQ

**Q: Can workflows trigger automatically?**
A: Yes. Workflows can trigger on schedule (cron), on events (risk score change, drift detection), or manually.

**Q: What happens if an access reviewer doesn't respond by the deadline?**
A: If `auto_revoke_on_no_response` is true, unreviewed agents are automatically suspended. Otherwise, the review escalates to the next level.

**Q: Can I customize workflow steps?**
A: Yes. Workflows support custom steps including API calls, notifications, approvals, and conditional logic.

**Q: How does credential rotation work without downtime?**
A: The rotation process: 1) Generate new credential 2) Both old and new are valid for a grace period 3) Agent starts using new credential 4) Old credential is revoked after grace period.

**Q: Can I integrate workflows with my ticketing system (Jira, ServiceNow)?**
A: Webhook-based integration is supported. Workflows can POST to external endpoints on step completion. Native Jira/ServiceNow integration is on the roadmap.

**Q: How many concurrent workflows can run?**
A: No hard limit. Workflows are processed asynchronously via a worker queue. Performance depends on control plane resources.

### Advanced Setup Questions

**Q: Can I implement "The Reaper" — automatic decommission based on triggers?**
A: Yes. Create a workflow with event trigger: "If agent inactive for 90 days AND no sponsor response in 14 days → auto-decommission." This is the "Lifecycle Reaper" pattern.

**Q: How do access reviews work across tenants?**
A: Access reviews are scoped to a single tenant. A global admin can create reviews across tenants via the SaaS Admin App.

**Q: Can I enforce that all agents must pass an access review before activation?**
A: Yes. Set a governance policy requiring access review approval as a step in the onboarding workflow. Agents remain in `pending` state until approved.

**Q: How does the workflow engine handle failures?**
A: Steps have configurable retry logic and timeout. On failure, the workflow transitions to `failed` state and notifies the workflow owner. Manual intervention can resume from the failed step.

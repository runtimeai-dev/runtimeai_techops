# 07 — Agent Behavioral Intelligence & Drift Detection Guide

**Product**: Agent Behavioral Intel
**Audience**: Customer Security / ML Engineer
**API Base**: `https://api.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is Behavioral Intel?

Agent Behavioral Intel detects when AI agents deviate from expected behavior:

- **Drift Detection** — Identify when agent behavior diverges from baseline
- **Risk Scoring** — Dynamic 0–100 risk scores based on behavior
- **Anomaly Detection** — LSTM-based pattern analysis
- **Behavioral Analytics** — MCP-layer behavior tracking

---

## Setting Up Drift Detection on rt19

### Step 1: Establish Agent Baselines

Before detecting drift, you need a behavioral baseline for each agent.

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Create a behavioral baseline for an agent
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/baseline" \
  -H "Content-Type: application/json" \
  -d '{
    "observation_window_hours": 168,
    "metrics": {
      "avg_requests_per_hour": 50,
      "avg_response_time_ms": 200,
      "typical_tools_used": ["read_ticket", "update_ticket", "search_kb"],
      "typical_data_access": ["customer_records:read"],
      "typical_hours": ["08:00-18:00"],
      "avg_tokens_per_request": 500
    }
  }'
```

### Step 2: Configure Drift Policies

Define what constitutes "drift" and what action to take.

```bash
# Create drift detection policy
curl -sf -b "$COOKIE" -X POST "$API/api/drift/policies" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "standard-drift-policy",
    "description": "Detect behavioral anomalies for all production agents",
    "rules": [
      {
        "metric": "tools_used",
        "condition": "new_tool_not_in_baseline",
        "severity": "high",
        "action": "alert_and_flag"
      },
      {
        "metric": "request_volume",
        "condition": "exceeds_baseline_by_300_percent",
        "severity": "medium",
        "action": "alert"
      },
      {
        "metric": "operating_hours",
        "condition": "outside_baseline_hours",
        "severity": "medium",
        "action": "alert"
      },
      {
        "metric": "data_access_pattern",
        "condition": "new_data_source_accessed",
        "severity": "critical",
        "action": "quarantine"
      },
      {
        "metric": "error_rate",
        "condition": "exceeds_10_percent",
        "severity": "low",
        "action": "alert"
      }
    ],
    "applies_to": {"environment": "production"},
    "enabled": true
  }'
```

### Step 3: View Drift Findings

```bash
# List all drift detections
curl -sf -b "$COOKIE" "$API/api/drift/findings" | jq '.findings[] | {
  agent_name: .agent_name,
  drift_type: .drift_type,
  severity: .severity,
  detected_at: .detected_at,
  details: .details
}'

# Get drift findings for a specific agent
curl -sf -b "$COOKIE" "$API/api/drift/findings?agent_id=<agent_id>" | jq .

# Get drift trend over time
curl -sf -b "$COOKIE" "$API/api/drift/trends?period=30d" | jq .
```

### Step 4: Risk Score Configuration

```bash
# View current risk scores for all agents
curl -sf -b "$COOKIE" "$API/api/risk/dashboard" | jq '{
  high_risk_agents: .high_risk_count,
  medium_risk_agents: .medium_risk_count,
  low_risk_agents: .low_risk_count,
  average_risk_score: .avg_score
}'

# Get risk score breakdown for an agent
curl -sf -b "$COOKIE" "$API/api/agents/<agent_id>/risk" | jq '{
  overall_score: .score,
  components: {
    behavioral_drift: .behavioral_score,
    compliance_adherence: .compliance_score,
    credential_hygiene: .credential_score,
    access_pattern: .access_score
  }
}'
```

### Step 5: Set Up Anomaly Alerts

```bash
# Configure alert thresholds
curl -sf -b "$COOKIE" -X PUT "$API/api/drift/alerts" \
  -H "Content-Type: application/json" \
  -d '{
    "channels": {
      "email": ["security-team@acme-corp.com"],
      "slack_webhook": "https://hooks.slack.com/services/..."
    },
    "thresholds": {
      "risk_score_above": 70,
      "drift_severity": "medium",
      "new_tool_usage": true,
      "abnormal_hours": true
    }
  }'
```

---

## Understanding Risk Scores

| Score Range | Level | Meaning |
|-------------|-------|---------|
| 0–20 | 🟢 Low | Agent is well-behaved, all baselines met |
| 21–40 | 🟡 Moderate | Minor deviations, monitor closely |
| 41–60 | 🟠 Elevated | Significant drift, investigation recommended |
| 61–80 | 🔴 High | Major anomalies, restrict access |
| 81–100 | ⛔ Critical | Immediate action required, auto-quarantine |

Risk score components:
- **Behavioral Drift** (40% weight) — Deviation from established baselines
- **Compliance Adherence** (25% weight) — Policy violations and guardrail hits
- **Credential Hygiene** (20% weight) — Credential age, rotation status, unused perms
- **Access Pattern** (15% weight) — Data access outside normal patterns

---

## Drift Detection Dashboard

| Panel | Shows |
|-------|-------|
| **Drift Timeline** | Drift events over time (line chart) |
| **Risk Heatmap** | Agent risk scores as a heatmap |
| **Top Drifting Agents** | Agents with most drift events |
| **Anomaly Stream** | Real-time anomaly feed |
| **Behavioral Comparison** | Baseline vs. actual behavior |

---

## FAQ

**Q: How long does it take to establish a baseline?**
A: Default is 7 days (168 hours) of observation. For agents with consistent behavior, 3 days may suffice. High-risk agents should have 14-day baselines.

**Q: Can drift detection cause false positives?**
A: Yes, especially during initial deployment or after legitimate changes. Use `audit_only` mode for the first 2 weeks, then switch to enforcement.

**Q: What happens when an agent drifts?**
A: Depends on the policy action: `alert` (notify only), `alert_and_flag` (notify + mark agent), `restrict` (reduce permissions), `quarantine` (kill switch activation).

**Q: How is anomaly detection different from drift detection?**
A: Drift detection compares against a defined baseline. Anomaly detection uses LSTM neural networks to find patterns that are statistically unusual — it can detect novel threats that weren't anticipated in the baseline.

**Q: Can I manually adjust an agent's risk score?**
A: No. Risk scores are calculated automatically. You can influence them by: resolving drift findings, improving compliance, rotating credentials, and completing access reviews.

**Q: How do I handle legitimate behavior changes?**
A: Update the agent's baseline: `PUT /api/agents/<id>/baseline` with the new expected behavior. This resets drift tracking for that agent.

### Advanced Setup Questions

**Q: Does drift detection work across the MCP layer?**
A: Yes. The MCP Gateway tracks tool invocations and can detect when an agent starts using tools outside its baseline. This requires the MCP gateway to be integrated with the drift engine.

**Q: Can I use my own ML models for anomaly detection?**
A: Not yet. The built-in LSTM model is the only option. Custom model support is on the roadmap.

**Q: How does drift detection scale?**
A: Drift detection uses Redis for caching and batched analysis. It handles thousands of agents. The drift worker processes events asynchronously to avoid blocking the main API.

**Q: Can drift detection integrate with my SOAR platform?**
A: Drift events are part of the audit trail and can be exported to SIEM. Direct SOAR integration (auto-playbook execution) is on the roadmap.

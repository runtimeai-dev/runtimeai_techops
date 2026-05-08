# 06 — AI Firewall & Kill Switch Guide

**Product**: AI Firewall
**Audience**: Customer Security / SOC Analyst
**API Base**: `https://api.rt19.runtimeai.io`
**Dashboard**: `https://app.rt19.runtimeai.io`
**Last Updated**: 2026-03-17

---

## What Is the AI Firewall?

The AI Firewall provides runtime security for AI agents:

- **DLP Engine** — Real-time PII detection and redaction (SSN, credit cards, phone, etc.)
- **Egress Enforcement** — Control outbound agent connections
- **Kill Switch** — Emergency quarantine for compromised agents
- **Rate Limiting** — Burst protection for agent API calls
- **Tool-Level Blocking** — Granular MCP tool access control
- **WAF** — Web application firewall for bot mitigation

---

## Setting Up the Firewall on rt19

### Step 1: Configure DLP Rules

#### Via Dashboard
1. Navigate to **Firewall** → **DLP Configuration**
2. Enable detection patterns:
   - ✅ SSN (XXX-XX-XXXX)
   - ✅ Credit Card (Luhn validation)
   - ✅ Phone Number
   - ✅ IPv4 Address
   - ✅ AWS Access Keys
3. Set action: **Block** or **Redact**
4. Click **Save**

#### Via API

```bash
COOKIE="/tmp/acme_session.txt"
API="https://api.rt19.runtimeai.io"

# Configure DLP rules
curl -sf -b "$COOKIE" -X PUT "$API/api/firewall/dlp" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "rules": [
      {"pattern": "ssn", "action": "block", "description": "Social Security Numbers"},
      {"pattern": "credit_card", "action": "block", "description": "Credit Card Numbers"},
      {"pattern": "phone", "action": "redact", "description": "Phone Numbers"},
      {"pattern": "ipv4", "action": "redact", "description": "IP Addresses"},
      {"pattern": "aws_key", "action": "block", "description": "AWS Access Keys"}
    ],
    "scan_direction": "bidirectional"
  }'
```

### Step 2: Test DLP Enforcement

```bash
# Test SSN blocking — should be blocked
curl -sf -b "$COOKIE" -X POST "$API/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Customer SSN is 123-45-6789",
    "direction": "outbound"
  }'
# Expected: {"blocked": true, "reason": "ssn_detected", "pattern": "123-45-6789"}

# Test credit card blocking
curl -sf -b "$COOKIE" -X POST "$API/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Payment card: 4111111111111111",
    "direction": "outbound"
  }'
# Expected: {"blocked": true, "reason": "credit_card_detected"}

# Test clean content — should pass
curl -sf -b "$COOKIE" -X POST "$API/api/firewall/test" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Here is the quarterly report summary.",
    "direction": "outbound"
  }'
# Expected: {"blocked": false}
```

### Step 3: Kill Switch

The Kill Switch is an emergency mechanism to instantly quarantine a compromised agent.

#### Activate Kill Switch (Emergency)

```bash
# Activate kill switch for a specific agent
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/kill-switch" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "activate",
    "reason": "Suspicious data exfiltration detected",
    "severity": "critical",
    "notify": ["security-team@acme-corp.com"]
  }'
# Response: {"status": "quarantined", "effective_immediately": true}
```

What happens when kill switch is activated:
1. Agent is immediately marked as `quarantined`
2. All active sessions are terminated
3. All pending requests are rejected
4. Credentials are suspended (not revoked — can be restored)
5. Audit event is created with full context
6. Notifications sent to specified recipients

#### Verify Kill Switch

```bash
# Check agent status
curl -sf -b "$COOKIE" "$API/api/agents/<agent_id>" | jq '{status, quarantined, kill_switch_active}'

# Verify traffic is blocked (this should fail)
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/invoke" \
  -H "Content-Type: application/json" \
  -d '{"action": "test"}'
# Expected: 403 Forbidden — "Agent is quarantined"
```

#### Deactivate Kill Switch

```bash
curl -sf -b "$COOKIE" -X POST "$API/api/agents/<agent_id>/kill-switch" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "deactivate",
    "reason": "Investigation complete — false positive confirmed",
    "approved_by": "security-lead@acme-corp.com"
  }'
```

### Step 4: Rate Limiting

```bash
# Set rate limits for agent API calls
curl -sf -b "$COOKIE" -X PUT "$API/api/firewall/rate-limits" \
  -H "Content-Type: application/json" \
  -d '{
    "default_limits": {
      "requests_per_minute": 60,
      "requests_per_hour": 1000,
      "burst_size": 10
    },
    "per_agent_overrides": {
      "<high_traffic_agent_id>": {
        "requests_per_minute": 200,
        "requests_per_hour": 5000
      }
    }
  }'
```

### Step 5: Tool-Level Blocking

Block specific MCP tools for specific agents.

```bash
# Block an agent from using the "execute_sql" tool
curl -sf -b "$COOKIE" -X POST "$API/api/firewall/tool-blocks" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "<agent_id>",
    "blocked_tools": ["execute_sql", "delete_file", "send_email"],
    "reason": "Agent does not need database or file deletion access"
  }'
```

---

## Firewall Dashboard

| Panel | Shows |
|-------|-------|
| **DLP Events** | Real-time stream of blocked/redacted content |
| **Kill Switch Status** | Currently quarantined agents |
| **Rate Limit Hits** | Agents hitting rate limits |
| **Egress Violations** | Blocked outbound connections |
| **Tool Block Events** | Blocked tool invocations |

---

## Testing the Firewall

```bash
# Run the firewall test suite
./scripts/test_firewall_dlp.sh

# Expected output:
#   ✅ DLP: SSN blocked
#   ✅ DLP: Credit card blocked
#   ✅ DLP: Clean content passed
#   ✅ Kill switch: Activate
#   ✅ Kill switch: Verify quarantine
#   ✅ Kill switch: Deactivate
#   ✅ Kill switch: Verify restored
#   ✅ Rate limiting: Under limit
#   ✅ Rate limiting: Over limit blocked
```

---

## FAQ

**Q: Does DLP scanning add latency?**
A: Minimal. The DLP engine runs in-process with regex pattern matching. Typical overhead is <5ms per request. For data plane deployments, the Wasm sidecar runs DLP at sub-millisecond speeds.

**Q: Can I add custom DLP patterns?**
A: Yes. Add custom regex patterns to the DLP configuration: `{"pattern": "custom_regex", "regex": "ACME-\\d{8}", "action": "block"}`.

**Q: Is the kill switch reversible?**
A: Yes. Kill switch suspends (not revokes) credentials. Deactivation restores the agent to its pre-quarantine state. All kill switch actions are audited.

**Q: Who can activate the kill switch?**
A: Only users with `admin` or `operator` roles. The action is logged with the actor's identity.

**Q: Can I auto-activate the kill switch based on rules?**
A: Yes. Configure auto-quarantine rules: "If trust score drops below 20" or "If 3 DLP violations in 1 hour" → auto-activate kill switch.

**Q: How does the WAF work?**
A: The WAF (OpenResty-based) runs as a reverse proxy in front of agent endpoints. It blocks common attack patterns (SQLi, XSS, bot traffic). Requires data plane deployment.

### Advanced Setup Questions

**Q: Can I deploy the firewall as a sidecar?**
A: Yes. The Flow Enforcer (Envoy + Wasm) deploys as a sidecar or gateway. It enforces DLP, rate limits, and egress rules at the network level. This is a data plane component — see [gaps_issues.md](gaps_issues.md) for current deployment status.

**Q: How does the firewall handle encrypted traffic?**
A: The firewall operates at the application layer (L7), inspecting request/response bodies after TLS termination. It does not perform MITM on encrypted streams between agents and external services.

**Q: Can I integrate with my existing SIEM for firewall events?**
A: Yes. Firewall events are part of the audit trail, which can be exported to Splunk, Sentinel, or QRadar via the SIEM integration.

**Q: What's the difference between the control plane firewall and data plane firewall?**
A: Control plane firewall is API-based (policies, DLP rules, kill switch). Data plane firewall is the Flow Enforcer — a network-level proxy that enforces policies inline. Currently, rt19 only has the control plane firewall. See [gaps_issues.md](gaps_issues.md).

# AI Firewall & Kill Switch Guide

**Product**: AI Security | **Version**: 1.0.0

---

## AI Firewall
Real-time traffic inspection via Flow Enforcer (Envoy + Wasm) + WAF (OpenResty).

### Egress Policy Management

```bash
# Block AI vendor APIs
curl -X POST https://<YOUR_ENDPOINT>/api/policies/egress \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"destination": "*.openai.com", "action": "block", "category": "ai-vendor"}'

# Check policy decision
curl -X POST https://<YOUR_ENDPOINT>/api/policies/egress/check \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"destination": "api.openai.com"}'
# Response: {"decision": "BLOCKED", "matched_policy": "*.openai.com"}
```

## Kill Switch (< 50ms Latency)

```bash
# Activate (immediate via Redis pub/sub)
curl -X POST https://<YOUR_ENDPOINT>/api/kill-switch/activate \
  -H "X-RuntimeAI-Admin-Secret: <SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"scope": "agent", "target": "<AGENT_ID>", "reason": "Anomalous behavior", "duration": "1h"}'

# List active kill switches
curl https://<YOUR_ENDPOINT>/api/kill-switch/active

# Deactivate
curl -X POST https://<YOUR_ENDPOINT>/api/kill-switch/deactivate \
  -H "X-RuntimeAI-Admin-Secret: <SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"scope": "agent", "target": "<AGENT_ID>"}'
```

## On-Prem Notes
- Kill Switch uses Redis pub/sub for sub-50ms propagation
- Flow Enforcer must be deployed as a sidecar for agent traffic interception
- WAF rules are configurable via OpenResty Lua scripts

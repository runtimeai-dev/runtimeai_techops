# Scanner 02: Slack (Simulation)
**Date**: 2026-03-27 | **Tenant**: equinix-test | **Result**: ✅ PASS

## Setup
- **Endpoint**: `POST /simulate/slack_scan?tenant_id=equinix-test`
- **Auth**: `X-API-Key: <API_KEY_SECRET>`
- **No external dependencies** — built-in simulation

## Test Execution
```bash
curl -s -X POST "http://discovery:8090/simulate/slack_scan?tenant_id=equinix-test" \
  -H "X-API-Key: $API_KEY_SECRET"
```

### Response
```json
{
    "status": "ingested",
    "scan_id": "120ff8c0-51fc-48af-8794-ed7a5882ff1b",
    "agents_processed": 3
}
```

## Agents Discovered
| Agent | Fingerprint | Risk Score | Capabilities |
|-------|------------|------------|-------------|
| DailyStandupBot | `slack:app:DailyStandupBot` | 10 | send_message, read_channels |
| JiraIntegration | `slack:app:JiraIntegration` | 10 | send_message, read_channels |
| PagerDuty | `slack:app:PagerDuty` | 10 | send_message, read_channels |

## Validation
✅ 3 agents present in DB with `slack:app:*` fingerprints

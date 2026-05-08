# Scanner 03: Network Traffic (Shadow AI Detection)
**Date**: 2026-03-27 | **Tenant**: equinix-test | **Result**: ❌ FAIL (DB constraint)

## Setup
- **Endpoint**: `POST /simulate/network_traffic?tenant_id=equinix-test`
- **Auth**: `X-API-Key: <API_KEY_SECRET>`
- **Purpose**: Detect shadow AI usage by analyzing network traffic patterns

## Test Execution
```bash
curl -s -X POST "http://discovery:8090/simulate/network_traffic?tenant_id=equinix-test" \
  -H "X-API-Key: $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '[
    {"domain": "api.openai.com", "path": "/v1/chat/completions", "method": "POST"},
    {"domain": "api.anthropic.com", "path": "/v1/messages", "method": "POST"},
    {"domain": "huggingface.co", "path": "/api/models", "method": "GET"}
  ]'
```

### Response
```
Internal Server Error
```

## Root Cause
```
psycopg.errors.CheckViolation: new row for relation "discovery_findings" violates check constraint "discovery_findings_severity_check"
```

The `discovery_findings` table has `CHECK (lower(severity) IN ('critical','high','medium','low','info'))` but `app.py` line 742 sends uppercase `'HIGH'`:
```python
severity="HIGH" if f.risk_score > 70 else "MEDIUM"
```

## Fix Required
**Option A** (recommended): Update `app.py` to send lowercase severity:
```python
severity="high" if f.risk_score > 70 else "medium"
```

**Option B**: Relax the CHECK constraint:
```sql
ALTER TABLE discovery_findings DROP CONSTRAINT discovery_findings_severity_check;
ALTER TABLE discovery_findings ADD CONSTRAINT discovery_findings_severity_check
  CHECK (lower(severity) = ANY (ARRAY['critical','high','medium','low','info']));
```

## What It Tests
- Shadow AI detection via DNS/network traffic analysis
- Signature matching against AI vendor domains (OpenAI, Anthropic, HuggingFace, etc.)
- Risk scoring based on traffic patterns
- Shadow AI inbox (`/v1/discovery/inbox`)

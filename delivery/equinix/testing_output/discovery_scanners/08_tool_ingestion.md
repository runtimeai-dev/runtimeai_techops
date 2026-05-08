# Scanner 08: Tool Ingestion
**Date**: 2026-03-27 | **Tenant**: equinix-test | **Result**: ✅ PASS

## Setup
- **Endpoint**: `POST /v1/discovery/ingest/tool`
- **Auth**: `X-API-Key: <API_KEY_SECRET>`
- **Purpose**: Register external tools in the system inventory

## Test Execution
```bash
curl -s -X POST "http://discovery:8090/v1/discovery/ingest/tool" \
  -H "X-API-Key: $API_KEY_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "tenant_id": "equinix-test",
    "tool_uri": "https://api.openai.com/v1",
    "name": "OpenAI API",
    "capabilities": ["chat", "embeddings"],
    "risk_tier": "HIGH",
    "owner": "data-team",
    "prod_ok": false
  }'
```

### Response
```json
{
    "status": "ingested",
    "tool_id": "openai-api"
}
```

## Validation
```bash
curl -s "http://discovery:8090/v1/inventory/tools?tenant_id=equinix-test" \
  -H "X-API-Key: $API_KEY_SECRET"
```
✅ Tool `openai-api` present with `risk_tier: HIGH`, `prod_ok: false`

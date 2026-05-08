# Scanner 04: Advanced Scan (DNS + Process + OAuth)
**Date**: 2026-03-27 | **Tenant**: equinix-test | **Result**: ❌ FAIL (same DB constraint)

## Setup
- **Endpoint**: `POST /v1/discovery/scan/advanced?tenant_id=equinix-test`
- **Auth**: `X-API-Key: <API_KEY_SECRET>`
- **Purpose**: Triggers 3 sub-scanners simultaneously:
  1. **DNS Scanner** — scans DNS logs for AI domain queries
  2. **Process Scanner** — detects local AI processes (ollama, lm-studio)
  3. **OAuth Scanner** — discovers OAuth grants across IdPs (mock mode)

## Test Execution
```bash
curl -s -X POST "http://discovery:8090/v1/discovery/scan/advanced?tenant_id=equinix-test" \
  -H "X-API-Key: $API_KEY_SECRET"
```

### Expected Response (after fix)
```json
{
    "status": "completed",
    "scanners_run": 3,
    "total_items_found": 5
}
```

### Actual Response
```
Internal Server Error
```

## Root Cause
Same as Scanner 03: `discovery_findings.severity` CHECK constraint expects lowercase, but app.py sends uppercase `'HIGH'` / `'MEDIUM'`.

## Sub-Scanners Detail

### DNS Scanner (`scanners/dns_scanner.py`)
- Reads DNS log files for AI domain queries
- Known AI domains: `api.openai.com`, `anthropic.com`, `huggingface.co`, `midjourney.com`
- Falls back to simulated data if no log file found

### Process Scanner (`scanners/process_scanner.py`)
- Detects local AI processes: `ollama` (risk 90), `lm-studio` (risk 85), `python3 model.py` (risk 50)
- In container mode, defaults to mock process list

### OAuth Scanner (`scanners/oauth_scanner.py`)
- Supports 6 IdP connectors: Okta, Azure AD, Google, AWS SSO, Oracle OCI, MCP Gateway
- Defaults to `DISCOVERY_USE_MOCK=true` → returns realistic mock data
- For real scanning: configure IdP connector settings via control-plane API

## Fix Required
Update `app.py` lines 742, 748 to use lowercase severity values.

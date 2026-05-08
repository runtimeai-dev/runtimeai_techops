# Scanner 01: GitHub (Simulation)
**Date**: 2026-03-27 | **Tenant**: equinix-test | **Result**: ✅ PASS

## Setup
- **Endpoint**: `POST /simulate/github_scan?tenant_id=equinix-test&count=5`
- **Auth**: `X-API-Key: <API_KEY_SECRET>` (from K8s secret or vault)
- **No external dependencies** — built-in simulation

## Test Execution
```bash
curl -s -X POST "http://discovery:8090/simulate/github_scan?tenant_id=equinix-test&count=5" \
  -H "X-API-Key: $API_KEY_SECRET"
```

### Response
```json
{
    "status": "ingested",
    "scan_id": "c146295d-b89a-4b7e-9421-302ba76982cd",
    "agents_processed": 5
}
```

## Agents Discovered
| Agent | Fingerprint | Risk Score |
|-------|------------|------------|
| RepoAgent-1 | `github:repo:RepoAgent-1` | 90 |
| RepoAgent-2 | `github:repo:RepoAgent-2` | 37 |
| RepoAgent-3 | `github:repo:RepoAgent-3` | 48 |
| RepoAgent-4 | `github:repo:RepoAgent-4` | 92 |
| RepoAgent-5 | `github:repo:RepoAgent-5` | 68 |

## Validation
```bash
curl -s "http://discovery:8090/v1/inventory/discovered?tenant_id=equinix-test" \
  -H "X-API-Key: $API_KEY_SECRET" | jq '.agents[] | select(.fingerprint | startswith("github:"))'
```
✅ 5 agents present in DB with correct fingerprints and risk scores

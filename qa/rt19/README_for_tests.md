# QA & Automation Testing

This directory contains consolidated test scripts and artifacts for validating the RuntimeAI platform.

## Test Structure

| Script | Description |
|--------|-------------|
| `01_backend_api_tests.sh` | verify core API endpoints (Drift, Policy, Inventory) using `curl`. |
| `02_discovery_tests.sh` | Run discovery scanners (VSCode, Cloud, Repo) to populate inventory. |
| `03_demo_validation.sh` | End-to-end validation of the primary demo workflow. |
| `04_budget_test.sh` | Simulate high spend and verify budget caps (429 Too Many Requests). |
| `05_reaper_test.sh` | Verify Lifecycle Management (Agent Revocation via HRIS signal). |
| `06_dns_test.sh` | Verify Identity DNS resolution and forwarding. |

## How to Run

### Prerequisites
- Docker environment must be running: `cd ../deployment/docker-compose && docker compose up -d`
- `jq` and `curl` must be installed.
- Python 3 with dependencies (for scanners) must be available.

### Running Tests

```bash
# 1. Backend Verification
./01_backend_api_tests.sh

# 2. Discovery Scanners
./02_discovery_tests.sh

# 3. Full Demo Walkthrough Validation
./03_demo_validation.sh

# 4. Cost Containment (Budget)
./04_budget_test.sh

# 5. Lifecycle Management (Reaper)
./05_reaper_test.sh

# 6. Identity DNS
./06_dns_test.sh
```

## Stability & Reliability
To maintain 100% pass rates, observe these rules:
1. **Rate Limit Cleanup**: Ensure Test 08 cleans up Redis keys. If running manual tests, you may need to run:
   `docker exec docker-compose-redis-1 redis-cli FLUSHALL`
2. **Wasm Integrity**: After any change to `flow-enforcer/wasm/main.go`, rebuild and restart the service. Verify the `contextID` initialization to prevent request hangups.
3. **Python Environment**: Always use the `.venv` created in the repo root to run scanners. Ensure `requests` is installed.
4. **Service Readiness**: Wait for containers to be `Healthy` before running the suite.

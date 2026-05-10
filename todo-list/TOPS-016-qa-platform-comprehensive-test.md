# TOPS-016: QA Test Suite — Platform-Level Comprehensive Tests

## Specification

Create comprehensive platform-level test suite (`qa/platform/run_platform_suite.sh`) validating all internal APIs, service integrations, and cross-service communication across rt19 environment.

Tests cover:
- Service discovery and health checks (all 31 services responding)
- Inter-service communication (gRPC, REST)
- Database connectivity and schema validation
- Cache (Redis) connectivity and key expiry
- Secret injection from QuantumVault (verify secrets mounted)
- Logging and observability (Prometheus metrics available, Grafana dashboards render)
- Multi-tenancy (RLS policies enforced, no data leakage)
- Load testing (concurrent requests, rate limiting)
- Backup/restore integration (data persistence, snapshot verification)

## Acceptance Criteria

- [ ] Script created at `qa/platform/run_platform_suite.sh`
- [ ] Supports: --env=rt19 (primary), --verbose, --filter=<pattern>, --load-test
- [ ] Test discovery: find `qa/platform/tests/*.sh` and execute in order
- [ ] Service health checks: curl each service on its health endpoint
- [ ] Validates all 31 services return 200 OK
- [ ] Tests inter-service communication (e.g., control-plane calls cost-ledger)
- [ ] Database tests: connect to PostgreSQL, validate schema, run sample queries
- [ ] Redis tests: connect, set/get keys, test TTL expiry
- [ ] QuantumVault tests: call /api/v1/health, decrypt sample secret
- [ ] Metrics validation: scrape Prometheus, verify service metrics present
- [ ] Tenant isolation: create 2 tenants, verify data not visible across tenants
- [ ] Load test (optional): 100 concurrent requests, measure p99 latency
- [ ] All tests have timeout (30s default)
- [ ] Generates detailed report with service-by-service results
- [ ] Committed to feature branch `TOPS-016-qa-platform-comprehensive-test`

## Effort Estimate

4 hours

## Dependencies

Blocked by: TOPS-001 through TOPS-008 (infra must be deployed), TOPS-015 (customer tests)
Blocks: Production deployment

## Implementation Notes

- Service discovery from K8s API (kubectl get services -n rt19)
- Health check endpoint: each service should respond to `/health` on its port
- Database tests use connection string from Terraform outputs
- Redis tests use endpoint from K8s ConfigMap or env var
- QuantumVault tests use admin token from K8s secret
- Metrics scraped from Prometheus on port 9090
- Tenant isolation tests use admin impersonation to create test tenants
- Load test uses Apache Bench (ab) or similar tool
- Report saved to `/tmp/platform-test-results-<timestamp>.txt`

## Verification

```bash
cd qa/platform
bash run_platform_suite.sh --env=rt19 --verbose
# Check detailed results
tail -50 /tmp/platform-test-results-*.txt
# Run load test (optional)
bash run_platform_suite.sh --env=rt19 --load-test
```

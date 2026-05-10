# TOPS-015: QA Test Runner — Customer-Facing Tests

## Specification

Create comprehensive QA test runner (`qa/customer/run_customer_suite.sh`) validating all customer-visible features across environments (rt19, rt01, rt02, pqdata, runtimecrm).

Tests cover:
- Authentication flow (login, MFA, token refresh)
- Dashboard UI rendering and API responses
- Core workflows (data import, processing, export)
- API rate limiting and error handling
- Multi-tenant isolation (tenant_id enforcement in responses)
- Permission enforcement (RBAC, row-level security)

## Acceptance Criteria

- [ ] Script created at `qa/customer/run_customer_suite.sh`
- [ ] Supports arguments: --env=<rt19|rt01|rt02|pqdata>, --verbose, --filter=<pattern>
- [ ] Test discovery: find `qa/customer/tests/*.sh` and execute in order
- [ ] Color-coded output (green=pass, red=fail, yellow=skip)
- [ ] Generates summary report with passed/failed counts
- [ ] Supports --stop-on-fail (exit on first failure)
- [ ] Each test validates: HTTP status code, JSON schema, response content
- [ ] Tests use environment variable BASE_URL (not hardcoded domain)
- [ ] Auth flow: uses admin impersonation for rt19 (X-RuntimeAI-Admin-Secret header), OAuth for prod
- [ ] Creates seed data (test accounts, test data) before running tests
- [ ] Cleans up test data after tests complete (idempotent)
- [ ] Committed to feature branch `TOPS-015-qa-customer-test-runner`

## Effort Estimate

3 hours

## Dependencies

Blocked by: TOPS-001 through TOPS-008 (infra must be deployed first)
Blocks: TOPS-016 (platform-level QA)

## Implementation Notes

- Tests run serially (not parallel) to avoid race conditions
- Each test script should be independent (can run in any order)
- Base URL from environment variable: BASE_URL (e.g., https://app.rt19.runtimeai.io)
- Admin secret for rt19: ADMIN_SECRET from K8s secret or env var
- Seed data stored in files or database (not hardcoded in test scripts)
- Tests should timeout after 30s per test (use `timeout 30` command)
- All API responses validated against JSON schema (use `jq` for validation)

## Verification

```bash
cd qa/customer
bash run_customer_suite.sh --env=rt19 --verbose
# Check summary report
tail -20 /tmp/qa-test-results-*.txt
```

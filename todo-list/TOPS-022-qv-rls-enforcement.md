# TOPS-022: QuantumVault RLS (Row-Level Security) Enforcement

## Specification

Implement and validate Row-Level Security (RLS) policies for QuantumVault multi-tenancy:
- Ensure tenant_id filtering on all secret queries (no cross-tenant data leakage)
- Validate database RLS policies (PostgreSQL native RLS)
- Test RLS enforcement with multiple tenants (verify isolation)
- Audit RLS policy violations (log all queries that bypass RLS)
- Document RLS architecture and maintenance procedures

## Acceptance Criteria

- [ ] RLS policies created for all QuantumVault tables:
  - [ ] secrets table: RLS policy on tenant_id
  - [ ] audit_logs table: RLS policy on tenant_id
  - [ ] key_versions table: RLS policy on tenant_id
  - [ ] rotation_history table: RLS policy on tenant_id
- [ ] Database role setup: runtimeai_qv_app (application role with SET ROLE enforced)
- [ ] Each query wrapped with: BEGIN; SET ROLE runtimeai_qv_<tenant_id>; [query]; RESET ROLE; COMMIT;
- [ ] RLS validation tests: attempt cross-tenant access, verify denied
- [ ] RLS audit: all unauthorized access attempts logged (log with tenant_id, user_id, timestamp)
- [ ] Documentation: RLS architecture diagram, test results, troubleshooting guide
- [ ] Committed to feature branch `TOPS-022-qv-rls-enforcement`

## Effort Estimate

2 hours

## Dependencies

Blocked by: TOPS-017 (QV init), TOPS-020 (secret creation)
Blocks: Production deployment, compliance validation

## Implementation Notes

- RLS is native PostgreSQL feature (policies per table, applied at query time)
- SET ROLE approach preferred over row-filtering application code (defense in depth)
- RLS policies enforce: tenant_id matches current session role
- Invalid role names cause queries to silently return 0 rows (critical to test!)
- RLS violations are logged but should NOT crash application (graceful degradation)
- All developer queries must use proper SET ROLE (test with grep for hardcoded query strings)
- RLS cannot prevent admin from accessing all data (by design; admins use separate role)

## Verification

```bash
# Connect to QV database
psql -h $RDS_ENDPOINT -U $RDS_USER -d quantumvault

# Check RLS policies
SELECT schemaname, tablename, policyname, permissive 
FROM pg_policies 
WHERE tablename LIKE 'secrets%' OR tablename LIKE 'audit%';

# Test RLS enforcement
BEGIN;
SET ROLE runtimeai_qv_rt19;
SELECT COUNT(*) FROM secrets;  -- Should return only rt19 secrets
SELECT COUNT(*) FROM secrets WHERE tenant_id = 'rt01';  -- Should return 0
RESET ROLE;
COMMIT;

# Test cross-tenant access attempt
BEGIN;
SET ROLE runtimeai_qv_rt01;
SELECT COUNT(*) FROM secrets WHERE tenant_id = 'rt19';  -- Should return 0
RESET ROLE;
COMMIT;
```

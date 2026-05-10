# TOPS-018: QuantumVault Key Rotation

## Specification

Implement QuantumVault key rotation script (`scripts/secrets/quantumvault-rotate-keys.sh`) for:
- Rotating master key (scheduled monthly)
- Rotating tenant-specific keys (scheduled quarterly)
- Creating new key versions while maintaining backward compatibility
- Re-encrypting secrets with new keys (zero-downtime migration)
- Audit logging of all key rotations

## Acceptance Criteria

- [ ] Script created at `scripts/secrets/quantumvault-rotate-keys.sh`
- [ ] Arguments: --key-type=<master|tenant>, --tenant=<tenant-id>, --dry-run
- [ ] Supports --schedule for automated rotation (cron integration)
- [ ] Pre-rotation validation: verify current key is healthy, QV API responsive
- [ ] Rotation process: generate new key, update secret references, verify decryption with new key
- [ ] Post-rotation: disable old key (don't delete), test fallback scenarios
- [ ] Re-encryption: re-wrap all secrets with new key (background job)
- [ ] Rollback plan: if rotation fails, automatically revert to previous key
- [ ] Audit trail: log key_id, rotation_timestamp, admin_name, status
- [ ] Zero downtime: new key is active before old key is removed
- [ ] Committed to feature branch `TOPS-018-qv-key-rotation`

## Effort Estimate

3 hours

## Dependencies

Blocked by: TOPS-017 (master key init), TOPS-020 (secret creation)
Blocks: TOPS-023 (security operations automation)

## Implementation Notes

- Master key rotation is ceremony-based (manual with 2-of-3 shards)
- Tenant key rotation is automated (scheduled via cron)
- New key version must be tested with sample secret before full rotation
- Old key kept for backward compatibility (in case of missed secret)
- Re-encryption is background job (may take hours for large deployments)
- Audit log format: JSON (compatible with ELK ingestion)
- Rollback can use QV API to mark old key as active again

## Verification

```bash
cd scripts/secrets
bash quantumvault-rotate-keys.sh --key-type=tenant --tenant=rt19 --dry-run
# Verify audit log entry
tail -1 audit_qv_rotations.json | jq '.'
# Test with real key (non-production first)
bash quantumvault-rotate-keys.sh --key-type=tenant --tenant=rt19
```

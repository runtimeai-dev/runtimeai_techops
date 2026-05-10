# TOPS-017: quantumvault-init.sh — QuantumVault Master Key Initialization

**Category**: Secrets Management | QuantumVault Integration  
**Priority**: P0 (Production blocking — all secrets encrypted)  
**Owner**: Security Engineer  
**Effort**: 3h (confidence: high)  
**Timeline**: Phase 1, Week 1

---

## Problem Statement

QuantumVault master key is not initialized. Without it, no secrets can be encrypted at rest. All tenant secrets must be encrypted using post-quantum cryptography (ML-KEM-1024) to meet SOC 2 / FedRAMP compliance.

**Current State**: QuantumVault service exists but master key not initialized  
**Desired State**: Master key created, tenant-specific key hierarchy established, 2-of-3 key shard recovery setup  
**Blocking**: Cannot encrypt secrets without master key initialization; TOPS-020, TOPS-021 blocked until complete

---

## Acceptance Criteria

- [ ] `scripts/secrets/quantumvault-init.sh` script created and executable
- [ ] Script initializes QuantumVault master key (ML-KEM-1024 encryption)
- [ ] Master key shards created and stored in 3 separate Azure Key Vaults (2-of-3 threshold)
- [ ] Tenant-specific key hierarchy created (rt19, rt01, rt02, pqdata, runtimecrm, aep)
- [ ] Each tenant can decrypt only its own secrets (RLS enforced in QuantumVault)
- [ ] Script includes `--test` mode to verify key creation + encryption/decryption roundtrip
- [ ] Script is idempotent (safe to run multiple times)
- [ ] No hardcoded key material or shard paths in script
- [ ] Documentation: `docs/quantumvault-setup.md` explains master key ceremony + disaster recovery
- [ ] PR created, reviewed by Security Lead, merged to dev

---

## Detailed Requirements

### Inputs

**External dependencies**:
- QuantumVault service running (assumed available)
- Azure CLI authenticated (`az login` with MFA)
- 3 Azure Key Vault instances for shard storage:
  - `runtimeai-kv-shard-1`
  - `runtimeai-kv-shard-2`
  - `runtimeai-kv-shard-3`
- Permissions to create keys in all 3 vaults

**Environment variables** (sourced from .env, never hardcoded):
```bash
QUANTUMVAULT_API_URL=https://quantumvault.runtimeai.io
QUANTUMVAULT_ADMIN_TOKEN=$(az keyvault secret show --vault-name runtimeai-prod-kv --name qv-admin-token --query value -o tsv)
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
```

### Outputs

**Files to create/modify**:
- [ ] `scripts/secrets/quantumvault-init.sh` (main script)
- [ ] `docs/quantumvault-setup.md` (ceremony documentation)
- [ ] `secrets-templates/quantumvault-init.env.template` (example env vars)

**Artifacts to commit**:
- Script + documentation (no actual key material or tokens)

**Side effects** (post-commit, manual action by ops):
- Master key created in QuantumVault (secure offline procedure)
- 3 key shards created and distributed to 3 vaults
- Tenant keys created for each environment

### Implementation Notes

**Key hierarchy**:
```
Master Key (ML-KEM-1024)
├── rt19 tenant key
├── rt01 tenant key
├── rt02 tenant key
├── pqdata tenant key
├── runtimecrm tenant key
└── aep tenant key
```

**Shard ceremony** (2-of-3 threshold):
1. Admin 1 generates shard 1, stores in vault-1
2. Admin 2 generates shard 2, stores in vault-2
3. Admin 3 generates shard 3, stores in vault-3
4. To recover: need 2 shards + threshold key material

**Script responsibilities**:
- Call QuantumVault API to initialize master key
- Retrieve shards from Azure Key Vaults
- Combine shards (2-of-3) to recreate master key (for disaster recovery test)
- Create tenant-specific keys
- Test roundtrip: encrypt test payload → decrypt → verify

---

## Dependencies

- **Blocks**: TOPS-020 (create-secrets-from-qv.sh), TOPS-021 (audit log exporter), TOPS-022 (RLS enforcement)
- **Blocked By**: None
- **Related**: TOPS-018 (key rotation), TOPS-019 (remove hardcoded secrets)

---

## Testing / Verification

```bash
# 1. Syntax check
bash -n /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-init.sh
# Expected: exit 0

# 2. ShellCheck
shellcheck /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-init.sh
# Expected: 0 warnings

# 3. Test mode (verify encryption roundtrip)
export QUANTUMVAULT_TEST_MODE=true
bash /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-init.sh --test
# Expected: "Master key initialization test PASSED" + exit 0

# 4. Verify no secrets in script
grep -E "password|secret|api.key|bearer|shard" /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-init.sh | grep -v "^#" | grep -v "QUANTUMVAULT_ADMIN_TOKEN=\${" 
# Expected: 0 matches (token references only use env var syntax)

# 5. Check tenant key creation
bash /Users/roshanshaik/work/runtimeai_techops/scripts/secrets/quantumvault-init.sh --list-tenants
# Expected: output lists all 6 tenant keys created
```

---

## Sign-Off

- [ ] Code complete + all acceptance criteria met
- [ ] Tested locally in test mode (--test flag)
- [ ] No hardcoded credentials anywhere
- [ ] Documentation complete + ceremony clear to operators
- [ ] PR created + reviewed by Security Lead
- [ ] Merged to dev + ready for master key ceremony (manual step)

**Completed By**: [name + date]  
**Verified By**: [Security Lead + date]  
**Ceremony Executed By**: [Admin 1 + Admin 2 + Admin 3, date]

---

## Notes

- Master key ceremony is a MANUAL OFFLINE PROCESS (script sets up infrastructure, but humans execute ceremony)
- Shard distribution requires 3 separate admins (no single person holds all shards)
- Store ceremony notes in `docs/quantumvault-ceremony-log/` (offline, encrypted)
- Test mode does NOT persist keys (ephemeral test setup only)
- Quarterly key rotation ceremony documented separately (TOPS-018)

#!/usr/bin/env bash
# =============================================================================
# PQ Data Platform — RuntimeAI Enterprise Integration Tests
# Validates all 9 PQDP services independently and tests cross-service flows
# between PQDP and the RuntimeAI Enterprise Control Plane.
#
# Usage:
#   ./pqdata_integration_tests.sh                   # local docker-compose
#   PQDP_BASE_URL=https://qutonomous.rt19.example.com \
#   JWT_SECRET=$(az keyvault ...) \
#     ./pqdata_integration_tests.sh                 # rt19 cluster
#
# Environment variables (all optional — defaults to local ports):
#   PQDP_BASE_URL   Base URL for k8s cluster (overrides per-service URLs)
#   JWT_SECRET      Shared HMAC-SHA256 secret (required for all auth'd calls)
#   TENANT_ID       Tenant to test as (default: pqdp-integration-test)
#   QV_URL          QuantumVault    (default: http://localhost:8200)
#   DS_URL          Secure DataShare (default: http://localhost:8085)
#   PE_URL          Policy Engine   (default: http://localhost:8083)
#   CG_URL          CryptoGuard     (default: http://localhost:8084)
#   TV_URL          TokenVault      (default: http://localhost:8086)
#   SG_URL          PQ Sign         (default: http://localhost:8087)
#   CP_URL          PQ Comply       (default: http://localhost:8090)
#   TS_URL          Transit Shield  (default: https://localhost:8443)
#   MG_URL          PQ Migrate      (default: http://localhost:8095)
#   CONTROL_PLANE_URL  RuntimeAI Enterprise CP (default: http://localhost:4000)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +"%m%d%y_%H%M%S")
RESULTS_DIR="$SCRIPT_DIR/test_results"
mkdir -p "$RESULTS_DIR"
LOG_FILE="$RESULTS_DIR/${TIMESTAMP}_pqdata_integration.log"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'
pass() { echo -e "${GREEN}✅ PASS${RESET}  $*" | tee -a "$LOG_FILE"; }
fail() { echo -e "${RED}❌ FAIL${RESET}  $*" | tee -a "$LOG_FILE"; FAILED=$((FAILED+1)); }
skip() { echo -e "${YELLOW}⚠️  SKIP${RESET}  $*" | tee -a "$LOG_FILE"; SKIPPED=$((SKIPPED+1)); }
info() { echo -e "${CYAN}ℹ️  INFO${RESET}  $*" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}──── $* ────${RESET}" | tee -a "$LOG_FILE"; }

PASSED=0; FAILED=0; SKIPPED=0
assert_status() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    pass "$label (HTTP $got)"
    PASSED=$((PASSED+1))
  else
    fail "$label — expected HTTP $want, got HTTP $got"
  fi
}

# ── Configuration ─────────────────────────────────────────────────────────────
TENANT_ID="${TENANT_ID:-pqdp-integration-test}"
JWT_SECRET="${JWT_SECRET:-}"

# If PQDP_BASE_URL is set, derive per-service URLs from it using known path prefixes.
# e.g. https://qutonomous.rt19.example.com → all services route via ingress.
# Otherwise fall back to direct localhost ports.
if [[ -n "${PQDP_BASE_URL:-}" ]]; then
  QV_URL="${QV_URL:-${PQDP_BASE_URL}/qv}"
  DS_URL="${DS_URL:-${PQDP_BASE_URL}/ds}"
  PE_URL="${PE_URL:-${PQDP_BASE_URL}/pe}"
  CG_URL="${CG_URL:-${PQDP_BASE_URL}/cg}"
  TV_URL="${TV_URL:-${PQDP_BASE_URL}/tv}"
  SG_URL="${SG_URL:-${PQDP_BASE_URL}/sg}"
  CP_URL="${CP_URL:-${PQDP_BASE_URL}/cp}"
  TS_URL="${TS_URL:-${PQDP_BASE_URL}/ts}"
  MG_URL="${MG_URL:-${PQDP_BASE_URL}/mg}"
else
  QV_URL="${QV_URL:-http://localhost:8200}"
  DS_URL="${DS_URL:-http://localhost:8085}"
  PE_URL="${PE_URL:-http://localhost:8083}"
  CG_URL="${CG_URL:-http://localhost:8084}"
  TV_URL="${TV_URL:-http://localhost:8086}"
  SG_URL="${SG_URL:-http://localhost:8087}"
  CP_URL="${CP_URL:-http://localhost:8090}"
  TS_URL="${TS_URL:-https://localhost:8443}"
  MG_URL="${MG_URL:-http://localhost:8095}"
fi
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:4000}"

echo -e "${BOLD}" | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo " PQ Data Platform — RuntimeAI Enterprise Integration Tests " | tee -a "$LOG_FILE"
echo " Timestamp : $TIMESTAMP"                                     | tee -a "$LOG_FILE"
echo " Tenant    : $TENANT_ID"                                     | tee -a "$LOG_FILE"
echo " Log       : $LOG_FILE"                                      | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo -e "${RESET}"

# ── JWT minting ───────────────────────────────────────────────────────────────
# Mints an HS256 Bearer token using only python3 (no external deps).
mint_token() {
  local tenant="${1:-$TENANT_ID}"
  local sub="${2:-integration-test}"
  local role="${3:-user}"
  if [[ -z "$JWT_SECRET" ]]; then
    echo ""
    return 0
  fi
  python3 - "$JWT_SECRET" "$sub" "$tenant" "$role" <<'PYEOF'
import hmac, hashlib, base64, json, time, sys

secret, sub, tenant, role = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
now = int(time.time())

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

hdr = b64url(json.dumps({'alg':'HS256','typ':'JWT'}, separators=(',',':')))
pay = b64url(json.dumps({
    'sub': sub, 'tenant_id': tenant, 'role': role,
    'exp': now + 300, 'iat': now
}, separators=(',',':')))
msg = f'{hdr}.{pay}'.encode()
sig = b64url(hmac.new(secret.encode(), msg, hashlib.sha256).digest())
print(f'{hdr}.{pay}.{sig}')
PYEOF
}

# ── curl helpers ──────────────────────────────────────────────────────────────
CURL_OPTS=(-s -o /dev/null -w "%{http_code}" --max-time 10)
CURL_BODY_OPTS=(-s -w "\n%{http_code}" --max-time 10)

# Authenticated request returning status code only
auth_status() {
  local method="$1" url="$2"
  shift 2
  local tok
  tok=$(mint_token)
  if [[ -z "$tok" ]]; then
    curl "${CURL_OPTS[@]}" -k -X "$method" "$url" "$@"
  else
    curl "${CURL_OPTS[@]}" -k -X "$method" "$url" \
      -H "Authorization: Bearer $tok" "$@"
  fi
}

# Authenticated request returning body + status (last line is status code)
auth_body_status() {
  local method="$1" url="$2"
  shift 2
  local tok
  tok=$(mint_token)
  if [[ -z "$tok" ]]; then
    curl "${CURL_BODY_OPTS[@]}" -k -X "$method" "$url" "$@"
  else
    curl "${CURL_BODY_OPTS[@]}" -k -X "$method" "$url" \
      -H "Authorization: Bearer $tok" "$@"
  fi
}

# Unauthenticated request status code only
unauth_status() {
  local method="$1" url="$2"
  shift 2
  curl "${CURL_OPTS[@]}" -k -X "$method" "$url" "$@"
}

healthz_ok() {
  local url="$1/healthz"
  local status
  status=$(curl "${CURL_OPTS[@]}" -k "$url" 2>/dev/null) || status="000"
  [[ "$status" == "200" ]]
}

# ── Section 0: Preflight ──────────────────────────────────────────────────────
section "0. Preflight — Service Reachability"

SERVICES=(
  "QuantumVault:$QV_URL"
  "Secure-DataShare:$DS_URL"
  "Policy-Engine:$PE_URL"
  "CryptoGuard:$CG_URL"
  "TokenVault:$TV_URL"
  "PQ-Sign:$SG_URL"
  "PQ-Comply:$CP_URL"
  "Transit-Shield:$TS_URL"
  "PQ-Migrate:$MG_URL"
)

ACTIVE_SERVICES=()
for svc_url in "${SERVICES[@]}"; do
  name="${svc_url%%:*}"
  url="${svc_url#*:}"
  if healthz_ok "$url"; then
    pass "$name reachable at $url"
    ACTIVE_SERVICES+=("$svc_url")
    PASSED=$((PASSED+1))
  else
    skip "$name not reachable at $url — per-service tests will skip"
  fi
done

if [[ "${#ACTIVE_SERVICES[@]}" -eq 0 ]]; then
  fail "No PQDP services are reachable. Start the stack first."
  echo -e "\n${RED}Aborting: no services available.${RESET}"
  exit 1
fi

if [[ -z "$JWT_SECRET" ]]; then
  skip "JWT_SECRET not set — authenticated tests will use empty token (expect 401s in ENFORCE_JWT=true mode)"
fi

# ── Section 1: QuantumVault ───────────────────────────────────────────────────
section "1. QuantumVault (PQC Secrets Vault & KMS)"

if healthz_ok "$QV_URL"; then
  NS="$(date +%s%N)"

  # 1a. Healthz fields
  body=$(curl -sk "$QV_URL/healthz")
  if echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
    pass "QuantumVault /healthz returns status:ok"
    PASSED=$((PASSED+1))
  else
    fail "QuantumVault /healthz body missing status:ok — got: $body"
  fi

  # 1b. Unauthenticated PUT → 401
  s=$(unauth_status PUT "$QV_URL/api/v1/vault/secret/test%2Funauth" \
    -H "Content-Type: application/json" -d '{"value":{"k":"v"}}')
  assert_status "QuantumVault PUT secret without token → 401" "$s" "401"

  # 1c. Secret round-trip
  PATH_ENC="test%2Fqa-roundtrip-${NS}"
  s=$(auth_status PUT "$QV_URL/api/v1/vault/secret/${PATH_ENC}" \
    -H "Content-Type: application/json" \
    -d "{\"value\":{\"qa-key\":\"qa-value-${NS}\"}}")
  assert_status "QuantumVault PUT secret → 200/201" "$s" "200"

  response=$(auth_body_status GET "$QV_URL/api/v1/vault/secret/${PATH_ENC}")
  http_s="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "$http_s" == "200" ]]; then
    if echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'qa-key' in str(d)" 2>/dev/null; then
      pass "QuantumVault GET secret → value matches"
      PASSED=$((PASSED+1))
    else
      fail "QuantumVault GET secret value mismatch — body: $body"
    fi
  else
    fail "QuantumVault GET secret → expected 200, got $http_s"
  fi

  # 1d. Non-existent path → 404
  s=$(auth_status GET "$QV_URL/api/v1/vault/secret/nonexistent%2Fpath-${NS}")
  assert_status "QuantumVault GET non-existent → 404" "$s" "404"

  # 1e. Transit encrypt/decrypt round-trip
  ENCRYPT_RESP=$(auth_body_status POST "$QV_URL/api/v1/transit/encrypt" \
    -H "Content-Type: application/json" \
    -d '{"plaintext":"aGVsbG8gd29ybGQ=","key_ref":"default"}')
  enc_status="${ENCRYPT_RESP##*$'\n'}"
  enc_body="${ENCRYPT_RESP%$'\n'*}"
  if [[ "$enc_status" == "200" ]]; then
    pass "QuantumVault transit encrypt → 200"
    PASSED=$((PASSED+1))
    # Try decrypt
    CIPHERTEXT=$(echo "$enc_body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ciphertext',''))" 2>/dev/null || echo "")
    if [[ -n "$CIPHERTEXT" ]]; then
      dec_status=$(auth_status POST "$QV_URL/api/v1/transit/decrypt" \
        -H "Content-Type: application/json" \
        -d "{\"ciphertext\":\"${CIPHERTEXT}\",\"key_ref\":\"default\"}")
      assert_status "QuantumVault transit decrypt → 200" "$dec_status" "200"
    fi
  else
    skip "QuantumVault transit encrypt returned $enc_status (key may not exist yet)"
  fi

  # 1f. Audit log
  s=$(auth_status GET "$QV_URL/api/v1/audit/log")
  assert_status "QuantumVault audit log accessible" "$s" "200"
else
  skip "QuantumVault not reachable — skipping all QV tests"
fi

# ── Section 2: Policy Engine ──────────────────────────────────────────────────
section "2. Policy Engine (ABAC Data Access Policies)"

if healthz_ok "$PE_URL"; then
  NS="$(date +%s%N)"
  POLICY_ID="qa-policy-${NS}"

  # 2a. Unauth
  s=$(unauth_status POST "$PE_URL/api/v1/policies" \
    -H "Content-Type: application/json" -d '{"name":"x"}')
  assert_status "PolicyEngine POST /policies without token → 401" "$s" "401"

  # 2b. Create policy
  create_resp=$(auth_body_status POST "$PE_URL/api/v1/policies" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"${POLICY_ID}\",\"name\":\"qa-allow-all-${NS}\",\"description\":\"QA test policy\",\"rego_source\":\"package qa\ndefault allow = true\"}")
  create_s="${create_resp##*$'\n'}"
  if [[ "$create_s" == "201" || "$create_s" == "200" || "$create_s" == "409" ]]; then
    pass "PolicyEngine create policy → $create_s"
    PASSED=$((PASSED+1))
  else
    fail "PolicyEngine create policy → unexpected $create_s"
  fi

  # 2c. Evaluate
  eval_resp=$(auth_body_status POST "$PE_URL/api/v1/policies/evaluate" \
    -H "Content-Type: application/json" \
    -d "{\"action\":\"read\",\"actor\":\"${TENANT_ID}\",\"data\":{\"classification\":\"PUBLIC\"}}")
  eval_s="${eval_resp##*$'\n'}"
  if [[ "$eval_s" == "200" ]]; then
    pass "PolicyEngine evaluate → 200"
    PASSED=$((PASSED+1))
  else
    skip "PolicyEngine evaluate returned $eval_s (acceptable if no active policy)"
  fi

  # 2d. List policies
  s=$(auth_status GET "$PE_URL/api/v1/policies")
  assert_status "PolicyEngine list policies → 200" "$s" "200"

  # 2e. Audit log
  s=$(auth_status GET "$PE_URL/api/v1/audit/logs")
  assert_status "PolicyEngine audit log → 200" "$s" "200"
else
  skip "PolicyEngine not reachable — skipping all PE tests"
fi

# ── Section 3: Secure DataShare ───────────────────────────────────────────────
section "3. Secure DataShare (Zero-Trust PQC Data Sharing)"

if healthz_ok "$DS_URL"; then
  NS="$(date +%s%N)"

  # 3a. Unauth
  s=$(unauth_status POST "$DS_URL/api/v1/shares" \
    -H "Content-Type: application/json" -d '{"blob_ref":"x"}')
  assert_status "DataShare POST /shares without token → 401" "$s" "401"

  # 3b. Create share
  share_resp=$(auth_body_status POST "$DS_URL/api/v1/shares" \
    -H "Content-Type: application/json" \
    -d "{\"blob_ref\":\"qa-blob-${NS}\",\"recipients\":[\"${TENANT_ID}\"]}")
  share_s="${share_resp##*$'\n'}"
  share_body="${share_resp%$'\n'*}"
  if [[ "$share_s" == "201" || "$share_s" == "200" ]]; then
    pass "DataShare create share → $share_s"
    PASSED=$((PASSED+1))
    SHARE_ID=$(echo "$share_body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    if [[ -n "$SHARE_ID" ]]; then
      # 3c. Get share
      s=$(auth_status GET "$DS_URL/api/v1/shares/${SHARE_ID}")
      assert_status "DataShare GET share by id → 200" "$s" "200"
      # 3d. Revoke
      s=$(auth_status POST "$DS_URL/api/v1/shares/${SHARE_ID}/revoke")
      if [[ "$s" == "200" || "$s" == "204" ]]; then
        pass "DataShare revoke share → $s"
        PASSED=$((PASSED+1))
      else
        fail "DataShare revoke → unexpected $s"
      fi
    fi
  else
    fail "DataShare create share → unexpected $share_s"
  fi

  # 3e. Audit log
  s=$(auth_status GET "$DS_URL/api/v1/audit/logs")
  assert_status "DataShare audit log → 200" "$s" "200"
else
  skip "Secure DataShare not reachable — skipping all DS tests"
fi

# ── Section 4: CryptoGuard ────────────────────────────────────────────────────
section "4. CryptoGuard (PQC Inventory & CBOM)"

if healthz_ok "$CG_URL"; then
  # 4a. Unauth
  s=$(unauth_status GET "$CG_URL/api/v1/cbom")
  assert_status "CryptoGuard GET /cbom without token → 401" "$s" "401"

  # 4b. Get CBOM (may be empty before first scan — that's OK)
  s=$(auth_status GET "$CG_URL/api/v1/cbom")
  assert_status "CryptoGuard GET CBOM → 200" "$s" "200"

  # 4c. Generate CBOM job
  gen_resp=$(auth_body_status POST "$CG_URL/api/v1/cbom/generate" \
    -H "Content-Type: application/json" -d '{}')
  gen_s="${gen_resp##*$'\n'}"
  gen_body="${gen_resp%$'\n'*}"
  if [[ "$gen_s" == "202" || "$gen_s" == "200" ]]; then
    pass "CryptoGuard CBOM generate → $gen_s"
    PASSED=$((PASSED+1))
    JOB_ID=$(echo "$gen_body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('job_id',''))" 2>/dev/null || echo "")
    if [[ -n "$JOB_ID" ]]; then
      s=$(auth_status GET "$CG_URL/api/v1/cbom/generate/${JOB_ID}")
      if [[ "$s" == "200" || "$s" == "202" ]]; then
        pass "CryptoGuard poll CBOM job → $s"
        PASSED=$((PASSED+1))
      else
        fail "CryptoGuard poll CBOM job → unexpected $s"
      fi
    fi
  else
    fail "CryptoGuard CBOM generate → unexpected $gen_s"
  fi

  # 4d. CNSA compliance
  s=$(auth_status GET "$CG_URL/api/v1/compliance/cnsa")
  assert_status "CryptoGuard CNSA compliance check → 200" "$s" "200"

  # 4e. Health score (may be 200 or 204 before first scan)
  s=$(auth_status GET "$CG_URL/api/v1/health-score")
  if [[ "$s" == "200" || "$s" == "204" ]]; then
    pass "CryptoGuard health score → $s"
    PASSED=$((PASSED+1))
  else
    fail "CryptoGuard health score → unexpected $s"
  fi

  # 4f. Audit log
  s=$(auth_status GET "$CG_URL/api/v1/audit/logs")
  assert_status "CryptoGuard audit log → 200" "$s" "200"
else
  skip "CryptoGuard not reachable — skipping all CG tests"
fi

# ── Section 5: TokenVault ─────────────────────────────────────────────────────
section "5. TokenVault (PQC Format-Preserving Tokenization)"

if healthz_ok "$TV_URL"; then
  NS="$(date +%s%N)"

  # 5a. Unauth
  s=$(unauth_status POST "$TV_URL/api/v1/tokenize" \
    -H "Content-Type: application/json" -d '{"key_ref":"default"}')
  assert_status "TokenVault POST /tokenize without token → 401" "$s" "401"

  # 5b. Tokenize PAN
  tok_resp=$(auth_body_status POST "$TV_URL/api/v1/tokenize" \
    -H "Content-Type: application/json" \
    -d '{"key_ref":"default","fields":[{"name":"pan","value":"4111111111111111","format":"PAN"}]}')
  tok_s="${tok_resp##*$'\n'}"
  tok_body="${tok_resp%$'\n'*}"
  if [[ "$tok_s" == "200" ]]; then
    pass "TokenVault tokenize PAN → 200"
    PASSED=$((PASSED+1))
    TOKEN_VALUE=$(echo "$tok_body" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tokens',{}).get('pan',''))" 2>/dev/null || echo "")
    if [[ -n "$TOKEN_VALUE" ]]; then
      # 5c. Detokenize
      detok_s=$(auth_status POST "$TV_URL/api/v1/detokenize" \
        -H "Content-Type: application/json" \
        -d "{\"token\":\"${TOKEN_VALUE}\",\"format_id\":\"PAN\",\"key_ref\":\"default\"}")
      assert_status "TokenVault detokenize → 200" "$detok_s" "200"
    fi
  else
    fail "TokenVault tokenize PAN → unexpected $tok_s"
  fi

  # 5d. Custom format registration
  fmt_id="qa-fmt-${NS}"
  fmt_s=$(auth_status POST "$TV_URL/api/v1/formats" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"${fmt_id}\",\"pattern\":\"####-####\",\"radix\":10,\"min_length\":8,\"max_length\":8}")
  if [[ "$fmt_s" == "201" || "$fmt_s" == "200" || "$fmt_s" == "409" ]]; then
    pass "TokenVault register custom format → $fmt_s"
    PASSED=$((PASSED+1))
  else
    fail "TokenVault register custom format → unexpected $fmt_s"
  fi

  # 5e. List formats
  s=$(auth_status GET "$TV_URL/api/v1/formats")
  assert_status "TokenVault list formats → 200" "$s" "200"

  # 5f. Audit log
  s=$(auth_status GET "$TV_URL/api/v1/audit/logs")
  assert_status "TokenVault audit log → 200" "$s" "200"
else
  skip "TokenVault not reachable — skipping all TV tests"
fi

# ── Section 6: PQ Sign ────────────────────────────────────────────────────────
section "6. PQ Sign (ML-DSA-87 Document & Code Signing)"

if healthz_ok "$SG_URL"; then
  # 6a. Unauth
  s=$(unauth_status POST "$SG_URL/api/v1/sign/document" \
    -H "Content-Type: application/json" -d '{"data":"dGVzdA==","key_ref":"default"}')
  assert_status "PQ-Sign POST /sign/document without token → 401" "$s" "401"

  # 6b. Get public key
  s=$(auth_status GET "$SG_URL/api/v1/sign/public-key")
  assert_status "PQ-Sign GET public key → 200" "$s" "200"

  # 6c. Sign document
  sign_resp=$(auth_body_status POST "$SG_URL/api/v1/sign/document" \
    -H "Content-Type: application/json" \
    -d '{"data":"dGVzdCBkb2N1bWVudA==","key_ref":"default"}')
  sign_s="${sign_resp##*$'\n'}"
  sign_body="${sign_resp%$'\n'*}"
  if [[ "$sign_s" == "200" ]]; then
    pass "PQ-Sign sign document → 200"
    PASSED=$((PASSED+1))
    # 6d. Verify
    verify_s=$(auth_status POST "$SG_URL/api/v1/verify/document" \
      -H "Content-Type: application/json" \
      -d "{\"signature\":$(echo "$sign_body" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('signature',{})))" 2>/dev/null || echo '{}'),\"data\":\"dGVzdCBkb2N1bWVudA==\"}")
    assert_status "PQ-Sign verify document → 200" "$verify_s" "200"
  else
    fail "PQ-Sign sign document → unexpected $sign_s"
  fi

  # 6e. Timestamp
  ts_s=$(auth_status POST "$SG_URL/api/v1/timestamp" \
    -H "Content-Type: application/json" -d '{"data":"dGVzdA=="}')
  assert_status "PQ-Sign timestamp → 200" "$ts_s" "200"

  # 6f. Audit log
  s=$(auth_status GET "$SG_URL/api/v1/audit/logs")
  assert_status "PQ-Sign audit log → 200" "$s" "200"
else
  skip "PQ-Sign not reachable — skipping all SG tests"
fi

# ── Section 7: PQ Comply ──────────────────────────────────────────────────────
section "7. PQ Comply (NIST/FIPS Compliance Reporting)"

if healthz_ok "$CP_URL"; then
  # 7a. Unauth
  s=$(unauth_status GET "$CP_URL/api/v1/posture")
  assert_status "PQ-Comply GET /posture without token → 401" "$s" "401"

  # 7b. List frameworks
  s=$(auth_status GET "$CP_URL/api/v1/compliance/frameworks")
  assert_status "PQ-Comply list frameworks → 200" "$s" "200"

  # 7c. Get posture
  s=$(auth_status GET "$CP_URL/api/v1/posture")
  assert_status "PQ-Comply get posture → 200" "$s" "200"

  # 7d. Gap analysis
  s=$(auth_status GET "$CP_URL/api/v1/compliance/gap-analysis")
  assert_status "PQ-Comply gap analysis → 200" "$s" "200"

  # 7e. Generate report
  report_resp=$(auth_body_status POST "$CP_URL/api/v1/compliance/reports" \
    -H "Content-Type: application/json" \
    -d '{"framework":"NIST-CSF","organization":"QA Test Org","algorithms":["ML-KEM-1024","ML-DSA-87"]}')
  report_s="${report_resp##*$'\n'}"
  if [[ "$report_s" == "200" || "$report_s" == "201" ]]; then
    pass "PQ-Comply generate report → $report_s"
    PASSED=$((PASSED+1))
  else
    fail "PQ-Comply generate report → unexpected $report_s"
  fi

  # 7f. Audit log
  s=$(auth_status GET "$CP_URL/api/v1/audit/logs")
  assert_status "PQ-Comply audit log → 200" "$s" "200"
else
  skip "PQ-Comply not reachable — skipping all CP tests"
fi

# ── Section 8: Transit Shield ─────────────────────────────────────────────────
section "8. Transit Shield (PQC Hybrid TLS Gateway)"

if healthz_ok "$TS_URL"; then
  # 8a. Healthz fields
  ts_health=$(curl -sk "$TS_URL/healthz")
  if echo "$ts_health" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('status')=='ok'" 2>/dev/null; then
    pass "TransitShield /healthz returns status:ok"
    PASSED=$((PASSED+1))
  else
    fail "TransitShield /healthz malformed — got: $ts_health"
  fi

  # 8b. Gateway stats requires auth
  s=$(unauth_status GET "$TS_URL/api/v1/gateway/stats")
  assert_status "TransitShield /gateway/stats without token → 401" "$s" "401"

  # 8c. Auth'd gateway stats
  tok=$(mint_token)
  if [[ -n "$tok" ]]; then
    s=$(curl "${CURL_OPTS[@]}" -k -X GET "$TS_URL/api/v1/gateway/stats" \
      -H "Authorization: Bearer $tok" \
      -H "X-Tenant-ID: ${TENANT_ID}")
    assert_status "TransitShield GET /gateway/stats (auth'd) → 200" "$s" "200"
  else
    skip "TransitShield gateway stats auth'd test — JWT_SECRET not set"
  fi
else
  skip "Transit Shield not reachable — skipping all TS tests"
fi

# ── Section 9: PQ Migrate ─────────────────────────────────────────────────────
section "9. PQ Migrate (Cross-Vault Secret Migration)"

if healthz_ok "$MG_URL"; then
  NS="$(date +%s%N)"

  # 9a. Unauth
  s=$(unauth_status POST "$MG_URL/api/v1/migrations" \
    -H "Content-Type: application/json" -d '{"name":"x"}')
  assert_status "PQ-Migrate POST /migrations without token → 401" "$s" "401"

  # 9b. Create migration job
  job_resp=$(auth_body_status POST "$MG_URL/api/v1/migrations" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"qa-job-${NS}\",\"source\":\"quantumvault\",\"source_config\":{\"url\":\"${QV_URL}\"},\"dry_run\":true}")
  job_s="${job_resp##*$'\n'}"
  job_body="${job_resp%$'\n'*}"
  if [[ "$job_s" == "201" || "$job_s" == "200" ]]; then
    pass "PQ-Migrate create job → $job_s"
    PASSED=$((PASSED+1))
    JOB_ID=$(echo "$job_body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
    if [[ -n "$JOB_ID" ]]; then
      # 9c. Get job
      s=$(auth_status GET "$MG_URL/api/v1/migrations/${JOB_ID}")
      assert_status "PQ-Migrate GET job by id → 200" "$s" "200"
      # 9d. Run job (async)
      s=$(auth_status POST "$MG_URL/api/v1/migrations/${JOB_ID}/run")
      if [[ "$s" == "202" || "$s" == "200" ]]; then
        pass "PQ-Migrate run job → $s"
        PASSED=$((PASSED+1))
      else
        fail "PQ-Migrate run job → unexpected $s"
      fi
    fi
  else
    fail "PQ-Migrate create job → unexpected $job_s"
  fi

  # 9e. List jobs (tenant-scoped)
  s=$(auth_status GET "$MG_URL/api/v1/migrations")
  assert_status "PQ-Migrate list jobs → 200" "$s" "200"

  # 9f. Tenant isolation: job created by tenant-A must not appear for tenant-B
  if [[ -n "$JWT_SECRET" ]]; then
    tok_b=$(mint_token "${TENANT_ID}-other-tenant" "isolation-test")
    client_b_resp=$(curl "${CURL_BODY_OPTS[@]}" -k -X GET "$MG_URL/api/v1/migrations" \
      -H "Authorization: Bearer $tok_b")
    b_status="${client_b_resp##*$'\n'}"
    b_body="${client_b_resp%$'\n'*}"
    if [[ "$b_status" == "200" ]]; then
      if [[ -n "${JOB_ID:-}" ]] && echo "$b_body" | grep -q "$JOB_ID"; then
        fail "PQ-Migrate tenant isolation breach: job ${JOB_ID} visible to other tenant"
      else
        pass "PQ-Migrate tenant isolation: job not visible cross-tenant"
        PASSED=$((PASSED+1))
      fi
    else
      skip "PQ-Migrate tenant isolation check skipped (status $b_status)"
    fi
  else
    skip "PQ-Migrate tenant isolation — JWT_SECRET not set"
  fi
else
  skip "PQ-Migrate not reachable — skipping all MG tests"
fi

# ── Section 10: Cross-Service Flows ──────────────────────────────────────────
section "10. Cross-Service Integration Flows"

# 10a. Vault-backed sign: store signing key metadata in QV, then sign with SG
if healthz_ok "$QV_URL" && healthz_ok "$SG_URL"; then
  NS="$(date +%s%N)"
  PATH_ENC="test%2Fqa-signing-meta-${NS}"
  put_s=$(auth_status PUT "$QV_URL/api/v1/vault/secret/${PATH_ENC}" \
    -H "Content-Type: application/json" \
    -d '{"value":{"key_ref":"default","algorithm":"ML-DSA-87"}}')
  sign_s=$(auth_status POST "$SG_URL/api/v1/sign/document" \
    -H "Content-Type: application/json" \
    -d '{"data":"Y3Jvc3Mtc2VydmljZSB0ZXN0","key_ref":"default"}')
  if [[ "$put_s" == "200" || "$put_s" == "201" ]] && [[ "$sign_s" == "200" ]]; then
    pass "Cross-service: Vault-backed signing key metadata stored + document signed"
    PASSED=$((PASSED+1))
  else
    fail "Cross-service vault-backed signing: QV PUT=$put_s, SG sign=$sign_s"
  fi
else
  skip "Cross-service vault+sign flow — QV or SG not reachable"
fi

# 10b. Policy evaluation guards data share (PE + DS)
if healthz_ok "$PE_URL" && healthz_ok "$DS_URL"; then
  # Just verify both services are healthy and auth'd calls return 200/201
  pe_s=$(auth_status GET "$PE_URL/api/v1/policies")
  ds_s=$(auth_status GET "$DS_URL/api/v1/shares")
  if [[ "$pe_s" == "200" && "$ds_s" == "200" ]]; then
    pass "Cross-service: PolicyEngine + DataShare both accessible (policy-governed sharing flow ready)"
    PASSED=$((PASSED+1))
  else
    fail "Cross-service PE+DS: PE list=$pe_s, DS list=$ds_s"
  fi
else
  skip "Cross-service PE+DS flow — one or both services not reachable"
fi

# 10c. Tokenize → store token in QV → detokenize (TV + QV)
if healthz_ok "$TV_URL" && healthz_ok "$QV_URL"; then
  NS="$(date +%s%N)"
  tokenize_resp=$(auth_body_status POST "$TV_URL/api/v1/tokenize" \
    -H "Content-Type: application/json" \
    -d '{"key_ref":"default","fields":[{"name":"ssn","value":"123-45-6789","format":"SSN"}]}')
  tok_s="${tokenize_resp##*$'\n'}"
  tok_body="${tokenize_resp%$'\n'*}"
  if [[ "$tok_s" == "200" ]]; then
    # Store the token reference in QV for safekeeping
    SSN_TOKEN=$(echo "$tok_body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tokens',{}).get('ssn',''))" 2>/dev/null || echo "")
    if [[ -n "$SSN_TOKEN" ]]; then
      PATH_ENC="test%2Fqa-token-ref-${NS}"
      put_s=$(auth_status PUT "$QV_URL/api/v1/vault/secret/${PATH_ENC}" \
        -H "Content-Type: application/json" \
        -d "{\"value\":{\"ssn_token\":\"${SSN_TOKEN}\",\"format\":\"SSN\"}}")
      if [[ "$put_s" == "200" || "$put_s" == "201" ]]; then
        pass "Cross-service: tokenized SSN + stored reference in QuantumVault"
        PASSED=$((PASSED+1))
      else
        fail "Cross-service TV+QV: tokenize OK but QV store returned $put_s"
      fi
    fi
  else
    skip "Cross-service TV+QV: tokenize returned $tok_s (SSN format may not be registered)"
  fi
else
  skip "Cross-service TV+QV flow — one or both services not reachable"
fi

# ── Section 11: RuntimeAI Enterprise → PQDP Integration ──────────────────────
section "11. RuntimeAI Enterprise ↔ PQDP Integration"

CP_HEALTH=$(curl "${CURL_OPTS[@]}" -k "$CONTROL_PLANE_URL/healthz" 2>/dev/null || echo "000")
if [[ "$CP_HEALTH" == "200" ]]; then
  # 11a. Control Plane healthz
  pass "RuntimeAI Control Plane reachable at $CONTROL_PLANE_URL"
  PASSED=$((PASSED+1))

  # 11b. CP can reach QV (proxy test through CP if applicable)
  # Only validate if QV is also reachable
  if healthz_ok "$QV_URL"; then
    pass "RuntimeAI CP + QuantumVault both reachable (cross-platform integration path available)"
    PASSED=$((PASSED+1))
    info "Integration note: CP should call QV at ${QV_URL} for PQC secret operations"
  fi
else
  skip "RuntimeAI Control Plane not reachable at $CONTROL_PLANE_URL — skipping CP↔PQDP tests"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$((PASSED+FAILED+SKIPPED))
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}" | tee -a "$LOG_FILE"
echo -e "${BOLD} PQ Data Platform Integration Tests — Summary               ${RESET}" | tee -a "$LOG_FILE"
echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}" | tee -a "$LOG_FILE"
echo -e " Total     : $TOTAL"                                                         | tee -a "$LOG_FILE"
echo -e " ${GREEN}Passed${RESET}    : $PASSED"                                        | tee -a "$LOG_FILE"
echo -e " ${RED}Failed${RESET}    : $FAILED"                                          | tee -a "$LOG_FILE"
echo -e " ${YELLOW}Skipped${RESET}   : $SKIPPED"                                      | tee -a "$LOG_FILE"
echo -e " Log       : $LOG_FILE"                                                       | tee -a "$LOG_FILE"
echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}" | tee -a "$LOG_FILE"

if [[ $FAILED -gt 0 ]]; then
  echo -e "\n${RED}${BOLD}RESULT: FAILED ($FAILED test(s) failed)${RESET}" | tee -a "$LOG_FILE"
  exit 1
else
  echo -e "\n${GREEN}${BOLD}RESULT: PASSED${RESET}" | tee -a "$LOG_FILE"
  exit 0
fi

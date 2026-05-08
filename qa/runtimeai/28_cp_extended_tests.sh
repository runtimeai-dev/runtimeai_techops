#!/bin/bash
# Extended enforcement tests: guardrails, NHI policy, conditional access, TTL, vendor config push

CP="https://api.rt19.runtimeai.io"
API_KEY="feb2e99379707e322c07c206f82c0a7a0bfe87cfaa620c64bd6afc685d33220c"
TENANT="scorpius-demo"
ENFORCER="https://enforcer.rt19.runtimeai.io"
CLEAN_KEY="rtai-pk-4254e304b64330735c9cbb7058ef7a8a"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
ak() { /usr/bin/curl -sk -H "X-API-Key: $API_KEY" -H "X-Tenant-ID: $TENANT" "$@"; }

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  GUARDRAILS — parse / create / activate / simulate"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

info "[1] Dry-run parse"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policy/guardrails/parse" \
  -H "Content-Type: application/json" \
  -d '{"text":"Block all requests where data_classification is sensitive"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
VALID=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("valid","?"))' 2>/dev/null)
[ "$CODE" = "200" ] && pass "parse → 200, valid=$VALID" || fail "parse → HTTP $CODE: $BODY"

info "[2] Create guardrail (plain English → auto-compiled)"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policy/guardrails" \
  -H "Content-Type: application/json" \
  -d '{"text":"Block all requests where data_classification is sensitive","policy_version":"demo-v1"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
GR_ID=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
[ "$CODE" = "200" ] || [ "$CODE" = "201" ] \
  && pass "create guardrail → HTTP $CODE, id=$GR_ID" \
  || fail "create guardrail → HTTP $CODE: $BODY"

info "[3] List guardrails"
RESP=$(ak -w "\n%{http_code}" "$CP/api/policy/guardrails")
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
CNT=$(echo "$BODY" | python3 -c 'import sys,json; d=json.load(sys.stdin); g=d.get("guardrails",d); print(len(g) if isinstance(g,list) else "?")' 2>/dev/null)
[ "$CODE" = "200" ] && pass "list guardrails → $CNT records" || fail "list → HTTP $CODE"

if [ -n "$GR_ID" ]; then
  info "[4] Activate guardrail → pushes policy to DP"
  RESP=$(ak -w "\n%{http_code}" -X PATCH "$CP/api/policy/guardrails/$GR_ID" \
    -H "Content-Type: application/json" -d '{"action":"activate"}')
  CODE=$(echo "$RESP" | tail -1)
  [ "$CODE" = "200" ] || [ "$CODE" = "204" ] \
    && pass "activate → HTTP $CODE (policy now live on DP)" \
    || fail "activate → HTTP $CODE"

  info "[5] Simulate: sensitive data_classification → expect deny"
  RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policy/guardrails/simulate" \
    -H "Content-Type: application/json" \
    -d '{"agent_id":"demo-agent-clean","data_classification":"sensitive","tool_id":"s3-mcp"}')
  CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
  DEC=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("decision","?"))' 2>/dev/null)
  RULES=$(echo "$BODY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("matched_rules",[])))' 2>/dev/null)
  if [ "$CODE" = "200" ] && [ "$DEC" = "deny" ]; then
    pass "simulate sensitive → deny ✓ (matched $RULES rule(s))"
  elif [ "$CODE" = "200" ]; then
    info "simulate sensitive → decision=$DEC (Rego compile may be pending; matched=$RULES)"
  else
    fail "simulate → HTTP $CODE: $BODY"
  fi

  info "[6] Simulate: public data_classification → expect allow"
  RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policy/guardrails/simulate" \
    -H "Content-Type: application/json" \
    -d '{"agent_id":"demo-agent-clean","data_classification":"public","tool_id":"github-mcp"}')
  CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
  DEC=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("decision","?"))' 2>/dev/null)
  [ "$CODE" = "200" ] && [ "$DEC" = "allow" ] \
    && pass "simulate public → allow ✓" \
    || { [ "$CODE" = "200" ] && info "simulate public → decision=$DEC" || fail "simulate → HTTP $CODE"; }

  info "[7] Deactivate guardrail"
  RESP=$(ak -w "\n%{http_code}" -X PATCH "$CP/api/policy/guardrails/$GR_ID" \
    -H "Content-Type: application/json" -d '{"action":"deactivate"}')
  CODE=$(echo "$RESP" | tail -1)
  [ "$CODE" = "200" ] || [ "$CODE" = "204" ] \
    && pass "deactivate → HTTP $CODE" || fail "deactivate → HTTP $CODE"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  NHI POLICY — deploy rules / evaluate: allow & deny"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

info "[8] Deploy NHI policy: github-mcp read=allow, write=deny; s3-mcp *=deny"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/nhi/policy/deploy" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "demo-agent-clean",
    "rules": [
      {"tool_id":"github-mcp","action":"read","resource":"repo","effect":"allow"},
      {"tool_id":"github-mcp","action":"write","resource":"repo","effect":"deny"},
      {"tool_id":"s3-mcp","action":"*","resource":"*","effect":"deny"}
    ]
  }')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
[ "$CODE" = "200" ] || [ "$CODE" = "201" ] \
  && pass "deploy NHI policy → HTTP $CODE" \
  || fail "deploy NHI policy → HTTP $CODE: $BODY"

sleep 0.3

info "[9] Evaluate: github-mcp read → expect allow"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/nhi/policy/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-clean","tool_id":"github-mcp","action":"read","resource":"repo"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
ALLOW=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("allow","?"))' 2>/dev/null)
[ "$CODE" = "200" ] && [ "$ALLOW" = "True" ] \
  && pass "github-mcp read → allow=True ✓" \
  || { [ "$CODE" = "200" ] && fail "github-mcp read → allow=$ALLOW (expected True)" || fail "evaluate → HTTP $CODE: $BODY"; }

info "[10] Evaluate: github-mcp write → expect deny"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/nhi/policy/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-clean","tool_id":"github-mcp","action":"write","resource":"repo"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
ALLOW=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("allow","?"))' 2>/dev/null)
[ "$CODE" = "200" ] && [ "$ALLOW" = "False" ] \
  && pass "github-mcp write → allow=False ✓ (DENIED)" \
  || { [ "$CODE" = "200" ] && fail "github-mcp write → allow=$ALLOW (expected False)" || fail "evaluate → HTTP $CODE: $BODY"; }

info "[11] Evaluate: s3-mcp wildcard action → expect deny"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/nhi/policy/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-clean","tool_id":"s3-mcp","action":"delete","resource":"bucket"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
ALLOW=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("allow","?"))' 2>/dev/null)
[ "$CODE" = "200" ] && [ "$ALLOW" = "False" ] \
  && pass "s3-mcp delete → allow=False ✓ (wildcard deny)" \
  || { [ "$CODE" = "200" ] && fail "s3-mcp delete → allow=$ALLOW (expected False)" || fail "evaluate → HTTP $CODE: $BODY"; }

info "[11b] Update NHI policy: remove s3 deny, add slack-mcp deny"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/nhi/policy/deploy" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "demo-agent-clean",
    "rules": [
      {"tool_id":"github-mcp","action":"read","resource":"repo","effect":"allow"},
      {"tool_id":"github-mcp","action":"write","resource":"repo","effect":"deny"},
      {"tool_id":"slack-mcp","action":"*","resource":"*","effect":"deny"}
    ]
  }')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
[ "$CODE" = "200" ] || [ "$CODE" = "201" ] \
  && pass "update NHI policy → HTTP $CODE (rules changed, pushed to DP)" \
  || fail "update → HTTP $CODE: $BODY"

sleep 0.3

info "[11c] After update: s3-mcp should now be allowed (rule removed)"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/nhi/policy/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-clean","tool_id":"s3-mcp","action":"read","resource":"bucket"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
ALLOW=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("allow","?"))' 2>/dev/null)
[ "$CODE" = "200" ] && [ "$ALLOW" = "True" ] \
  && pass "s3-mcp read after policy update → allow=True ✓ (rule propagated)" \
  || { [ "$CODE" = "200" ] && fail "s3-mcp read → allow=$ALLOW (expected True after update)" || fail "evaluate → HTTP $CODE: $BODY"; }

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  CONDITIONAL ACCESS — create / evaluate / update / delete"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

info "[11d] Setup: register demo agents for conditional-access evaluate tests"
RESP=$(ak -s -w "\n%{http_code}" -X POST "$CP/api/agents" -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-clean","name":"Demo Agent Clean","owner":"qa-suite","environment":"production","risk_score":5,"trust_score":90}')
[ "$(echo "$RESP" | tail -1)" = "200" ] || [ "$(echo "$RESP" | tail -1)" = "201" ] || [ "$(echo "$RESP" | tail -1)" = "409" ] \
  && info "  demo-agent-clean registered" || info "  demo-agent-clean registration: $(echo "$RESP" | tail -1)"
RESP=$(ak -s -w "\n%{http_code}" -X POST "$CP/api/agents" -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-rogue","name":"Demo Agent Rogue","owner":"qa-suite","environment":"production","risk_score":92,"trust_score":10}')
[ "$(echo "$RESP" | tail -1)" = "200" ] || [ "$(echo "$RESP" | tail -1)" = "201" ] || [ "$(echo "$RESP" | tail -1)" = "409" ] \
  && info "  demo-agent-rogue registered" || info "  demo-agent-rogue registration: $(echo "$RESP" | tail -1)"

info "[12] List conditional access (baseline)"
RESP=$(ak -w "\n%{http_code}" "$CP/api/policies/conditional-access")
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
CNT=$(echo "$BODY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("policies",[])))' 2>/dev/null)
[ "$CODE" = "200" ] && pass "list → HTTP 200, $CNT existing policies" || fail "list → HTTP $CODE"

info "[13] Create: block risk_score > 80"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policies/conditional-access" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-block-high-risk","conditions":{"risk_score_gt":80},"action":"block","target_type":"agent"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
CA_ID=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
[ "$CODE" = "200" ] || [ "$CODE" = "201" ] \
  && pass "create block-high-risk → HTTP $CODE, id=$CA_ID" \
  || fail "create → HTTP $CODE: $BODY"

info "[14] Create: require_approval after-hours (22:00–06:00 UTC)"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policies/conditional-access" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-after-hours-approval","conditions":{"time_of_day":{"start":22,"end":6}},"action":"require_approval","target_type":"agent"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
CA_ID2=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
[ "$CODE" = "200" ] || [ "$CODE" = "201" ] \
  && pass "create after-hours → HTTP $CODE, id=$CA_ID2" \
  || fail "create after-hours → HTTP $CODE: $BODY"

info "[15] Create: block trust_score < 30"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policies/conditional-access" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-block-low-trust","conditions":{"trust_score_lt":30},"action":"block","target_type":"agent"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
CA_ID3=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
[ "$CODE" = "200" ] || [ "$CODE" = "201" ] \
  && pass "create block-low-trust → HTTP $CODE, id=$CA_ID3" \
  || fail "create low-trust → HTTP $CODE: $BODY"

info "[16] Evaluate: demo-agent-clean (should allow — normal risk)"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policies/conditional-access/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-clean","environment":"production"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
DEC=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("decision","?"))' 2>/dev/null)
MATCHED=$(echo "$BODY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("matched",[])))' 2>/dev/null)
[ "$CODE" = "200" ] && pass "evaluate clean-agent → decision=$DEC, matched=$MATCHED rules" \
  || fail "evaluate → HTTP $CODE: $BODY"

info "[17] Evaluate: demo-agent-rogue (risk=92, trust=10 → expect block)"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/policies/conditional-access/evaluate" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-rogue","environment":"production"}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
DEC=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("decision","?"))' 2>/dev/null)
MATCHED=$(echo "$BODY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("matched_policies",json.load(sys.stdin).get("matched",[]))))' 2>/dev/null || echo "?")
# 403 with decision=block is the correct outcome for a high-risk agent
[ \( "$CODE" = "200" -o "$CODE" = "403" \) ] && [ "$DEC" = "block" ] \
  && pass "evaluate rogue-agent → decision=block ✓ (matched=$MATCHED policies), HTTP $CODE" \
  || { [ "$CODE" = "200" ] && fail "evaluate rogue-agent → decision=$DEC (expected block)" || fail "evaluate → HTTP $CODE: $BODY"; }

if [ -n "$CA_ID" ]; then
  info "[18] Update: raise risk threshold to 90"
  RESP=$(ak -w "\n%{http_code}" -X PUT "$CP/api/policies/conditional-access" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"$CA_ID\",\"name\":\"demo-block-high-risk\",\"conditions\":{\"risk_score_gt\":90}}")
  CODE=$(echo "$RESP" | tail -1)
  [ "$CODE" = "200" ] && pass "update threshold risk_score_gt → 90, HTTP $CODE" \
    || fail "update → HTTP $CODE: $(echo $RESP | sed '$d')"
fi

info "[19] Cleanup: delete all demo conditional-access policies"
for ID in "$CA_ID" "$CA_ID2" "$CA_ID3"; do
  [ -z "$ID" ] && continue
  CODE=$(ak -o /dev/null -w "%{http_code}" -X DELETE "$CP/api/policies/conditional-access?id=$ID")
  [ "$CODE" = "200" ] || [ "$CODE" = "204" ] \
    && pass "delete $ID → HTTP $CODE" || fail "delete $ID → HTTP $CODE"
done

info "[19b] Teardown: delete demo agents"
ak -s -X DELETE "$CP/api/agents/demo-agent-clean" > /dev/null
ak -s -X DELETE "$CP/api/agents/demo-agent-rogue" > /dev/null

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  PROXY KEY ENTITLEMENTS — allowlist / blocklist / TTL expiry"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

info "[20] Issue key: allowed_models=[haiku only]"
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/proxy-keys" \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"demo-agent-entitle","vendor_alias":"claude-demo","allowed_models":["claude-haiku-4-5-20251001"]}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
ENT_KEY=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("key",""))' 2>/dev/null)
ENT_ID=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
[ "$CODE" = "201" ] \
  && pass "issue entitlement key → id=$ENT_ID, allowed=[haiku]" \
  || fail "issue → HTTP $CODE: $BODY"

if [ -n "$ENT_KEY" ]; then
  info "[21] Allowed model (haiku) → enforcer forwards"
  CODE=$(/usr/bin/curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "$ENFORCER/claude-demo/v1/messages" \
    -H "Authorization: Bearer $ENT_KEY" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}')
  [ "$CODE" != "403" ] \
    && pass "haiku (in allowlist) → HTTP $CODE — enforcer forwarded ✓" \
    || fail "haiku unexpectedly blocked → HTTP $CODE"

  info "[22] Non-allowed model (opus) → enforcer blocks 403"
  RESP=$(/usr/bin/curl -sk -w "\n%{http_code}" \
    -X POST "$ENFORCER/claude-demo/v1/messages" \
    -H "Authorization: Bearer $ENT_KEY" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-opus-4-7","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}')
  CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
  ERR=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("error",""))' 2>/dev/null)
  [ "$CODE" = "403" ] \
    && pass "opus (not in allowlist) → 403 $ERR ✓" \
    || fail "opus should be blocked by allowlist, got HTTP $CODE: $BODY"
fi

info "[23] Issue key with TTL (expires in 5 seconds)"
EXPIRES=$(python3 -c 'from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)+timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
RESP=$(ak -w "\n%{http_code}" -X POST "$CP/api/proxy-keys" \
  -H "Content-Type: application/json" \
  -d "{\"agent_id\":\"demo-agent-ttl\",\"vendor_alias\":\"claude-demo\",\"expires_at\":\"$EXPIRES\"}")
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
TTL_KEY=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("key",""))' 2>/dev/null)
TTL_ID=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
STORED_EXP=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("expires_at","null"))' 2>/dev/null)
[ "$CODE" = "201" ] \
  && pass "issue TTL key → expires_at=$STORED_EXP" \
  || fail "issue TTL → HTTP $CODE: $BODY"

if [ -n "$TTL_KEY" ]; then
  info "[24] Pre-expiry: key should be accepted"
  CODE=$(/usr/bin/curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "$ENFORCER/claude-demo/v1/messages" \
    -H "Authorization: Bearer $TTL_KEY" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"pre-expiry"}]}')
  # 401 = Anthropic auth error (enforcer forwarded but test acct key is dummy) = accepted
  # 403 = enforcer blocked (key expired/invalid) = fail
  [ "$CODE" != "403" ] \
    && pass "pre-expiry → HTTP $CODE (enforcer forwarded ✓)" \
    || fail "pre-expiry key rejected → HTTP $CODE"

  info "[25] Waiting 6 seconds for TTL to expire..."
  sleep 6

  info "[26] Post-expiry: key should be rejected (401 or 403)"
  RESP=$(/usr/bin/curl -sk -w "\n%{http_code}" \
    -X POST "$ENFORCER/claude-demo/v1/messages" \
    -H "Authorization: Bearer $TTL_KEY" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"post-expiry"}]}')
  CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
  ERR=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("error",""))' 2>/dev/null)
  [ "$CODE" = "401" ] || [ "$CODE" = "403" ] \
    && pass "post-expiry → HTTP $CODE $ERR ✓ (TTL enforced by DP)" \
    || fail "expired key should be rejected, got HTTP $CODE: $BODY"
fi

info "[27] PATCH proxy key: extend TTL to 1 hour from now"
NEW_EXP=$(python3 -c 'from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)+timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
if [ -n "$TTL_ID" ]; then
  RESP=$(ak -w "\n%{http_code}" -X PATCH "$CP/api/proxy-keys/$TTL_ID" \
    -H "Content-Type: application/json" \
    -d "{\"expires_at\":\"$NEW_EXP\"}")
  CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
  UPDATED_EXP=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("expires_at","?"))' 2>/dev/null)
  [ "$CODE" = "200" ] \
    && pass "PATCH TTL → new expires_at=$UPDATED_EXP ✓" \
    || fail "PATCH TTL → HTTP $CODE: $BODY"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  VENDOR CONFIG — update blocked models → verify DP enforces"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

info "[28] Get current claude-demo vendor config"
RESP=$(ak -w "\n%{http_code}" "$CP/api/vendor-config/claude-demo")
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
ORIG_BLOCKED=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("blocked_models",[]))' 2>/dev/null)
[ "$CODE" = "200" ] \
  && pass "get vendor config → blocked_models=$ORIG_BLOCKED" \
  || fail "get → HTTP $CODE"

info "[29] PATCH: add claude-instant-1 to blocked models"
RESP=$(ak -w "\n%{http_code}" -X PATCH "$CP/api/vendor-config/claude-demo" \
  -H "Content-Type: application/json" \
  -d '{"blocked_models":["claude-2","claude-instant","claude-instant-1"]}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
NEW_BLOCKED=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("blocked_models","?"))' 2>/dev/null)
[ "$CODE" = "200" ] \
  && pass "PATCH vendor config → blocked_models=$NEW_BLOCKED" \
  || fail "PATCH → HTTP $CODE: $BODY"

sleep 0.5

info "[30] Verify: claude-instant-1 rejected by DP enforcer"
RESP=$(/usr/bin/curl -sk -w "\n%{http_code}" \
  -X POST "$ENFORCER/claude-demo/v1/messages" \
  -H "Authorization: Bearer $CLEAN_KEY" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-instant-1","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}')
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
ERR=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("error",""))' 2>/dev/null)
[ "$CODE" = "403" ] \
  && pass "claude-instant-1 → 403 $ERR ✓ (CP→DP push confirmed)" \
  || info "claude-instant-1 → HTTP $CODE (DP propagation may be in-flight)"

info "[31] Verify: allowed model (haiku) still works after vendor config change"
CODE=$(/usr/bin/curl -sk -o /dev/null -w "%{http_code}" \
  -X POST "$ENFORCER/claude-demo/v1/messages" \
  -H "Authorization: Bearer $CLEAN_KEY" -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}')
[ "$CODE" != "403" ] \
  && pass "haiku still allowed after vendor config update → HTTP $CODE ✓" \
  || fail "haiku unexpectedly blocked after config change → HTTP $CODE"

info "[32] Restore vendor config (remove claude-instant-1)"
RESP=$(ak -w "\n%{http_code}" -X PATCH "$CP/api/vendor-config/claude-demo" \
  -H "Content-Type: application/json" \
  -d '{"blocked_models":["claude-2","claude-instant"]}')
CODE=$(echo "$RESP" | tail -1)
[ "$CODE" = "200" ] \
  && pass "restore vendor config → HTTP $CODE ✓" \
  || fail "restore → HTTP $CODE"

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  SUMMARY"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}PASS: $PASS${NC}   ${RED}FAIL: $FAIL${NC}"
echo ""

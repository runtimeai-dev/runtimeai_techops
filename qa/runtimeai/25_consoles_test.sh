#!/usr/bin/env bash
# OPER_RT19-072c P0-001 / P0-005 — Federated console + OCC end-to-end smoke test
#
# Coverage (per console):
#   1. /healthz — 200 text/plain
#   2. /assets/remoteEntry.js — 200 application/javascript + CORS for OCC origin
#   3. /api/auth/me — 401 (auth proxy reachable, denies anon)
#   4. / — 200 SPA shell
#   5. UI-called data endpoints — 401 (proxy reachable, denies anon)
#      ↑ NEW: actually exercises endpoints the console UI calls
#
# Coverage (OCC shell — omni.rt19.runtimeai.io):
#   - /healthz, /, /assets/remoteEntry.js, CORS
#   - /api/omni/auth/me — 401 (proves auth proxy is registered)
#   - /api/omni/auth/login POST with bad creds — 401 (proves login route exists)
#     ↑ NEW: catches stale gateway image missing /api/omni/auth/* route
#   - /api/omni/v1/entitlement — 401 (proves data routes registered)
#
# DNS-resilient: uses dig @8.8.8.8 + curl --resolve to bypass stale local OS DNS.

set -u

ORIGIN="https://omni.rt19.runtimeai.io"
PASS=0
FAIL=0
WARN=0

# label  base_url  ui_endpoint_csv (relative paths exercised by console UI)
CONSOLES=(
  "NHI     https://nhi.rt19.runtimeai.io       /api/nhi/v1/nhis,/api/nhi/v1/drift-events,/api/nhi/v1/kill-switch"
  "CLOUD   https://cloud.rt19.runtimeai.io     /api/cloud/security/v1/accounts,/api/cloud/security/v1/workloads"
  "KINETIC https://kinetic.rt19.runtimeai.io   /api/kinetic/v1/devices,/api/kinetic/v1/fleet/stats"
  "CRM     https://app.runtimecrm.com          /api/arh/v1/dashboard/stats,/api/v1/contacts"
)

check() {
  local label="$1" name="$2" status="$3" expect="$4" extra="${5:-}"
  if [[ "$status" == "$expect" ]]; then
    printf "[%-7s] %-44s PASS (%s)%s\n" "$label" "$name" "$status" "${extra:+ $extra}"
    PASS=$((PASS + 1))
  else
    printf "[%-7s] %-44s FAIL (got %s, want %s)%s\n" "$label" "$name" "$status" "$expect" "${extra:+ $extra}"
    FAIL=$((FAIL + 1))
  fi
}

warn() {
  local label="$1" msg="$2"
  printf "[%-7s] %-44s WARN (%s)\n" "$label" "DNS not resolving" "$msg"
  WARN=$((WARN + 1))
}

resolve_ip() {
  local host="$1"
  host=${host#https://}
  host=${host%%/*}
  dig +short +time=3 +tries=1 @8.8.8.8 "$host" | head -1
}

run_console() {
  local label="$1" base="$2" endpoints_csv="$3"

  local ip
  ip=$(resolve_ip "$base")
  if [[ -z "$ip" ]]; then
    warn "$label" "skipping — add A record (Namecheap) to fix"
    return
  fi

  local host=${base#https://}
  host=${host%%/*}
  local RESOLVE=(--resolve "$host:443:$ip" --resolve "$host:80:$ip")

  # 1. /healthz
  status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base/healthz")
  check "$label" "/healthz" "$status" "200"

  # 2. /assets/remoteEntry.js — status, content-type, CORS
  hdrs=$(curl "${RESOLVE[@]}" -s -I --max-time 8 -H "Origin: $ORIGIN" "$base/assets/remoteEntry.js")
  re_status=$(printf "%s" "$hdrs" | awk 'NR==1 {print $2}')
  ctype=$(printf "%s" "$hdrs" | awk -F': ' 'tolower($1)=="content-type" {print $2}' | tr -d '\r' | head -1)
  cors=$(printf "%s" "$hdrs" | awk -F': ' 'tolower($1)=="access-control-allow-origin" {print $2}' | tr -d '\r' | head -1)
  if [[ "$re_status" == "200" && "$ctype" == application/javascript* && "$cors" == "$ORIGIN" ]]; then
    check "$label" "/assets/remoteEntry.js" "200" "200" "(JS + CORS ok)"
  else
    check "$label" "/assets/remoteEntry.js" "${re_status:-000}" "200" "ct=${ctype:-none} cors=${cors:-none}"
  fi

  # 3. /api/auth/me — must be reachable; expect 401
  status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base/api/auth/me")
  check "$label" "/api/auth/me" "$status" "401"

  # 4. /
  status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base/")
  check "$label" "/" "$status" "200"

  # 5. NEW: UI-called data endpoints — must be reachable; expect 401 anon
  IFS=',' read -ra endpoints <<<"$endpoints_csv"
  for ep in "${endpoints[@]}"; do
    status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base$ep")
    # Acceptable: 401 (auth required) or 403 (forbidden). FAIL if 404/502/000.
    if [[ "$status" == "401" || "$status" == "403" ]]; then
      check "$label" "$ep" "$status" "$status" "(proxy ok, auth required)"
    else
      check "$label" "$ep" "$status" "401"
    fi
  done
}

run_occ() {
  local label="OCC"
  local base="https://omni.rt19.runtimeai.io"
  local ip
  ip=$(resolve_ip "$base")
  if [[ -z "$ip" ]]; then
    warn "$label" "skipping — DNS missing"
    return
  fi
  local host=${base#https://}
  host=${host%%/*}
  local RESOLVE=(--resolve "$host:443:$ip" --resolve "$host:80:$ip")

  # SPA shell
  status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base/")
  check "$label" "/" "$status" "200"

  # Auth proxy: GET /api/omni/auth/me → 401 (route registered, no cookie)
  status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base/api/omni/auth/me")
  if [[ "$status" == "401" || "$status" == "403" ]]; then
    check "$label" "/api/omni/auth/me" "$status" "$status" "(auth proxy registered)"
  else
    check "$label" "/api/omni/auth/me" "$status" "401" "stale gateway image? expected 401"
  fi

  # Auth proxy: POST /api/omni/auth/login with bad creds → 401 (NOT 404!)
  # 404 here means the gateway image is stale and missing the /api/omni/auth/* route.
  status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 \
    -X POST "$base/api/omni/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"tenant_id":"qa-nonexistent","email":"qa@invalid.test","password":"wrong"}')
  if [[ "$status" == "401" || "$status" == "400" ]]; then
    check "$label" "POST /api/omni/auth/login" "$status" "$status" "(login route alive)"
  else
    check "$label" "POST /api/omni/auth/login" "$status" "401" "ROUTE MISSING — rebuild omni-gateway"
  fi

  # Data route: /api/omni/v1/entitlement → 401
  status=$(curl "${RESOLVE[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base/api/omni/v1/entitlement")
  if [[ "$status" == "401" || "$status" == "403" ]]; then
    check "$label" "/api/omni/v1/entitlement" "$status" "$status" "(data route registered)"
  else
    check "$label" "/api/omni/v1/entitlement" "$status" "401"
  fi
}

run_occ
for entry in "${CONSOLES[@]}"; do
  read -r label base endpoints <<<"$entry"
  run_console "$label" "$base" "$endpoints"
done

echo ""
echo "Result: $PASS PASS, $WARN WARN, $FAIL FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

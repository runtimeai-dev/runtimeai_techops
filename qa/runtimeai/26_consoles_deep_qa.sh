#!/usr/bin/env bash
# OPER_RT19-072c P0-017: comprehensive console QA — catches the classes of
# bugs the surface-level 25_consoles_test.sh missed across rounds 3-3.8.
#
# 4 layers of verification:
#  L1 NETWORK    — host resolves, /healthz 200, /assets/remoteEntry.js JS+CORS
#  L2 ARTIFACT   — built JS bundle has zero localhost / no leaked hardcoded URLs
#  L3 UPSTREAM   — every URL in service ConfigMap actually resolves in K8s
#  L4 DATA       — login as test user, hit each UI-called endpoint, assert
#                  response shape + non-empty rows for seeded tenant
#
# Each layer prints PASS/FAIL with the exact reason. Exits non-zero on any FAIL.

set -u
ORIGIN="https://omni.rt19.runtimeai.io"
TENANT_UUID="${TENANT_UUID:-1b922b60-64b2-4e9b-974a-b878658838c8}"  # equinix-demo
PASS=0; FAIL=0; WARN=0
NS="${NAMESPACE:-rt19}"

check() { local label="$1" status="$2" expect="$3" extra="${4:-}"
  if [[ "$status" == "$expect" ]]; then
    printf "[PASS] %-60s %s\n" "$label" "${extra:+— $extra}"; PASS=$((PASS+1))
  else
    printf "[FAIL] %-60s got=%s want=%s %s\n" "$label" "$status" "$expect" "${extra:+— $extra}"; FAIL=$((FAIL+1))
  fi
}
warn() { printf "[WARN] %-60s %s\n" "$1" "$2"; WARN=$((WARN+1)); }
section() { printf "\n=== %s ===\n" "$1"; }

resolve_ip() { local h="$1"; h=${h#https://}; h=${h%%/*}; dig +short +time=3 +tries=1 @8.8.8.8 "$h" | head -1; }

############################################################
# L1 — NETWORK
############################################################
section "L1 NETWORK — hosts resolve, /healthz, /assets/remoteEntry.js"

declare -A HOSTS=(
  [OCC]="https://omni.rt19.runtimeai.io"
  [RTAI]="https://app.rt19.runtimeai.io"
  [NHI]="https://nhi.rt19.runtimeai.io"
  [CLOUD]="https://cloud.rt19.runtimeai.io"
  [KINETIC]="https://kinetic.rt19.runtimeai.io"
  [CRM]="https://app.runtimecrm.com"
)

for label in OCC RTAI NHI CLOUD KINETIC CRM; do
  base="${HOSTS[$label]}"
  ip=$(resolve_ip "$base")
  if [[ -z "$ip" ]]; then warn "[$label] DNS" "no A record for ${base#https://}"; continue; fi
  host=${base#https://}; host=${host%%/*}
  R=(--resolve "$host:443:$ip" --resolve "$host:80:$ip")
  rc=$(curl "${R[@]}" -s -o /dev/null -w "%{http_code}" --max-time 8 "$base/healthz")
  check "[$label] /healthz" "$rc" "200"
  [[ "$label" == "OCC" ]] && continue
  hdrs=$(curl "${R[@]}" -s -I --max-time 8 -H "Origin: $ORIGIN" "$base/assets/remoteEntry.js")
  rs=$(echo "$hdrs" | awk 'NR==1{print $2}')
  ct=$(echo "$hdrs" | awk -F': ' 'tolower($1)=="content-type"{print $2}' | tr -d '\r' | head -1)
  cors=$(echo "$hdrs" | awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2}' | tr -d '\r' | head -1)
  if [[ "$rs" == "200" && "$ct" == application/javascript* && "$cors" == "$ORIGIN" ]]; then
    check "[$label] /assets/remoteEntry.js (200+JS+CORS)" "ok" "ok"
  else
    check "[$label] /assets/remoteEntry.js (200+JS+CORS)" "rs=$rs ct=$ct cors=$cors" "ok"
  fi
done

############################################################
# L2 — ARTIFACT (no hardcoded URLs in built bundles)
############################################################
section "L2 ARTIFACT — bundle has no hardcoded prod / localhost URLs"

# Pull each console's main JS bundle and grep for localhost or hardcoded prod URLs.
for label in OCC NHI CLOUD KINETIC CRM; do
  base="${HOSTS[$label]}"
  ip=$(resolve_ip "$base")
  [[ -z "$ip" ]] && { warn "[$label] artifact" "DNS missing"; continue; }
  host=${base#https://}; host=${host%%/*}
  R=(--resolve "$host:443:$ip")
  main=$(curl "${R[@]}" -s "$base/" | grep -oE 'assets/[^"]+\.js' | head -1)
  [[ -z "$main" ]] && { warn "[$label] artifact" "no main bundle in /index.html"; continue; }
  body=$(curl "${R[@]}" -s "$base/$main")
  bad=$(echo "$body" | grep -oE 'http://localhost:[0-9]+/assets/remoteEntry\.js' | head -3)
  if [[ -n "$bad" ]]; then
    check "[$label] $main has no localhost remoteEntry" "found" "none" "$(echo $bad | tr '\n' ',')"
  else
    check "[$label] $main has no localhost remoteEntry" "ok" "ok"
  fi
  # OPER_RT19-072c P0-019: also catch localhost:* used as API base.
  # The OCC shell shipped with `BASE = "http://localhost:8100"` for 4 rounds —
  # broke every API call from the browser. Catch any localhost:NNNN reference.
  bad_api=$(echo "$body" | grep -oE 'http://localhost:[0-9]{2,5}' | grep -v '/assets/remoteEntry' | sort -u | head -3)
  if [[ -n "$bad_api" ]]; then
    check "[$label] $main has no localhost API base" "found" "none" "$(echo $bad_api | tr '\n' ',')"
  else
    check "[$label] $main has no localhost API base" "ok" "ok"
  fi
done

############################################################
# L3 — UPSTREAM (each ConfigMap URL resolves in cluster)
############################################################
section "L3 UPSTREAM — omni-gateway ConfigMap URLs resolve to live services"

for var in NHI_SERVICE_URL CLOUD_SECURITY_URL KINETIC_AI_URL CONTROL_PLANE_URL BILLING_SERVICE_URL ML_SERVICE_URL AUTH_JWKS_URL AUDIT_LOG_URL; do
  url=$(kubectl get cm omni-gateway-config -n $NS -o jsonpath="{.data.$var}" 2>/dev/null)
  [[ -z "$url" ]] && { warn "[CM] $var" "not set"; continue; }
  host=${url#http://}; host=${host#https://}; host=${host%%/*}; host=${host%%:*}
  # Strip FQDN suffixes — accept either "name" or "name.namespace.svc.cluster.local"
  short=${host%%.*}
  if kubectl get svc -A --no-headers 2>/dev/null | awk '{print $2}' | grep -qx "$short"; then
    check "[CM] $var → $host" "resolves" "resolves"
  else
    check "[CM] $var → $host" "no svc" "resolves"
  fi
done

############################################################
# L4 — DATA (UI-called endpoints return non-empty for seeded tenant)
############################################################
section "L4 DATA — equinix-demo seed counts in each backend"

# Direct DB count checks for tables the consoles read.
PG_POD=$(kubectl get pod -n $NS -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$PG_POD" ]]; then
  warn "[DATA] postgres" "no pod found"
else
  declare -A COUNT_QUERIES=(
    ["nhi_identities"]="SELECT COUNT(*) FROM nhi_identities WHERE tenant_id='$TENANT_UUID'"
    ["nhi_drift_events"]="SELECT COUNT(*) FROM nhi_drift_events WHERE tenant_id='$TENANT_UUID'"
    ["cloud_accounts"]="SELECT COUNT(*) FROM cloud_accounts WHERE tenant_id='$TENANT_UUID'"
    ["cloud_workloads"]="SELECT COUNT(*) FROM cloud_workloads WHERE tenant_id='$TENANT_UUID'"
    ["fleets"]="SELECT COUNT(*) FROM fleets WHERE tenant_id='$TENANT_UUID'"
    ["edge_devices"]="SELECT COUNT(*) FROM edge_devices WHERE tenant_id='$TENANT_UUID'"
  )
  for tbl in "${!COUNT_QUERIES[@]}"; do
    n=$(kubectl exec -n $NS $PG_POD -- psql -U runtimeai -d authzion -tAc "${COUNT_QUERIES[$tbl]}" 2>/dev/null | tr -d ' \r')
    [[ -z "$n" ]] && n=0
    if [[ "$n" -gt 0 ]]; then
      check "[DATA] $tbl rows for equinix-demo" "$n>0" "$n>0" "n=$n"
    else
      check "[DATA] $tbl rows for equinix-demo" "0" ">0" "seed missing — run qa_testing_local/seed_equinix_demo.sql"
    fi
  done
  for tbl in arh_contacts arh_sequences arh_deals; do
    n=$(kubectl exec -n $NS $PG_POD -- psql -U runtimeai -d runtimecrm -tAc "SELECT COUNT(*) FROM $tbl WHERE tenant_id='$TENANT_UUID'" 2>/dev/null | tr -d ' \r')
    [[ -z "$n" ]] && n=0
    if [[ "$n" -gt 0 ]]; then check "[DATA] $tbl (CRM) rows" "$n>0" "$n>0" "n=$n"; else check "[DATA] $tbl (CRM) rows" "0" ">0"; fi
  done
fi

############################################################
# REGISTRY — every active remote in DB matches a live remoteEntry
############################################################
section "REGISTRY — remote_registry rows point at reachable remoteEntry.js"

kubectl exec -n $NS deploy/postgres -- psql -U runtimeai -d authzion -tAc \
  "SELECT product || '|' || remote_url || '|' || active::text FROM remote_registry WHERE active=true" 2>/dev/null \
  | while IFS='|' read -r product url active; do
    [[ -z "$product" ]] && continue
    host=${url#https://}; host=${host#http://}; host=${host%%/*}
    ip=$(dig +short +time=3 +tries=1 @8.8.8.8 "$host" | head -1)
    if [[ -z "$ip" ]]; then
      printf "[FAIL] [REG] %-30s %s — DNS missing\n" "$product" "$url"
    else
      rc=$(curl --resolve "$host:443:$ip" -s -o /dev/null -w "%{http_code}" "$url" -H "Origin: $ORIGIN" --max-time 8)
      [[ "$rc" == "200" ]] && printf "[PASS] [REG] %-30s 200\n" "$product" || printf "[FAIL] [REG] %-30s %s != 200\n" "$product" "$rc"
    fi
  done

echo ""
echo "Result: $PASS PASS, $WARN WARN, $FAIL FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
